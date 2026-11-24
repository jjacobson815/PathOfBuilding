#!/usr/bin/env python3
"""Repeatable per-league upstream-sync tool for Path of Building Qt/QML port.

Features:
- CR-normalized classification of src/Modules/, src/Data/, src/Classes/, and runtime/lua/.
- LF-space 3-way merge strategy for the 4 sanctioned src/ seams + stock-LuaJIT compat files,
  with CRLF restoration on write.
- Stock LuaJIT (`luajit -bl`) bytecode/syntax compatibility check.
- Safe `--dry-run` mode (default when `--apply` is not given) that exits 0 even if the
  upstream ref is not fetched or luajit is unavailable.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

SYNC_DIRS = (
    "src/Modules",
    "src/Data",
    "src/Classes",
    "runtime/lua",
)

MERGE_SEAM_FILES = {
    "src/Modules/Build.lua",
    "src/Modules/Main.lua",
    "src/Modules/Data.lua",
    "src/Modules/UITheme.lua",
    "src/Classes/CompareBuySimilar.lua",
}


def run_git(repo_root: Path, args: list[str], binary: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args],
        cwd=repo_root,
        capture_output=True,
        text=not binary,
    )


def normalize_lf(data: bytes) -> bytes:
    return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def to_crlf(data: bytes) -> bytes:
    return normalize_lf(data).replace(b"\n", b"\r\n")


def find_luajit() -> str | None:
    on_path = shutil.which("luajit")
    if on_path:
        return on_path
    candidates = [
        Path("C:/msys64/mingw64/bin/luajit.exe"),
        Path("/c/msys64/mingw64/bin/luajit"),
        Path("/usr/bin/luajit"),
        Path("/usr/local/bin/luajit"),
    ]
    for cand in candidates:
        if cand.is_file():
            return str(cand)
    return None


def list_local_files(repo_root: Path) -> set[str]:
    files: set[str] = set()
    for rel_dir in SYNC_DIRS:
        base = repo_root / rel_dir
        if not base.is_dir():
            continue
        for p in base.rglob("*"):
            if p.is_file():
                files.add(p.relative_to(repo_root).as_posix())
    return files


def list_ref_files(repo_root: Path, ref: str) -> set[str]:
    res = run_git(repo_root, ["ls-tree", "-r", "--name-only", ref, "--", *SYNC_DIRS])
    if res.returncode != 0:
        return set()
    return {line.strip().replace("\\", "/") for line in res.stdout.splitlines() if line.strip()}


def read_git_blob(repo_root: Path, ref: str, rel_path: str) -> bytes | None:
    res = run_git(repo_root, ["show", f"{ref}:{rel_path}"], binary=True)
    if res.returncode != 0:
        return None
    return res.stdout


def classify_files(repo_root: Path, upstream_ref: str) -> dict[str, list[str]]:
    local_files = list_local_files(repo_root)
    upstream_files = list_ref_files(repo_root, upstream_ref)
    all_paths = sorted(local_files | upstream_files)

    buckets: dict[str, list[str]] = defaultdict(list)
    for rel in all_paths:
        in_local = rel in local_files
        in_up = rel in upstream_files
        if in_local and not in_up:
            buckets["qt_only"].append(rel)
            continue
        if in_up and not in_local:
            buckets["upstream_only"].append(rel)
            continue

        local_bytes = (repo_root / rel).read_bytes()
        up_bytes = read_git_blob(repo_root, upstream_ref, rel)
        if up_bytes is None:
            buckets["qt_only"].append(rel)
            continue

        if local_bytes == up_bytes:
            buckets["unchanged"].append(rel)
        elif normalize_lf(local_bytes) == normalize_lf(up_bytes):
            buckets["crlf_only"].append(rel)
        else:
            buckets["changed"].append(rel)
    return buckets


def merge_seam_lf_to_crlf(
    repo_root: Path,
    rel_path: str,
    base_ref: str,
    upstream_ref: str,
) -> tuple[bool, bytes, str]:
    """3-way merge rel_path in LF space and return CRLF bytes."""
    local_lf = normalize_lf((repo_root / rel_path).read_bytes())
    up_raw = read_git_blob(repo_root, upstream_ref, rel_path)
    base_raw = read_git_blob(repo_root, base_ref, rel_path) if base_ref else None

    if up_raw is None:
        return True, to_crlf(local_lf), "kept qt-only file"
    up_lf = normalize_lf(up_raw)
    base_lf = normalize_lf(base_raw) if base_raw is not None else b""

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        cur_p = tmp / "current"
        base_p = tmp / "base"
        up_p = tmp / "upstream"
        cur_p.write_bytes(local_lf)
        base_p.write_bytes(base_lf)
        up_p.write_bytes(up_lf)

        res = subprocess.run(
            ["git", "merge-file", "-p", str(cur_p), str(base_p), str(up_p)],
            capture_output=True,
        )
        if res.returncode == 0:
            return True, to_crlf(res.stdout), "clean 3-way LF merge -> CRLF"
        if res.returncode > 0:
            return False, to_crlf(res.stdout), f"merge conflict ({res.returncode} conflict(s))"
        return False, b"", f"git merge-file failed: {res.stderr.decode(errors='replace')}"


def check_luajit_syntax(repo_root: Path, luajit_bin: str) -> tuple[bool, int, list[str]]:
    lua_files: list[Path] = []
    for sub in ("src/Modules", "src/Classes", "src/Data"):
        d = repo_root / sub
        if d.is_dir():
            lua_files.extend(sorted(d.rglob("*.lua")))

    failures: list[str] = []
    for f in lua_files:
        res = subprocess.run(
            [luajit_bin, "-bl", str(f)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        if res.returncode != 0:
            rel = f.relative_to(repo_root).as_posix()
            failures.append(f"{rel}: {res.stderr.strip()}")
    return len(failures) == 0, len(lua_files), failures


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Per-league upstream-sync classifier, 3-way LF->CRLF seam merger, and LuaJIT syntax verifier."
    )
    parser.add_argument(
        "--upstream",
        default="origin/dev",
        help="Upstream git ref to sync against (default: origin/dev).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report classification and sync plan without modifying files (default unless --apply is passed).",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply pure file copies/additions and 3-way LF->CRLF seam merges to the working tree.",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="Path to repository root (defaults to parent of tools/).",
    )
    args = parser.parse_args(argv)
    dry_run = args.dry_run or not args.apply
    repo_root = args.repo_root.resolve()

    print(f"upstream_sync: mode={'DRY-RUN' if dry_run else 'APPLY'}, upstream={args.upstream}")

    ref_ok = run_git(repo_root, ["rev-parse", "--verify", "--quiet", args.upstream]).returncode == 0
    if not ref_ok:
        msg = f"upstream ref '{args.upstream}' is not available locally (fetch upstream or pass --upstream <ref>)."
        if dry_run:
            print(f"[DRY-RUN] {msg}")
            print("[DRY-RUN] Planned steps when ref is available:")
            print("  1. CR-normalized classify of " + ", ".join(SYNC_DIRS))
            print("  2. Copy/add pure upstream files; preserve qt-only sanctioned files")
            print("  3. LF-space 3-way merge + CRLF restore for: " + ", ".join(sorted(MERGE_SEAM_FILES)))
            print("  4. Verify stock LuaJIT compatibility with `luajit -bl`")
        else:
            print(f"[FAIL] {msg}", file=sys.stderr)
            return 1
    else:
        buckets = classify_files(repo_root, args.upstream)
        print("CR-normalized classification:")
        for key in ("unchanged", "crlf_only", "changed", "qt_only", "upstream_only"):
            print(f"  {key:13s}: {len(buckets[key])}")

        seam_changed = [p for p in buckets["changed"] if p in MERGE_SEAM_FILES]
        pure_changed = [p for p in buckets["changed"] if p not in MERGE_SEAM_FILES]
        print(f"  pure_changed : {len(pure_changed)}")
        print(f"  seam_changed : {len(seam_changed)} ({', '.join(seam_changed) if seam_changed else 'none'})")

        if not dry_run:
            base_res = run_git(repo_root, ["merge-base", "HEAD", args.upstream])
            base_ref = base_res.stdout.strip() if base_res.returncode == 0 else ""

            for rel in pure_changed + buckets["upstream_only"]:
                blob = read_git_blob(repo_root, args.upstream, rel)
                if blob is not None:
                    dest = repo_root / rel
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(to_crlf(blob))

            conflicts: list[str] = []
            for rel in seam_changed:
                ok, merged_bytes, note = merge_seam_lf_to_crlf(repo_root, rel, base_ref, args.upstream)
                print(f"  merge {rel}: {note}")
                if ok:
                    (repo_root / rel).write_bytes(merged_bytes)
                else:
                    conflicts.append(rel)
            if conflicts:
                print(f"[FAIL] 3-way merge conflicts in: {', '.join(conflicts)}", file=sys.stderr)
                return 1

    luajit_bin = find_luajit()
    if luajit_bin is None:
        print("[SKIP] luajit binary not found on PATH or MSYS2; skipping `luajit -bl` syntax check.")
    else:
        ok, count, failures = check_luajit_syntax(repo_root, luajit_bin)
        if ok:
            print(f"[PASS] luajit -bl: {count} Lua file(s) parsed cleanly ({luajit_bin}).")
        else:
            print(f"[FAIL] luajit -bl: {len(failures)} error(s):\n  " + "\n  ".join(failures), file=sys.stderr)
            return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
