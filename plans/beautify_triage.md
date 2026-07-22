# Beautify Triage — Objective Evidence (Phase 0)

> Companion to [`beautify_plan.md`](beautify_plan.md). Objective, repeatable
> measurement of the legacy-vs-new regression using
> [`tools/screenshot_diff.py`](tools/screenshot_diff.py).

## Method
- `skill_tree/legacy.png` (working SimpleGraphic) vs `skill_tree/new.png` (Qt port).
- `import/legacy.png` vs `import/new.png`.
- Metrics: size, per-channel mean/std (palette + flatness), colour-histogram
  distance (resolution-independent), luminance SSIM + MSE on a common canvas.

## Raw results

| Metric | skill_tree | import |
|---|---|---|
| legacy size | 1267x665 | 1265x729 |
| new size | 1075x725 | 1084x729 |
| legacy mean RGB | (18.0, 21.6, 23.7) | (19.6, 24.0, 26.6) |
| new mean RGB | (17.5, 26.1, 44.0) | (17.1, 25.0, 42.9) |
| legacy std RGB | (30.0, 31.1, 30.7) | (35.4, 41.0, 42.9) |
| new std RGB | (16.7, 19.7, 16.3) | (15.2, 16.0, 11.9) |
| hist chi2 (lower=better) | 0.0766 | 0.1033 |
| hist corr (1.0=identical) | 0.3488 | 0.1013 |
| SSIM (1.0=identical) | 0.0677 | 0.2547 |
| MSE | 1331.9 | 1862.1 |
| blank? | No | No |

## Interpretation

1. **Both `new` images are structurally very different from legacy**
   (SSIM 0.068 / 0.255 — essentially different layouts).
2. **Both `new` images have ~half the pixel standard deviation of legacy**
   (skill_tree 16–20 vs 30; import 12–16 vs 35–43). The Qt port renders a
   **much sparser, content-poor UI** — tree nodes/sprites and import fields are
   largely absent vs the legacy reference.
3. **`new` is bluer** (B channel 44 vs 24). This matches the Cyber Citrus
   `#0F172A` background actually being applied, so this is **not** a
   "theme not loaded" case — it is **missing content**, not missing theme.
4. `new.png` file sizes (91KB / 32KB) are far smaller than `legacy.png`
   (773KB / 169KB), corroborating the low-variance / low-detail finding.

## Deploy-gap check (ruled OUT)

- `dist/pob-qt.exe` = 07/13 05:34 AM, 830,311 bytes — **identical timestamp and
  size** to `build-win/pob-qt.exe`. The running binary *is* the current build.
- Screenshots captured **07/17 02:56–03:02 AM** (today), ~4h after the binary.
  They reflect the current build, not a stale one.
- **Conclusion:** the documented "deploy gap" root cause from
  [`plans/style_fix_pass2.md`](plans/style_fix_pass2.md) is **NOT** what is
  breaking the current UI. The breakage is a genuine porting/rendering defect.

## Hypothesised root causes (to confirm in Phase 3)

### skill_tree (TREE view) — empty/sparse tree
- [`app/qml/main.qml:250`](app/qml/main.qml:250) `treeView` draws `treeBg`
  (`backgroundUrl`) + `treeCanvas` (`drawImage` sprites).
- [`app/qml/main.qml:314`](app/qml/main.qml:314) canvas early-returns when
  `bounds.size <= 0`; repaint only on `onViewChanged` + a one-shot `Timer`
  ([`app/qml/main.qml:459`](app/qml/main.qml:459)). If `bounds`/`nodes` populate
  after that single repaint, the tree stays blank.
- Likely fix direction: repaint when `boundsValid` flips true (bind
  `requestPaint` to `boundsValid` / a `boundsChanged` signal), and verify
  `backgroundUrl` + sprite atlas actually resolve from `TreeData/<ver>/`.

### import (IMPORT view) — minimal vs legacy
- [`app/qml/main.qml:1293`](app/qml/main.qml:1293) `importView` exists and is
  `visible: activeView === "IMPORT"` (the old "parent hidden" bug is fixed).
- It is simply a **minimal** UI (one `TextField` + `Button` + status `Text`) vs
  the richer legacy import screen. The low std is partly by-design sparsity,
  but the regression vs legacy suggests the legacy offered more (paste box,
  preview, options). Phase 3 should decide whether to enrich or accept.

## Verdict
The "utterly broken" report is objectively confirmed: the Qt port renders a
content-poor UI versus the legacy reference, and the cause is **not** the
recurring deploy gap. This validates the need for the ironclad multiphase plan
([`beautify_plan.md`](beautify_plan.md)) — the prior ad-hoc fixes did not hold.
Phase 3 (layout audit) must confirm the tree/import root causes above before
Phase 4+ component work begins.
