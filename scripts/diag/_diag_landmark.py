import json, math
import numpy as np
from PIL import Image, ImageFilter

# ---------------------------------------------------------------------------
# Task 1: saturation-based content bbox, but crop to KNOWN canvas region first
# ---------------------------------------------------------------------------
def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)

def hsv_sv(a):
    r = a[:, :, 0] / 255.0
    g = a[:, :, 1] / 255.0
    b = a[:, :, 2] / 255.0
    maxc = np.maximum(np.maximum(r, g), b)
    minc = np.minimum(np.minimum(r, g), b)
    v = maxc
    s = np.where(maxc > 0, (maxc - minc) / np.maximum(maxc, 1e-9), 0.0)
    return s, v

def sat_bbox_cov(a, sat_thr=0.3, val_thr=0.2):
    s, v = hsv_sv(a)
    mask = (s > sat_thr) & (v > val_thr)
    total = a.shape[0] * a.shape[1]
    cov = float(mask.sum()) / total
    if not mask.any():
        return (0, 0, a.shape[1], a.shape[0]), cov
    ys, xs = np.where(mask)
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1), cov

leg = load("bugs/legacy.png")
new = load("dist/src/captures/tree.png")
Hl, Wl, _ = leg.shape
Hn, Wn, _ = new.shape

# crop to known canvas regions
leg_crop = leg[55:665, 190:1267]          # legacy: remove sidebar (x<190) + top bar (y<55)
new_crop = new[32:720, 312:1100]          # new: canvas geom x=312 y=32, w=788 h=688

lb, lc = sat_bbox_cov(leg_crop)
nb, nc = sat_bbox_cov(new_crop)
print("=== TASK 1: saturation bbox on CANVAS-CROPPED regions (sat>0.3 & val>0.2) ===")
print(f"legacy crop [55:665,190:1267] -> bbox=({lb[0]},{lb[1]})-({lb[2]},{lb[3]}) w={lb[2]-lb[0]} h={lb[3]-lb[1]} coverage={100*lc:.2f}%")
print(f"new    crop [32:720,312:1100] -> bbox=({nb[0]},{nb[1]})-({nb[2]},{nb[3]}) w={nb[2]-nb[0]} h={nb[3]-nb[1]} coverage={100*nc:.2f}%")
print(f"  (prior full-frame: legacy 6.06% vs new 0.97% -> 6.2x gap)")
if lc > 0 and nc > 0:
    print(f"  cropped gap ratio: {lc/nc:.2f}x  (shrinks if sidebar contamination was the cause)")
print()

# ---------------------------------------------------------------------------
# Task 2: landmark coordinate check (NEW build only)
#   compute tree (x,y) from group+orbit via PoB formula, predict screen pos,
#   detect actual rendered position in tree.png
# ---------------------------------------------------------------------------
print("=== TASK 2: landmark node coordinate check (NEW build) ===")
raw = open("TreeData/3_28/data.json", encoding="utf-8").read()
start = raw.index("var passiveSkillTreeData = ") + len("var passiveSkillTreeData = ")
i = raw.index("{", start)
depth = 0; j = i; in_str = False; esc = False
while j < len(raw):
    c = raw[j]
    if esc: esc = False
    elif c == '\\' and in_str: esc = True
    elif c == '"': in_str = not in_str
    elif not in_str:
        if c == '{': depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0: break
    j += 1
data = json.loads(raw[i:j+1])
nodes = data["nodes"]; groups = data["groups"]
spp = data["constants"]["skillsPerOrbit"]   # 0-based
orb = data["constants"]["orbitRadii"]        # 0-based

def calc_orbit_angles(n):
    if n == 16: return [0,30,45,60,90,120,135,150,180,210,225,240,270,300,315,330]
    if n == 40: return [0,10,20,30,40,45,50,60,70,80,90,100,110,120,130,135,140,150,160,170,180,190,200,210,220,225,230,240,250,260,270,280,290,300,310,315,320,330,340,350]
    return [360.0*k/n for k in range(n+1)]

