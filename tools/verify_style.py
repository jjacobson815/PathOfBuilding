#!/usr/bin/env python3
"""Style regression gate (Phase 2 / Phase 14).

Diffs captured screenshots against committed baseline references using
[`screenshot_diff.py`](screenshot_diff.py) and exits non-zero if any view's
SSIM falls below its threshold.

Usage:
  python tools/verify_style.py [--capture-dir DIR] [--baseline-dir DIR] [--threshold 0.85]
  python tools/verify_style.py [legacy.png new.png label ...]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import screenshot_diff as sd  # noqa: E402

DEFAULT_BASELINE_DIR = os.path.join("app", "tests", "capture-baseline")
DEFAULT_CAPTURE_DIR = "captures"

# Per-view SSIM thresholds. Tree rendering can have minor subpixel variance
# across GPU drivers, while static forms/tables should match more closely.
VIEW_THRESHOLDS = {
    "list": 0.85,
    "import": 0.85,
    "tree": 0.80,
    "skills": 0.85,
    "items": 0.85,
    "calcs": 0.85,
    "config": 0.85,
    "notes": 0.85,
    "party": 0.85,
    "compare": 0.85,
}


def parse_view_thresholds(raw_items):
    overrides = {}
    for item in raw_items or []:
        if "=" not in item:
            raise ValueError(f"Expected view=float for --view-threshold, got: {item}")
        view, val = item.split("=", 1)
        overrides[view.strip()] = float(val)
    return overrides


def main():
    parser = argparse.ArgumentParser(
        description="Compare captured QML screenshots against baseline PNGs using SSIM.",
    )
    parser.add_argument(
        "--capture-dir",
        default=DEFAULT_CAPTURE_DIR,
        help=f"Directory containing captured <view>.png files (default: {DEFAULT_CAPTURE_DIR})",
    )
    parser.add_argument(
        "--baseline-dir",
        default=DEFAULT_BASELINE_DIR,
        help=f"Directory containing baseline <view>.png files (default: {DEFAULT_BASELINE_DIR})",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=None,
        help="Override global SSIM threshold for all views (default: per-view thresholds)",
    )
    parser.add_argument(
        "--view-threshold",
        action="append",
        metavar="VIEW=FLOAT",
        help="Override SSIM threshold for a specific view (repeatable)",
    )
    parser.add_argument(
        "positional",
        nargs="*",
        help="Optional explicit triples: legacy.png new.png label ...",
    )
    args = parser.parse_args()

    try:
        view_overrides = parse_view_thresholds(args.view_threshold)
    except ValueError as exc:
        parser.error(str(exc))

    pairs = []
    pos = args.positional
    if pos:
        if len(pos) < 2:
            parser.error("Positional mode requires at least <legacy.png> <new.png> [label]")
        i = 0
        while i < len(pos):
            if i + 1 >= len(pos):
                parser.error(f"Unpaired positional argument: {pos[i]}")
            label = pos[i + 2] if i + 2 < len(pos) else f"pair_{len(pairs)}"
            thresh = args.threshold if args.threshold is not None else 0.85
            pairs.append((pos[i], pos[i + 1], label, thresh))
            i += 3
    else:
        for view, default_thresh in VIEW_THRESHOLDS.items():
            thresh = (
                view_overrides[view]
                if view in view_overrides
                else (args.threshold if args.threshold is not None else default_thresh)
            )
            pairs.append((
                os.path.join(args.baseline_dir, f"{view}.png"),
                os.path.join(args.capture_dir, f"{view}.png"),
                view,
                thresh,
            ))

    ok = True
    for leg, new, label, thresh in pairs:
        try:
            r = sd.compare(leg, new, label)
        except FileNotFoundError as e:
            print(f"!! missing file for {label}: {e}")
            ok = False
            continue
        if r["blank"]:
            print(f"REGRESSION: {label} rendered blank/flat")
            ok = False
        elif r["ssim"] < thresh:
            print(f"REGRESSION: {label} SSIM {r['ssim']:.3f} < {thresh:.2f}")
            ok = False
        else:
            print(f"OK: {label} SSIM {r['ssim']:.3f} >= {thresh:.2f}")

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
