import numpy as np
from PIL import Image

new = np.asarray(Image.open("dist/src/captures/tree.png").convert("RGB"), dtype=np.float64)
crop = new[32:720, 312:1100]
BG = np.array([8.0, 12.0, 17.0])
d = np.sqrt(((crop - BG) ** 2).sum(2))
mask = d > 40
print("new crop non-bg(dist>40) count:", int(mask.sum()), "coverage: %.3f%%" % (100 * mask.sum() / mask.size))
if mask.any():
    ys, xs = np.where(mask)
    print("bbox: x(%d-%d) y(%d-%d)  w=%d h=%d" % (xs.min(), xs.max() + 1, ys.min(), ys.max() + 1, xs.max() - xs.min() + 1, ys.max() - ys.min() + 1))
    vals = crop[mask]
    print("mean non-bg color: R=%.1f G=%.1f B=%.1f" % tuple(vals.mean(0)))
    q = vals.astype(int) >> 4
    keys = (q[:, 0] << 8) | (q[:, 1] << 4) | q[:, 2]
    u, c = np.unique(keys, return_counts=True)
    print("top non-bg quantized colors:")
    for k, n in sorted(zip(u, c), key=lambda x: -x[1])[:6]:
        print("   rgb(%d,%d,%d) n=%d" % (((k >> 8) & 15) * 16, ((k >> 4) & 15) * 16, (k & 15) * 16, n))
else:
    print("NO non-bg pixels at all in new crop (tree canvas is uniformly background)")

# inspect predicted class-start center (706,376) -> crop coords (394,344)
for (wx, wy, label) in [(706, 376, "ClassStart#0(center)"), (706, 536, "ClassStart#4"), (565, 458, "ClassStart#1")]:
    cy, cx = wy - 32, wx - 312
    reg = crop[max(0, cy - 15):cy + 15, max(0, cx - 15):cx + 15]
    rd = d[max(0, cy - 15):cy + 15, max(0, cx - 15):cx + 15]
    print("%s: region mean RGB=%.1f,%.1f,%.1f  maxdist=%.1f" % (label, reg.reshape(-1, 3).mean(0)[0], reg.reshape(-1, 3).mean(0)[1], reg.reshape(-1, 3).mean(0)[2], rd.max()))
