from PIL import Image
import numpy as np

im = Image.open("captures/tree.png").convert("RGB")
a = np.asarray(im, dtype=np.float64)
bg = np.array([15, 23, 42])
d = np.abs(a - bg).sum(axis=2)
mask = d > 40
ys, xs = np.where(mask)
print("image size:", im.size)
print("non-bg pixel count:", int(mask.sum()))
if mask.sum() > 0:
    print("bbox x: [%d, %d]  y: [%d, %d]" % (xs.min(), xs.max(), ys.min(), ys.max()))
    print("center of mass: x=%.0f y=%.0f" % (xs.mean(), ys.mean()))
    # coarse 22x14 density grid
    H, W = a.shape[0], a.shape[1]
    gh, gw = 14, 22
    print("\ncoarse density grid (each cell ~ %dx%d px), #non-bg px:" %
          (W // gw, H // gh))
    for gy in range(gh):
        row = ""
        for gx in range(gw):
            x0, x1 = gx * W // gw, (gx + 1) * W // gw
            y0, y1 = gy * H // gh, (gy + 1) * H // gh
            c = int(mask[y0:y1, x0:x1].sum())
            row += ("." if c == 0 else ("o" if c < 50 else ("O" if c < 300 else "#")))
        print(row)
