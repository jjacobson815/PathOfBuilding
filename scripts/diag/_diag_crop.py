from PIL import Image
import numpy as np

def grid(path, cells=3):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im, dtype=np.float64)
    H, W, _ = a.shape
    print(f"{path}  {W}x{H}")
    for r in range(cells):
        row = []
        for c in range(cells):
            y0 = r * H // cells; y1 = (r + 1) * H // cells
            x0 = c * W // cells; x1 = (c + 1) * W // cells
            blk = a[y0:y1, x0:x1].reshape(-1, 3)
            m = blk.mean(0)
            row.append(f"({c},{r}):{m[0]:.0f},{m[1]:.0f},{m[2]:.0f}")
        print("   " + " | ".join(row))

grid("bugs/legacy.png")
grid("dist/src/captures/tree.png")
