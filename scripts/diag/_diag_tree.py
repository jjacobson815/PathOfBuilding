import sys
from PIL import Image
import numpy as np

def analyze(path):
    try:
        im = Image.open(path).convert("RGB")
    except Exception as e:
        print(f"{path}: ERROR opening: {e}")
        return
    a = np.asarray(im, dtype=np.float64)
    mean = a.mean(axis=(0, 1))
    std = a.std(axis=(0, 1))
    bg = np.array([15, 23, 42])      # #0F172A theme background
    lime = np.array([163, 230, 53])  # #A3E635 accent
    d_bg = np.abs(a - bg).sum(axis=2)
    d_lime = np.abs(a - lime).sum(axis=2)
    n_bg = int((d_bg < 30).sum())
    n_lime = int((d_lime < 60).sum())
    n_nonbg = int((d_bg > 40).sum())
    total = a.shape[0] * a.shape[1]
    print(f"{path}: size={im.size} mean=({mean[0]:.0f},{mean[1]:.0f},{mean[2]:.0f}) "
          f"std=({std[0]:.0f},{std[1]:.0f},{std[2]:.0f}) bgpx={n_bg} ({100*n_bg/total:.1f}%) "
          f"limepx={n_lime} nonbgpx={n_nonbg} ({100*n_nonbg/total:.1f}%)")

for p in ["captures/tree.png", "captures/config.png", "captures/skills.png",
          "captures/items.png", "captures/calcs.png", "captures/notes.png",
          "skill_tree/legacy.png", "skill_tree/new.png", "import/legacy.png", "import/new.png"]:
    analyze(p)
