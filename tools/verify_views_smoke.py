#!/usr/bin/env python3
"""Smoke gate for captured QML views and runtime logs (Phase 14.3).

Validates that:
  1. `_status.log` exists in `<capture_dir>` and reports captured views.
  2. All 9 expected views (or the views specified via `--views` / present in
     `_status.log`) exist as non-empty, non-blank PNG images.
  3. Zero QML warnings or errors appear in `pob-qt-main.log` or capture logs.

Usage:
  python tools/verify_views_smoke.py <capture_dir> [--log PATH] [--views v1,v2,...]
"""
import argparse
import math
import os
import re
import struct
import sys
import zlib

try:
    import numpy as np
    from PIL import Image
    _HAS_PIL_NUMPY = True
except ImportError:
    _HAS_PIL_NUMPY = False

EXPECTED_VIEWS = [
    "list",
    "import",
    "tree",
    "skills",
    "items",
    "calcs",
    "config",
    "notes",
    "party",
]

QML_ERROR_PATTERNS = [
    re.compile(r"\bQML\b.*(?:Error|Warning|TypeError|ReferenceError|SyntaxError)", re.IGNORECASE),
    re.compile(r"qrc:/[^\s]+:\d+:\d+:"),
    re.compile(r"\b(?:TypeError|ReferenceError|SyntaxError)\b:"),
    re.compile(r"QQmlApplicationEngine failed to load", re.IGNORECASE),
    re.compile(r"module\s+\"[^\"]+\"\s+is not installed", re.IGNORECASE),
    re.compile(r"\bis not a type\b", re.IGNORECASE),
    re.compile(r"Cannot assign to non-existent property", re.IGNORECASE),
    re.compile(r"\b(?:CRITICAL|FATAL)\b:", re.IGNORECASE),
]


