import numpy as np
from PIL import Image

img = np.asarray(Image.open("dist/src/captures/tree.png").convert("RGB"), dtype=np.float64)
H, W, _ = img.shape
print(f"full image: {W}x{H}")

# canvas region used by onPaint: window (312,32) size 788x688
x0, y0, cw, ch = 312, 32, 788, 688
crop = img[y0:y0+ch, x0:x0+cw]
BG = np.array([8.0, 12.0, 17.0])
MUTED = np.array([148.0, 163.0, 184.0])   # theme.muted (unallocated node fill)
CYAN = np.array([0.0, 176.0, 208.0])    # UI chrome strip

d = np.sqrt(((crop - BG) ** 2).sum(2))
dm = np.sqrt(((crop - MUTED) ** 2).sum(2))
dc = np.sqrt(((crop - CYAN) ** 2).sum(2))

content = d > 40                      # differs from tree background
not_cyan = dc > 60                    # exclude the bright UI strip
node_like = (dm < 55) & content & not_cyan   # light-slate node/connector fill
other_content = content & not_cyan & ~node_like

n_content = int(content.sum())
n_node = int(node_like.sum())
n_other = int(other_content.sum())
print(f"canvas crop: {cw}x{ch} = {cw*ch} px")
print(f"  content (dist>40 from bg): {n_content} px ({100*n_content/(cw*ch):.3f}%)")
print(f"  NODE-LIKE (light-slate ~muted, excl cyan): {n_node} px")
print(f"  OTHER content (excl cyan, not node-colored): {n_other} px")

# coarse 16x14 grid of node-like density to see if nodes are spread like a real tree
gx, gy = 16, 14
print("\nnode-like density grid (rows top->bottom, cols left->right), . = 0, # = many:")
for r in range(gy):
    row = ""
    for c in range(gx):
        yy0 = r * ch // gy; yy1 = (r+1) * ch // gy
        xx0 = c * cw // gx; xx1 = (c+1) * cw // gx
        block = node_like[yy0:yy1, xx0:xx1]
        v = int(block.sum())
        row += "#" if v > 40 else ("+" if v > 10 else ("." if v > 0 else " "))
    print("  " + row)
