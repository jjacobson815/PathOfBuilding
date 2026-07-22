from PIL import Image, ImageFilter
import numpy as np

def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)

def hsv_sv(a):
    # a: float64 RGB 0..255 -> S,V in 0..1
    r = a[:, :, 0] / 255.0
    g = a[:, :, 1] / 255.0
    b = a[:, :, 2] / 255.0
    maxc = np.maximum(np.maximum(r, g), b)
    minc = np.minimum(np.minimum(r, g), b)
    v = maxc
    s = np.where(maxc > 0, (maxc - minc) / np.maximum(maxc, 1e-9), 0.0)
    return s, v

def mode_and_second(a):
    q = a.astype(np.int32) >> 4
    keys = (q[:, :, 0] << 8) | (q[:, :, 1] << 4) | q[:, :, 2]
    vals, counts = np.unique(keys, return_counts=True)
    order = np.argsort(counts)[::-1]
    mk = int(vals[order[0]])
    sk = int(vals[order[1]])
    mc = np.array([((mk >> 8) & 0xF) * 16, ((mk >> 4) & 0xF) * 16, (mk & 0xF) * 16], dtype=np.float64)
    sc = np.array([((sk >> 8) & 0xF) * 16, ((sk >> 4) & 0xF) * 16, (sk & 0xF) * 16], dtype=np.float64)
    return mc, sc, int(counts[order[0]]), int(counts[order[1]]), a.shape[0] * a.shape[1]

def content_bbox_sat(a, sat_thr=0.3, val_thr=0.2):
    s, v = hsv_sv(a)
    mask = (s > sat_thr) & (v > val_thr)
    total = a.shape[0] * a.shape[1]
    cov = float(mask.sum()) / total
    if not mask.any():
        return (0, 0, a.shape[1], a.shape[0]), cov
    ys, xs = np.where(mask)
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1), cov

def fit(arr, TW, TH, pad):
    h, w, _ = arr.shape
    s = min(TW / w, TH / h)
    nw, nh = max(1, int(round(w * s))), max(1, int(round(h * s)))
    rz = np.asarray(Image.fromarray(arr.astype(np.uint8)).resize((nw, nh), Image.LANCZOS))
    cv = np.zeros((TH, TW, 3), dtype=np.uint8)
    cv[:, :] = pad.astype(np.uint8)
    cv[(TH - nh) // 2:(TH - nh) // 2 + nh, (TW - nw) // 2:(TW - nw) // 2 + nw] = rz
    return cv.astype(np.float64)

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

leg = load("bugs/legacy.png")
new = load("dist/src/captures/tree.png")
Hl, Wl, _ = leg.shape
Hn, Wn, _ = new.shape

# per-image mode + second-most-common quantized color
lmc, lsc, lmc_n, lsc_n, ltot = mode_and_second(leg)
nmc, nsc, nmc_n, nsc_n, ntot = mode_and_second(new)

# saturation-based content bbox
lbbox, lcov = content_bbox_sat(leg)
nbbox, ncov = content_bbox_sat(new)
lx0, ly0, lx1, ly1 = lbbox
nx0, ny0, nx1, ny1 = nbbox

def rgbstr(c):
    return f"rgb({int(c[0])},{int(c[1])},{int(c[2])})"

print("=== PER-IMAGE COLOR IDENTITY ===")
print(f"legacy  mode={rgbstr(lmc)} (n={lmc_n}, {100*lmc_n/ltot:.1f}%)  second={rgbstr(lsc)} (n={lsc_n}, {100*lsc_n/ltot:.1f}%)")
print(f"         guess: mode=panel/tree-bg dark shade; second=likely sidebar or tree-bg variant (chrome, NOT content)")
print(f"new     mode={rgbstr(nmc)} (n={nmc_n}, {100*nmc_n/ntot:.1f}%)  second={rgbstr(nsc)} (n={nsc_n}, {100*nsc_n/ntot:.1f}%)")
print(f"         guess: mode=panel #0F172A left bar/top bar; second=likely tree-bg #080C11 (chrome, NOT content)")
print()
print("=== SATURATION-BASED CONTENT BBOX (sat>0.3 AND val>0.2) ===")
print(f"legacy  {Wl}x{Hl}  bbox=({lx0},{ly0})-({lx1},{ly1})  w={lx1-lx0} h={ly1-ly0}  aspect={(lx1-lx0)/(ly1-ly0):.3f}  coverage={100*lcov:.2f}%")
print(f"new     {Wn}x{Hn}  bbox=({nx0},{ny0})-({nx1},{ny1})  w={nx1-nx0} h={ny1-ny0}  aspect={(nx1-nx0)/(ny1-ny0):.3f}  coverage={100*ncov:.2f}%")
print(f"         (sanity: sparse nodes/edges over dark bg -> expect single-digit to low-teens %; not ~0% or >50%)")
print()

leg_c = leg[ly0:ly1, lx0:lx1]
new_c = new[ny0:ny1, nx0:nx1]

TW, TH = 820, 820
leg_f = fit(leg_c, TW, TH, lmc)
new_f = fit(new_c, TW, TH, nmc)
print(f"=== SSIM (content-bbox, aspect-preserved fit, padded with each image's OWN mode color) ===")
print(f"fit target {TW}x{TH}")
print(f"CORRECTED SSIM: {ssim(leg_f, new_f):.4f}")
print()
print("NOTE: bbox-fit SSIM normalizes overall scale/extent, NOT per-node correspondence.")
print("A high score is necessary but NOT sufficient proof of correct structure; it does not")
print("rule out both images showing different partial views that bbox similarly. A landmark-node")
print("position check (class start + 2-3 named keystones by coordinate) remains required follow-up.")
