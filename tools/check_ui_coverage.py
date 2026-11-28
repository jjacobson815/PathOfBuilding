#!/usr/bin/env python3
"""Generate docs/ui-specs/COVERAGE.md mapping QML files -> specs -> tests -> AC counts."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_QML = ROOT / "app" / "qml"
SPEC_VIEWS = ROOT / "docs" / "ui-specs" / "views"
SPEC_COMPONENTS = ROOT / "docs" / "ui-specs" / "components"
UI_TESTS = ROOT / "app" / "tests" / "ui"
OUT_PATH = ROOT / "docs" / "ui-specs" / "COVERAGE.md"


def count_acs(spec_path: Path) -> int:
    text = spec_path.read_text(encoding="utf-8", errors="replace")
    return len(set(re.findall(r"\bAC-\d+\b", text)))


def main() -> int:
    qml_files = sorted(APP_QML.rglob("*.qml"))
    view_specs = {p.stem: p for p in SPEC_VIEWS.glob("*.md")}
    comp_specs = {p.stem: p for p in SPEC_COMPONENTS.glob("*.md")}
    test_files = {p.stem: p for p in UI_TESTS.rglob("tst_*.qml")}

    rows: list[str] = []
    covered_specs = 0
    covered_tests = 0
    total_acs = 0

    for qml in qml_files:
        rel_qml = qml.relative_to(ROOT).as_posix()
        stem = qml.stem
        spec = view_specs.get(stem) or comp_specs.get(stem)
        if spec is None and stem == "main":
            spec = view_specs.get("MainShell")
        tst = test_files.get(f"tst_{stem}")
        if tst is None and stem == "main":
            tst = test_files.get("tst_MainShell")

        spec_str = spec.relative_to(ROOT).as_posix() if spec else "—"
        tst_str = tst.relative_to(ROOT).as_posix() if tst else "—"
        acs = count_acs(spec) if spec else 0

        if spec:
            covered_specs += 1
        if tst:
            covered_tests += 1
        total_acs += acs
        rows.append(f"| `{rel_qml}` | `{spec_str}` | `{tst_str}` | {acs} |")

    lines = [
        "# PoB-Qt UI Spec & Test Coverage Matrix",
        "",
        f"- **Total QML files:** {len(qml_files)}",
        f"- **Mapped to specs:** {covered_specs}/{len(qml_files)}",
        f"- **Mapped to QuickTest suites:** {covered_tests}/{len(qml_files)}",
        f"- **Total Acceptance Criteria (AC-XX):** {total_acs}",
        "",
        "| QML File | UI Spec | QuickTest Suite | AC Count |",
        "| --- | --- | --- | ---: |",
        *rows,
        "",
    ]
    OUT_PATH.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"COVERAGE OK: {len(qml_files)} QML files, {covered_specs} specs, {covered_tests} tests, {total_acs} ACs -> {OUT_PATH.relative_to(ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
