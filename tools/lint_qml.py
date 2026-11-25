#!/usr/bin/env python3
"""Static and qmllint check for PoB-Qt QML sources and QuickTest suites."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_QML = ROOT / "app" / "qml"
UI_TESTS = ROOT / "app" / "tests" / "ui"
QRC_PATH = APP_QML / "qml.qrc"


def find_qmllint() -> str | None:
    exe = shutil.which("qmllint") or shutil.which("qmllint.exe")
    if exe:
        return exe
    candidate = Path("C:/msys64/mingw64/bin/qmllint.exe")
    if candidate.exists():
        return str(candidate)
    return None


def collect_qml_files(base: Path) -> list[Path]:
    if not base.exists():
        return []
    return sorted(base.rglob("*.qml"))


def check_qrc_coverage() -> list[str]:
    errors: list[str] = []
    if not QRC_PATH.exists():
        return [f"Missing QRC file: {QRC_PATH}"]
    tree = ET.parse(QRC_PATH)
    listed = set()
    for node in tree.findall(".//file"):
        if node.text:
            listed.add(node.text.strip().replace("\\", "/"))

    for ext in ("*.qml", "*.js"):
        for f in sorted(APP_QML.rglob(ext)):
            rel = f.relative_to(APP_QML).as_posix()
            if rel not in listed:
                errors.append(f"Unregistered QML/JS asset missing from app/qml/qml.qrc: {rel}")
    return errors


def check_static_rules(qml_files: list[Path]) -> list[str]:
    errors: list[str] = []
    array_is_array_re = re.compile(r"\bArray\.isArray\s*\(")
    popup_root_keys_re = re.compile(r"^\s*PopupBase\s*\{", re.MULTILINE)

    for path in qml_files:
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8", errors="replace")

        if path.is_relative_to(APP_QML):
            for idx, line in enumerate(text.splitlines(), 1):
                if array_is_array_re.search(line):
                    errors.append(
                        f"{rel}:{idx}: raw Array.isArray() is forbidden on Lua bridge values; use QmlBridge.toArray()"
                    )

        if popup_root_keys_re.search(text):
            # Check top-level body of PopupBase root for direct Keys.on*
            depth = 0
            in_root = False
            for idx, line in enumerate(text.splitlines(), 1):
                if not in_root and "PopupBase" in line and "{" in line:
                    in_root = True
                    depth = line.count("{") - line.count("}")
                    continue
                if in_root:
                    if depth == 1 and re.search(r"^\s*Keys\.on\w+\s*:", line):
                        errors.append(
                            f"{rel}:{idx}: Keys.on* attached directly to PopupBase root (attach to content Item instead)"
                        )
                    depth += line.count("{") - line.count("}")
                    if depth <= 0:
                        in_root = False
    return errors


def run_qmllint(qmllint: str, qml_files: list[Path]) -> list[str]:
    if not qml_files:
        return []
    env = os.environ.copy()
    mingw_bin = "C:\\msys64\\mingw64\\bin"
    if os.path.isdir(mingw_bin) and mingw_bin not in env.get("PATH", ""):
        env["PATH"] = mingw_bin + os.pathsep + env.get("PATH", "")

    cmd = [
        qmllint,
        "-I", str(APP_QML),
        "-I", str(APP_QML / "components"),
        "-I", str(APP_QML / "views"),
        "--unqualified", "disable",
        "--missing-property", "disable",
        "--missing-type", "disable",
        "--unused-imports", "disable",
        "--import", "disable",
        "--compiler", "disable",
    ] + [str(p) for p in qml_files]

    proc = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if proc.returncode != 0:
        out = (proc.stdout + "\n" + proc.stderr).strip()
        return [f"qmllint failed (exit {proc.returncode}):\n{out}"]
    return []


def main() -> int:
    app_qml_files = collect_qml_files(APP_QML)
    test_qml_files = collect_qml_files(UI_TESTS)
    all_qml = app_qml_files + test_qml_files

    errors: list[str] = []
    errors.extend(check_qrc_coverage())
    errors.extend(check_static_rules(app_qml_files))

    qmllint = find_qmllint()
    if qmllint:
        errors.extend(run_qmllint(qmllint, all_qml))
    else:
        print("WARN: qmllint not found on PATH; skipping qmllint pass", file=sys.stderr)

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    print(f"LINT OK: {len(app_qml_files)} app QML + {len(test_qml_files)} test QML files checked")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
