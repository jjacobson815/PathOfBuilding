from PIL import Image
import numpy as np

def analyze(path, name):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im, dtype=np.float64)
    H, W, _ = a.shape
    print(f"=== {name} {W}x{H} ===")
    print(" grid (R,G,B) 3x3:")
    for r in range(3):
        cells = []
        for c in range(3):
            y0 = r*H//3; y1 = (r+1)*H//3
            x0 = c*W//3; x1 = (c+1)*W//3
            m = a[y0:y1, x0:x1].reshape(-1, 3).mean(0)
            cells.append(f"({c},{r}):{m[0]:.0f},{m[1]:.0f},{m[2]:.0f}")
        print("   " + " | ".join(cells))
    print(" col profile (mean R,G,B) across width:")
    ncol = 20
    for c in range(ncol):
        x0 = c*W//ncol; x1 = (c+1)*W//ncol
        m = a[:, x0:x1].reshape(-1, 3).mean(0)
        print(f"   c{c:02d}:{m[0]:.0f},{m[1]:.0f},{m[2]:.0f}", end="")
    print()
    print(" row profile (mean R,G,B) down height:")
    nrow = 12
    for r in range(nrow):
        y0 = r*H//nrow; y1 = (r+1)*H//nrow
        m = a[y0:y1, :].reshape(-1, 3).mean(0)
        print(f"   r{r:02d}:{m[0]:.0f},{m[1]:.0f},{m[2]:.0f}", end="")
    print()

analyze("bugs/legacy.png", "LEGACY")
analyze("dist/src/captures/tree.png", "NEW(full)")
