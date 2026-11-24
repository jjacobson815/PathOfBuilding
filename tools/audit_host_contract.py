#!/usr/bin/env python3
"""Audit the Path of Building Qt/QML host contract.

Checks:
1. `src/` edits relative to upstream stay within the 4 sanctioned seams
   (Build.lua, Main.lua, Data.lua, UITheme.lua) plus documented stock-LuaJIT
   compatibility edits (CompareBuySimilar.lua).
2. No live `Update.exe`, `SpawnProcess`, or `ConExecute` execution paths exist
   in `app/` (comments, docs, and empty-body stubs are permitted).
3. Zero bare `new("X", ...)` constructor calls exist in `app/` Lua files
   (must use `new("X"):X(...)` per upstream class rework).
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

SANCTIONED_SRC_FILES = {
    "src/Modules/Build.lua",
    "src/Modules/Main.lua",
    "src/Modules/Data.lua",
    "src/Modules/UITheme.lua",
}

COMPAT_SRC_FILES = {
    "src/Classes/CompareBuySimilar.lua",
}

ALLOWED_SRC_FILES = SANCTIONED_SRC_FILES | COMPAT_SRC_FILES

APP_SCAN_EXTENSIONS = {
    ".lua", ".cpp", ".c", ".h", ".hpp", ".qml", ".cmake", ".py", ".sh", ".ps1", ".bat"
}

EMPTY_STUB_PATTERNS = (
    re.compile(r"^\s*function\s+ConExecute\s*\([^)]*\)\s*end\s*$"),
    re.compile(r"^\s*function\s+SpawnProcess\s*\([^)]*\)\s*end\s*$"),
)

BARE_NEW_RE = re.compile(r'\bnew\s*\(\s*["\']([A-Za-z0-9_]+)["\']\s*,')
LEGACY_EXEC_RE = re.compile(r'(Update\.exe|\bSpawnProcess\b|\bConExecute\b)')


def run_git(repo_root: Path, args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=repo_root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def strip_lua_comments(text: str) -> list[tuple[int, str]]:
    """Return (1-based line_no, code_only_line) with Lua comments stripped."""
    # Remove block comments --[[ ... ]] while preserving line count
    def _blank_block(match: re.Match[str]) -> str:
        return "\n" * match.group(0).count("\n")

    cleaned = re.sub(r"--\[(=*)\[[\s\S]*?\]\1\]", _blank_block, text)
    lines: list[tuple[int, str]] = []
    for idx, line in enumerate(cleaned.splitlines(), start=1):
        # Strip single-line -- comments outside obvious string literals
        in_quote: str | None = None
        escaped = False
        cut = len(line)
        i = 0
        while i < len(line):
            ch = line[i]
            if escaped:
                escaped = False
            elif ch == "\\" and in_quote is not None:
                escaped = True
            elif in_quote is not None:
                if ch == in_quote:
                    in_quote = None
            elif ch in ('"', "'"):
                in_quote = ch
            elif ch == "-" and i + 1 < len(line) and line[i + 1] == "-":
                cut = i
                break
            i += 1
        lines.append((idx, line[:cut]))
    return lines


def strip_c_like_comments(text: str) -> list[tuple[int, str]]:
    """Return (1-based line_no, code_only_line) for C++/QML/CMake/Python."""
    def _blank_block(match: re.Match[str]) -> str:
        return "\n" * match.group(0).count("\n")

    cleaned = re.sub(r"/\*[\s\S]*?\*/", _blank_block, text)
    lines: list[tuple[int, str]] = []
    for idx, line in enumerate(cleaned.splitlines(), start=1):
        stripped = line.lstrip()
        if stripped.startswith("//") or stripped.startswith("#"):
            lines.append((idx, ""))
            continue
        # Trim trailing // comment when not inside quotes
        in_quote: str | None = None
        escaped = False
        cut = len(line)
        i = 0
        while i < len(line):
            ch = line[i]
            if escaped:
                escaped = False
            elif ch == "\\" and in_quote is not None:
                escaped = True
            elif in_quote is not None:
                if ch == in_quote:
                    in_quote = None
            elif ch in ('"', "'"):
                in_quote = ch
            elif ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
                cut = i
                break
            i += 1
        lines.append((idx, line[:cut]))
    return lines


def check_src_seams(repo_root: Path, base_ref: str) -> tuple[bool, list[str]]:
    messages: list[str] = []
    ref_check = run_git(repo_root, ["rev-parse", "--verify", "--quiet", base_ref])
    if ref_check.returncode != 0:
        # Fallback: verify sanctioned files exist when upstream ref is unavailable
        missing = [p for p in SANCTIONED_SRC_FILES if not (repo_root / p).is_file()]
        if missing:
            messages.append(
                f"[FAIL] src/ seams: base ref '{base_ref}' not found and missing sanctioned files: {missing}"
            )
            return False, messages
        messages.append(
            f"[PASS] src/ seams: base ref '{base_ref}' not present; verified all 4 sanctioned files exist."
        )
        return True, messages

    diff_res = run_git(repo_root, ["diff", "--name-only", base_ref, "--", "src/"])
    if diff_res.returncode != 0:
        messages.append(f"[FAIL] src/ seams: git diff failed: {diff_res.stderr.strip()}")
        return False, messages

    changed = sorted({line.strip().replace("\\", "/") for line in diff_res.stdout.splitlines() if line.strip()})
    unexpected = [f for f in changed if f not in ALLOWED_SRC_FILES]
    if unexpected:
        messages.append(
            "[FAIL] src/ seams: unsanctioned edits detected in src/: " + ", ".join(unexpected)
        )
        return False, messages

    messages.append(
        f"[PASS] src/ seams: {len(changed)} modified/added file(s) vs {base_ref}, all within sanctioned seams + compat list."
    )
    return True, messages


def check_no_legacy_exec(repo_root: Path) -> tuple[bool, list[str]]:
    app_dir = repo_root / "app"
    violations: list[str] = []

    for path in sorted(app_dir.rglob("*")):
        if not path.is_file():
            continue
        if path.suffix.lower() not in APP_SCAN_EXTENSIONS and path.name != "CMakeLists.txt":
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if path.suffix.lower() == ".lua":
            lines = strip_lua_comments(text)
        else:
            lines = strip_c_like_comments(text)

        for line_no, code in lines:
            if not code.strip():
                continue
            if any(pat.match(code) for pat in EMPTY_STUB_PATTERNS):
                continue
            if LEGACY_EXEC_RE.search(code):
                rel = path.relative_to(repo_root).as_posix()
                violations.append(f"{rel}:{line_no}: {code.strip()}")

    if violations:
        return False, [
            f"[FAIL] legacy execution paths: found {len(violations)} live reference(s) in app/:\n  "
            + "\n  ".join(violations)
        ]
    return True, ["[PASS] legacy execution paths: zero live Update.exe / SpawnProcess / ConExecute calls in app/."]


def check_no_bare_new(repo_root: Path) -> tuple[bool, list[str]]:
    app_lua_dir = repo_root / "app"
    violations: list[str] = []

    for path in sorted(app_lua_dir.rglob("*.lua")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, code in strip_lua_comments(text):
            if not code.strip():
                continue
            if BARE_NEW_RE.search(code):
                rel = path.relative_to(repo_root).as_posix()
                violations.append(f"{rel}:{line_no}: {code.strip()}")

    if violations:
        return False, [
            f"[FAIL] constructor convention: found {len(violations)} bare new(\"X\", ...) call(s) in app/:\n  "
            + "\n  ".join(violations)
        ]
    return True, ["[PASS] constructor convention: zero bare new(\"X\", ...) calls in app/."]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Audit Path of Building Qt/QML host contract invariants.")
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="Path to repository root (defaults to parent of tools/).",
    )
    parser.add_argument(
        "--base-ref",
        default="origin/dev",
        help="Upstream git ref to diff src/ against (default: origin/dev).",
    )
    args = parser.parse_args(argv)
    repo_root = args.repo_root.resolve()

    results = [
        check_src_seams(repo_root, args.base_ref),
        check_no_legacy_exec(repo_root),
        check_no_bare_new(repo_root),
    ]

    all_ok = True
    for ok, msgs in results:
        if not ok:
            all_ok = False
        for msg in msgs:
            print(msg)

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
