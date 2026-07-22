#!/usr/bin/env python3
"""Objective screenshot diff for the PoB Qt port beautify triage (Phase 0).

Compares a "new" (current Qt port) screenshot against a "legacy" (working
SimpleGraphic) reference using resolution-independent and structural metrics:

  * size mismatch
  * per-channel mean / std (palette + flatness / blank-render detection)
  * colour histogram distance (chi-square + correlation, resolution independent)
  * luminance SSIM + MSE on a common canvas (structural similarity)

Usage:
  python tools/screenshot_diff.py <legacy.png> <new.png> [label]
"""
import sys
import numpy as np
from PIL import Image, ImageFilter


def load_rgb(path):
    im = Image.open(path).convert("RGB")
    return np.asarray(im, dtype=np.float64), im.size


def stats(arr):
    mean = arr.mean(axis=(0, 1))
    std = arr.std(axis=(0, 1))
    return mean, std


def hist_dist(a, b, bins=32):
    """Chi-square + correlation distance over per-channel colour histograms."""
    lo = np.min(np.concatenate([a.ravel(), b.ravel()]))
    hi = np.max(np.concatenate([a.ravel(), b.ravel()]))
    if hi == lo:
        hi = lo + 1.0
    chi, corr = [], []
    for c in range(3):
        ha, _ = np.histogram(a[:, :, c], bins=bins, range=(lo, hi), density=True)
        hb, _ = np.histogram(b[:, :, c], bins=bins, range=(lo, hi), density=True)
        ha += 1e-6
        hb += 1e-6
        chi.append(0.5 * np.sum((ha - hb) ** 2 / (ha + hb)))
        corr.append(np.corrcoef(ha, hb)[0, 1])
    return float(np.mean(chi)), float(np.mean(corr))


def box_filter(x, r=3):
    """Uniform (box) blur via PIL — avoids scipy dependency."""
    im = Image.fromarray(np.clip(x, 0, 255).astype(np.uint8))
    blurred = im.filter(ImageFilter.BoxBlur(r))
    return np.asarray(blurred, dtype=np.float64)


def ssim_luminance(a, b):
    """Luminance SSIM on two equal-sized float arrays (0..255)."""
    ya = 0.299 * a[:, :, 0] + 0.587 * a[:, :, 1] + 0.114 * a[:, :, 2]
    yb = 0.299 * b[:, :, 0] + 0.587 * b[:, :, 1] + 0.114 * b[:, :, 2]
    L = 255.0
    C1 = (0.01 * L) ** 2
    C2 = (0.03 * L) ** 2
    mu_a, mu_b = box_filter(ya), box_filter(yb)
    a2, b2, ab = box_filter(ya ** 2), box_filter(yb ** 2), box_filter(ya * yb)
    sa2 = a2 - mu_a ** 2
    sb2 = b2 - mu_b ** 2
    sab = ab - mu_a * mu_b
    num = (2 * mu_a * mu_b + C1) * (2 * sab + C2)
    den = (mu_a ** 2 + mu_b ** 2 + C1) * (sa2 + sb2 + C2)
    return float(np.mean(num / den))


def mse(a, b):
    return float(np.mean((a - b) ** 2))


def compare(legacy_path, new_path, label=""):
    a, sa = load_rgb(legacy_path)
    b, sb = load_rgb(new_path)
    ma, sda = stats(a)
    mb, sdb = stats(b)

    # Common canvas: resize new to legacy size for pixel metrics.
    if sa != sb:
        b_resized = np.asarray(
            Image.fromarray(b.astype(np.uint8)).resize(sa, Image.LANCZOS),
            dtype=np.float64,
        )
    else:
        b_resized = b

    chi, corr = hist_dist(a, b)
    s = ssim_luminance(a, b_resized)
    e = mse(a, b_resized)

    # Flatness / blank-render heuristic on the new image.
    flat = bool(np.all(sdb < 6.0))

    print(f"=== {label} ===")
    print(f"  legacy size : {sa[0]}x{sa[1]}")
    print(f"  new size    : {sb[0]}x{sb[1]}  (size_match={sa == sb})")
    print(f"  legacy mean : R={ma[0]:.1f} G={ma[1]:.1f} B={ma[2]:.1f}")
    print(f"  new    mean : R={mb[0]:.1f} G={mb[1]:.1f} B={mb[2]:.1f}")
    print(f"  legacy std  : R={sda[0]:.1f} G={sda[1]:.1f} B={sda[2]:.1f}")
    print(f"  new    std  : R={sdb[0]:.1f} G={sdb[1]:.1f} B={sdb[2]:.1f}")
    print(f"  hist chi2   : {chi:.4f}  (lower=more similar palette)")
    print(f"  hist corr   : {corr:.4f}  (1.0=identical distribution)")
    print(f"  SSIM (lum)  : {s:.4f}  (1.0=identical structure)")
    print(f"  MSE         : {e:.1f}    (0=identical pixels)")
    print(f"  blank?      : {flat}  (new image nearly flat -> likely broken/blank render)")
    print()
    return {
        "label": label,
        "size_match": sa == sb,
        "mean_delta": float(np.linalg.norm(ma - mb)),
        "std_new": sdb.tolist(),
        "hist_chi2": chi,
        "hist_corr": corr,
        "ssim": s,
        "mse": e,
        "blank": flat,
    }


def main():
    pairs = []
    # Default pairs from the user's triage request.
    pairs.append(("skill_tree/legacy.png", "skill_tree/new.png", "skill_tree"))
    pairs.append(("import/legacy.png", "import/new.png", "import"))
    # Allow CLI overrides.
    args = sys.argv[1:]
    if len(args) >= 2:
        pairs = [(args[0], args[1], args[2] if len(args) > 2 else "cli")]

    results = []
    for leg, new, lab in pairs:
        try:
            results.append(compare(leg, new, lab))
        except FileNotFoundError as e:
            print(f"!! missing file for {lab}: {e}")
    print("SUMMARY")
    for r in results:
        verdict = "BLANK/BROKEN" if r["blank"] else ("SIMILAR" if r["ssim"] > 0.85 else "REGRESSED")
        print(f"  {r['label']:10s} ssim={r['ssim']:.3f} hist_corr={r['hist_corr']:.3f} -> {verdict}")


if __name__ == "__main__":
    main()
