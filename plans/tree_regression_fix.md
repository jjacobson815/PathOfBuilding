# Tree Regression Fix — Lag + Square Nodes

## Root cause (confirmed in `app/qml/main.qml`)
1. **Square nodes** — `ctx.shadowBlur`/`ctx.shadowColor` were set on the `drawImage` of the
   circular frame sprite (`PSSkillFrame*`). Qt's Canvas casts `shadowBlur` from the image's
   **bounding box**, not its alpha, so the circular frame got a **square halo**. The frame
   sprite itself is circular (see `pob_host.lua` `nodeSprite()` / `PassiveTreeView.lua:833`).
2. **Lag** — `shadowBlur` on ~3000 nodes per repaint is expensive, and the 250ms `Timer`
   (`app/qml/main.qml:571`) runs `running: true` **forever**, forcing a full `requestPaint()`
   (background + groups + thousands of connectors + 3000 nodes) **4×/sec continuously**.

## Fix (minimal, per user decision)
- **Remove the glow entirely** (constants + set/reset lines). Simplest, max performance,
  closest to legacy look. No replacement glow.
- **Gate the 250ms Timer** to `running: !treeView.boundsValid` so it only runs during the
  initial data-load window and stops once bounds are valid. Initial paint is already covered
  by `Component.onCompleted`, `onVisibleChanged`, `onBoundsValidChanged`, and atlas
  `statusChanged` handlers — so no continuous repaint is needed in steady state.
- **Keep** the asset-visibility improvements: enlarged node scaling (`nodeScaleFactor`,
  `minNodePx`) and thin, zoom-scaled connectors (z-order already correct: bg → groups →
  connectors → nodes).

## Steps
1. Delete `nodeGlowBlur` / `nodeGlowColor` properties (lines 300-301).
2. Delete `ctx.shadowBlur`/`ctx.shadowColor` set (426-427) and `ctx.shadowBlur = 0` reset
   (479); update the stale "subtle outer glow" comment (420-424).
3. Change Timer `running: true` → `running: !treeView.boundsValid` (line 574).
4. Build: `set PATH=C:\msys64\mingw64\bin;%PATH% && cd build-win && ninja`
   Deploy: `copy /Y build-win\pob-qt.exe dist\pob-qt.exe`
   Validate: `qmllint app/qml/main.qml`

## Offscreen render-cache (IMPLEMENTED 2026-07-20)
- **Offscreen render-cache**: the tree now renders to an offscreen `Canvas` (`treeBuffer`),
  re-renders only on zoom/data change, and blits (translates) during pan — matching legacy
  pan smoothness. `imageSmoothingQuality` was dropped from "high" to "medium" to speed up
  sprite scaling during pan. See [`plans/tree_offscreen_cache_plan.md`](plans/tree_offscreen_cache_plan.md)
  for the full design and [`app/qml/main.qml`](app/qml/main.qml) for the implementation
  (`treeBuffer` Canvas, shared `drawTree`, blit in `treeCanvas.onPaint`, gated re-render in
  the `treeViewController` Connections).
