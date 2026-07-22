#!/usr/bin/env python3
"""Style regression gate (Phase 2).

Diffs current screenshots against the legacy references using
[`screenshot_diff.py`](screenshot_diff.py) and exits non-zero if any view's
SSIM falls below the threshold. Wire this into CI / a pre-launch check so
"beautify" is objectively measurable.

Usage:
  python tools/verify_style.py [--threshold 0.85] [legacy.png new.png label ...]
Default pairs: skill_tree + import (legacy vs new).
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import screenshot_diff as sd  # noqa: E402


def main():
    args = sys.argv[1:]
    threshold = 0.85
    capture_dir = "captures"
    pairs = []
    i = 0
    while i < len(args):
        if args[i] == "--threshold":
            threshold = float(args[i + 1])
            i += 2
            continue
        if args[i] == "--capture-dir":
            capture_dir = args[i + 1]
            i += 2
            continue
        if i + 1 < len(args):
            label = args[i + 2] if i + 2 < len(args) else "cli"
            pairs.append((args[i], args[i + 1], label))
            i += 3
        else:
            print(f"!! unpaired arg: {args[i]}")
            i += 1

    if not pairs:
        # Headless capture mapping: <capture_dir>/<view>.png vs legacy reference.
        # The capture harness (pob-qt --capture) writes lowercase view ids, e.g.
        # captures/tree.png and captures/import.png.
        pairs = [
            ("skill_tree/legacy.png", f"{capture_dir}/tree.png", "skill_tree"),
            ("import/legacy.png", f"{capture_dir}/import.png", "import"),
        ]

    ok = True
    for leg, new, label in pairs:
        try:
            r = sd.compare(leg, new, label)
        except FileNotFoundError as e:
            print(f"!! missing file for {label}: {e}")
            ok = False
            continue
        if r["ssim"] < threshold:
            print(f"REGRESSION: {label} SSIM {r['ssim']:.3f} < {threshold}")
            ok = False
        else:
            print(f"OK: {label} SSIM {r['ssim']:.3f} >= {threshold}")

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
