from PIL import Image, ImageFilter
import numpy as np

def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)

def colmean(a, ch):
    return a[:, :, ch].mean(0)

def rowmean(a, ch):
    return a[:, :, ch].mean(1)

def find_drop(prof):
    # prof: 1D array (left->right or top->bottom). Sidebar/topbar is brighter
    # (higher B); tree area is darker. Find first index where B crosses
    # below the midpoint of (left-quarter mean, right-quarter mean).
    n = len(prof)
    hi = prof[: max(1, n // 4)].mean()
    lo = prof[n // 4:].mean()
    thr = (hi + lo) / 2.0
    for i in range(n):
        if prof[i] < thr:
            return i
    return n // 4

leg = load("bugs/legacy.png")
new = load("dist/src/captures/tree.png")
Hl, Wl, _ = leg.shape
Hn, Wn, _ = new.shape

# legacy: detect sidebar (col B) + topbar (row B) boundaries
legB_col = colmean(leg, 2)
legB_row = rowmean(leg, 2)
sx = find_drop(legB_col)   # sidebar right edge (x)
sy = find_drop(legB_row)   # topbar bottom (y)
print(f"legacy img {Wl}x{Hl} -> sidebar_end_x={sx} topbar_end_y={sy}")
leg_crop = leg[sy:Hl, sx:Wl]

# new: live canvas geometry (312,32,788,688)
nx, ny, nw, nh = 312, 32, 788, 688
new_crop = new[ny:ny + nh, nx:nx + nw]

def to_size(arr, W, H):
    return np.asarray(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).resize((W, H), Image.LANCZOS), dtype=np.float64)

Wc, Hc = 760, 660
leg_r = to_size(leg_crop, Wc, Hc)
new_r = to_size(new_crop, Wc, Hc)

def ssim(a, b):
    ya = 0.299 * a[:, :, 0] + 0.587 * a[:, :, 1] + 0.114 * a[:, :, 2]
    yb = 0.299 * b[:, :, 0] + 0.587 * b[:, :, 1] + 0.114 * b[:, :, 2]
    L = 255.0
    C1 = (0.01 * L) ** 2
    C2 = (0.03 * L) ** 2
    def box(x, r=3):
        return np.asarray(Image.fromarray(np.clip(x, 0, 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(r)), dtype=np.float64)
    ma, mb = box(ya), box(yb)
    a2, b2, ab = box(ya ** 2), box(yb ** 2), box(ya * yb)
    sa2 = a2 - ma ** 2
    sb2 = b2 - mb ** 2
    sab = ab - ma * mb
    num = (2 * ma * mb + C1) * (2 * sab + C2)
    den = (ma ** 2 + mb ** 2 + C1) * (sa2 + sb2 + C2)
    return float(np.mean(num / den))

print(f"legacy crop: {leg_crop.shape[1]}x{leg_crop.shape[0]}  new crop: {new_crop.shape[1]}x{new_crop.shape[0]}")
print(f"CORRECTED SSIM (canvas-content-only, aligned {Wc}x{Hc}): {ssim(leg_r, new_r):.4f}")