def _check_png_stdlib(path):
    """Pure-stdlib PNG header + non-blank pixel check (no numpy/PIL needed)."""
    with open(path, "rb") as fh:
        raw = fh.read()
    if len(raw) < 33 or raw[:8] != b"\x89PNG\r\n\x1a\n":
        return False, "invalid PNG signature"
    pos = 8
    w = h = bit_depth = color_type = 0
    idat = bytearray()
    while pos + 8 <= len(raw):
        length, ctype = struct.unpack(">I4s", raw[pos:pos + 8])
        pos += 8
        chunk = raw[pos:pos + length]
        pos += length + 4  # skip CRC
        if ctype == b"IHDR" and len(chunk) >= 13:
            w, h, bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])
        elif ctype == b"IDAT":
            idat.extend(chunk)
        elif ctype == b"IEND":
            break
    if w < 100 or h < 100:
        return False, f"unexpectedly small ({w}x{h})"
    if not idat:
        return False, "missing IDAT chunk"
    try:
        decompressed = zlib.decompress(bytes(idat))
    except zlib.error as exc:
        return False, f"corrupt PNG IDAT ({exc})"
    # Sample bytes across scanlines to confirm non-flat render.
    bpp_map = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
    channels = bpp_map.get(color_type, 4)
    stride = 1 + w * channels * max(1, bit_depth // 8)
    sample = []
    step_y = max(1, h // 40)
    step_x = max(1, w // 40) * channels
    for y in range(0, h, step_y):
        row_start = y * stride + 1
        row_end = min(len(decompressed), row_start + w * channels)
        if row_start >= row_end:
            break
        for x in range(row_start, row_end, step_x):
            sample.append(decompressed[x])
    if len(sample) < 16:
        return False, f"truncated PNG payload ({w}x{h})"
    mean = sum(sample) / len(sample)
    var = sum((v - mean) ** 2 for v in sample) / len(sample)
    if math.sqrt(var) < 2.0:
        return False, f"blank/flat render ({w}x{h})"
    return True, f"OK ({w}x{h}, {len(raw)} bytes)"


def check_png(path):
    """Return (ok, message) for a captured PNG."""
    if not os.path.isfile(path):
        return False, "missing"
    if os.path.getsize(path) == 0:
        return False, "empty (0 bytes)"
    if not _HAS_PIL_NUMPY:
        return _check_png_stdlib(path)
    try:
        im = Image.open(path).convert("RGB")
        arr = np.asarray(im, dtype=np.float64)
    except Exception as exc:
        return False, f"unreadable PNG ({exc})"
    w, h = im.size
    if w < 100 or h < 100:
        return False, f"unexpectedly small ({w}x{h})"
    if np.all(arr.std(axis=(0, 1)) < 3.0):
        return False, f"blank/flat render ({w}x{h})"
    return True, f"OK ({w}x{h}, {os.path.getsize(path)} bytes)"


def scan_log_for_errors(log_path):
    """Return list of (line_no, line_text) matching QML/Qt error patterns."""
    hits = []
    with open(log_path, "r", encoding="utf-8", errors="replace") as fh:
        for idx, line in enumerate(fh, start=1):
            stripped = line.rstrip("\r\n")
            if any(pat.search(stripped) for pat in QML_ERROR_PATTERNS):
                hits.append((idx, stripped))
    return hits


def main():
    parser = argparse.ArgumentParser(
        description="Validate captured QML view PNGs, _status.log, and QML runtime logs.",
        usage="python tools/verify_views_smoke.py <capture_dir> [options]",
    )
    parser.add_argument("capture_dir", help="Directory containing captured view PNGs and _status.log")
    parser.add_argument(
        "--log",
        action="append",
        dest="logs",
        help="Additional log file(s) to check for QML warnings/errors (e.g. pob-qt-main.log)",
    )
    parser.add_argument(
        "--views",
        default=None,
        help="Comma-separated list of view names to require (default: all 9 standard views)",
    )
    parser.add_argument(
        "--allow-present",
        action="store_true",
        help="Validate only the view PNGs present in capture_dir instead of requiring all 9",
    )
    args = parser.parse_args()

    cap_dir = args.capture_dir
    if not os.path.isdir(cap_dir):
        print(f"FAIL: capture directory does not exist: {cap_dir}", file=sys.stderr)
        return 1

    status_path = os.path.join(cap_dir, "_status.log")
    if not os.path.isfile(status_path):
        print(f"FAIL: missing _status.log in {cap_dir}", file=sys.stderr)
        return 1

    with open(status_path, "r", encoding="utf-8", errors="replace") as fh:
        status_text = fh.read()

    if args.views:
        views = [v.strip() for v in args.views.split(",") if v.strip()]
    elif args.allow_present:
        views = sorted(
            os.path.splitext(f)[0]
            for f in os.listdir(cap_dir)
            if f.lower().endswith(".png")
        )
        if not views:
            print(f"FAIL: no PNG files found in {cap_dir}", file=sys.stderr)
            return 1
    else:
        views = list(EXPECTED_VIEWS)

    ok = True
    # _status.log reports viewList count = number of BUILD views (8); LIST mode
    # is appended separately by runCapture(), yielding 9 total PNGs.
    min_build_views = len([v for v in EXPECTED_VIEWS if v != "list"])
    m = re.search(r"viewList\s+count=(\d+)", status_text)
    if m:
        count = int(m.group(1))
        print(f"[smoke] _status.log reports viewList count={count}")
        if not args.allow_present and not args.views and count < min_build_views:
            print(f"FAIL: expected viewList count >= {min_build_views}, got {count}", file=sys.stderr)
            ok = False
    else:
        print("[smoke] WARNING: _status.log does not contain 'viewList count=N'")

    print(f"[smoke] Checking {len(views)} view(s) in {cap_dir}:")
    for view in views:
        png_path = os.path.join(cap_dir, f"{view}.png")
        v_ok, msg = check_png(png_path)
        print(f"  {view:10s}: {msg}")
        if not v_ok:
            ok = False

    # Collect log files to scan for QML warnings/errors.
    candidate_logs = [status_path]
    for name in ("pob-qt-main.log", "capture.log"):
        p = os.path.join(cap_dir, name)
        if os.path.isfile(p) and p not in candidate_logs:
            candidate_logs.append(p)
    for extra in args.logs or []:
        if not os.path.isfile(extra):
            print(f"FAIL: specified log file not found: {extra}", file=sys.stderr)
            ok = False
        elif extra not in candidate_logs:
            candidate_logs.append(extra)

    for lp in candidate_logs:
        hits = scan_log_for_errors(lp)
        if hits:
            print(f"FAIL: QML/Qt errors or warnings in {lp}:", file=sys.stderr)
            for line_no, text in hits[:20]:
                print(f"  L{line_no}: {text}", file=sys.stderr)
            ok = False
        else:
            print(f"[smoke] Log clean (0 QML warnings/errors): {lp}")

    if ok:
        print("[smoke] PASS")
        return 0
    print("[smoke] FAIL", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