orbit_angles = {o: calc_orbit_angles(spp[o]) for o in range(len(spp))}

def node_xy(nid):
    nd = nodes[nid]
    g = groups[str(nd["group"])]
    o = nd.get("orbit", 0); oidx = nd.get("orbitIndex", 0)
    ang = math.radians(orbit_angles[o][oidx])
    r = orb[o]
    return g["x"] + math.sin(ang)*r, g["y"] - math.cos(ang)*r

# transform params from capture _diag.log (default camera: zoomX=zoomY=0)
CANVAS_X0, CANVAS_Y0 = 312, 32
OX, OY, SCALE = 394, 344, 0.05006   # ox=width/2+zoomX, oy=height/2+zoomY, scale=baseScale*zoom

def predict(tx, ty):
    cx = OX + SCALE * tx
    cy = OY + SCALE * ty
    return CANVAS_X0 + cx, CANVAS_Y0 + cy

# detection: node pixels differ from tree-bg (8,12,17) by > 40 in RGB dist
BG = np.array([8.0, 12.0, 17.0])
def detect(img, wx, wy, rad=38):
    x0 = max(0, int(wx-rad)); x1 = min(img.shape[1], int(wx+rad)+1)
    y0 = max(0, int(wy-rad)); y1 = min(img.shape[0], int(wy+rad)+1)
    if x1 <= x0 or y1 <= y0: return None
    reg = img[y0:y1, x0:x1]
    d = np.sqrt(((reg - BG)**2).sum(2))
    mask = d > 40
    if not mask.any(): return None
    ys, xs = np.where(mask)
    # centroid of detected pixels
    cy = y0 + ys.mean(); cx = x0 + xs.mean()
    return (cx, cy, float(d[mask].max()))

targets = {}
for nid, nd in nodes.items():
    nm = nd.get("name")
    if nm in ("Vaal Pact", "Acrobatics", "Point Blank", "Blood Magic", "Ancestral Bond"):
        targets[nm] = (nid, node_xy(nid))
# class-start nodes (one per class)
for nid, nd in nodes.items():
    if "classStartIndex" in nd:
        targets[f"ClassStart#{nd['classStartIndex']}"] = (nid, node_xy(nid))

print(f"transform: canvas@({CANVAS_X0},{CANVAS_Y0}) ox={OX} oy={OY} scale={SCALE}  bg=(8,12,17)")
print(f"{'node':16} {'tree_x':>9} {'tree_y':>9} | {'pred_x':>7} {'pred_y':>7} | {'act_x':>7} {'act_y':>7} | {'dx':>6} {'dy':>6}  note")
for nm in ("Vaal Pact", "Acrobatics", "Point Blank", "Blood Magic", "Ancestral Bond",
           "ClassStart#0","ClassStart#1","ClassStart#2","ClassStart#3","ClassStart#4","ClassStart#5","ClassStart#6"):
    if nm not in targets: continue
    nid, (tx, ty) = targets[nm]
    px, py = predict(tx, ty)
    in_canvas = (312 <= px <= 1100) and (32 <= py <= 720)
    if not in_canvas:
        print(f"{nm:16} {tx:9.1f} {ty:9.1f} | {px:7.1f} {py:7.1f} |   --     --    |  --    --   OFF-CANVAS")
        continue
    det = detect(new, px, py)
    if det is None:
        print(f"{nm:16} {tx:9.1f} {ty:9.1f} | {px:7.1f} {py:7.1f} |   --     --    |  --    --   NOT DETECTED")
    else:
        ax, ay, mx = det
        print(f"{nm:16} {tx:9.1f} {ty:9.1f} | {px:7.1f} {py:7.1f} | {ax:7.1f} {ay:7.1f} | {ax-px:6.1f} {ay-py:6.1f}  maxdist={mx:.0f}")
