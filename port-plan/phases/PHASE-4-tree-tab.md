# Phase 4 — Tree Tab (finish & harden)

**Status:** IN PROGRESS — Part 4.1 4/5 done (renderer landed as `TreeScene`); latest evidence in "Session log — 2026-09-24". See "Recon findings" at the bottom before starting.
**Goal:** Finish the passive-tree tab — the one view that already renders. Harden
the renderer, make the tree viewer an embeddable multi-instance component, and add
the missing interactive features (spec management, compare overlay, search, node
power/heat map + Power Report, mastery/tattoo popups, Timeless Jewel finder).
**Depends on:** Phase 1 (components, tooltip, popup), Phase 2 (node compare +
node-power via calculator bridge), Phase 3 (shell frames it).
**References to load:** [[tabs-catalog]] (Tree tab section), [[control-library]]
(embeddable tree viewer note), [[calc-engine-contract]] (node power / PowerBuilder),
[[data-and-assets]] (tree assets, WebP, timeless LUTs).

## Why here

The tree is the highest-value view and is already ~80% rendered, so it's the best
place to prove the whole "QML-native view over marshalled Lua" pattern end-to-end
before the heavier tabs. It also produces the embeddable tree component that
ItemSlotControl, TimelessJewelSocketControl, and CalcBreakdown reuse later.

## Part 4.1 — Renderer hardening

- [x] Decide: keep the Canvas-2D JS renderer and optimize, or move to
  `QQuickItem`/scene-graph nodes. Either way: persist atlas decode (stop recreating
  `Image` objects), add a **spatial index for hitTest** (replace the C++ linear
  scan), and stop the per-call `io.open` asset probing in `pob_getTreeData`. (L)
  → **DONE: scene graph (`TreeScene`)**, Canvas path deleted; shared
  `QSGTexture` cache, C++ hit grid, memoised `sheetInfo`. Evidence: session log
  2026-09-24.
- [x] Replace the `TreeViewController` refresh signature (`allocCount*1000003 +
  nodeCount`, which misses same-count changes and ignores search state) with an
  engine-sourced **revision counter** (e.g. spec serial) that includes search. (S)
- [x] **Generalize `_gbByVersion`** (hardcoded to only "3_28" in `pob_host.lua`)
  so group backgrounds resolve for every tree version. (S)
- [x] Enable WebP decoding (qtimageformats plugin) for `ascendancy-*.webp`/
  `bloodline-*.webp`; verify all 39 versions load (5+ version-gated sprite formats
  in `PassiveTree.lua`). (S)
- [ ] Make the tree viewer an **embeddable, parameterized component** (zoom target,
  crosshair, compare spec) — required by ItemSlotControl jewel viewer,
  TimelessJewelSocketControl, and CalcBreakdown. (M)

## Part 4.2 — Spec management

- [ ] Spec dropdown with respec-gold tooltip (class/asc/points/sockets, switch
  stat-diff, per-node refund cost). Up/Down cycle specs. (M)
- [ ] Manage-trees popup (generic set-manager component): new/copy/delete/rename/
  reorder; reorder syncs the itemsTab tree selector + loadouts. (M)
- [ ] **Import Tree** (pathofexile.com incl. ruthless/alternate URLs, poeurl
  resolve [needs Phase 10 network], poeplanner decode, poeskilltree; version
  validation) and **Export Tree** (encode URL, PoEURL shrink, copy). (M — the
  poeurl/network path is gated on Phase 10; local encode/decode works now.)

## Part 4.3 — Interaction & display

- [ ] Viewer: pan/zoom/alloc/dealloc with dependent-node handling, path tracing +
  hover preview, path drag (Shift alternate-path mode). Hotkeys: `p` heat map,
  Ctrl+D stat-diff tooltips, Ctrl+C copy hovered node, PgUp/PgDn zoom, Shift-socket
  jewel compare, wiki hotkey. (M)
- [ ] Node tooltips: name, stats (unsupported flagged), reminder text, **stat-diff
  on alloc/dealloc** (Phase 2 node calculator), required gold, compare-spec status;
  jewel sockets show socketed-jewel tooltip + radius rings + "allocates in radius". (M)
- [ ] Compare checkbox + compare-spec dropdown → overlay (green/red/blue) or the
  compare colors in the viewer; cluster subgraphs. (M)
- [ ] Search box (Ctrl+F, Lua patterns, `oil:` anoint prefix, `(a|b)` groups) →
  viewer highlight + optional edge-of-viewport circles. (S-M)
- [ ] **Show Node Power** + max-depth dropdown + power-stat dropdown → heat map;
  **Power Report drawer** (PowerReportListControl, sortable, click-to-recenter);
  progress toast while the PowerBuilder coroutine runs (drive resume from a Qt
  timer/idle hook, never concurrent with a rebuild). (M — uses Phase 2 node power.)

## Part 4.4 — Popups

- [ ] **Mastery-effect popup** (right-click mastery): per-effect stat-diff preview
  (PassiveMasteryControl with embedded node tooltip). (S-M)
- [ ] **Tattoo popup** (right-click tattooable node): eligible tattoos by target
  type/connections, legacy toggle, tattoo count x/50, Add/Reset Node. (M)
- [ ] **Reset popup**: Reset Tree / Remove All Tattoos / Cancel. (S)
- [ ] Version dropdown + **Convert** popup (Convert / Copy+Convert / Cancel) +
  "convert all trees" banner for outdated specs. (S-M)

## Part 4.5 — Timeless Jewel finder (large sub-feature)

- [ ] Full popup: 6 jewel types + conqueror/devotion dropdowns; jewel-socket
  dropdown (+ "All Sockets" multi-search) with **mini tree preview**
  (TimelessJewelSocketControl); Filter Nodes + distance slider + protect-notables
  list; weight sliders; node search dropdown; Desired/Fallback node CSV edits +
  fallback-weight generation; results list (TimelessJewelListControl, click seed →
  preview transformations); **trade URL builder** (realm/league/buyout → pathofexile.
  com/trade queries from seed ranges). State in `<TimelessData>`. (L — the trade-URL
  portion touches network/realm-league fetch, gated on Phase 10/12; the LUT search
  itself is offline via `data.readLUT`.) (S — verify the binary seed LUTs load; see
  [[data-and-assets]].)

## Acceptance gate

- Tree renders correctly across ≥3 tree versions (latest + one old + one ruthless/
  alternate), including group backgrounds, WebP ascendancy art, frame rings.
- Pixel-sample verification vs a legacy screenshot (per the retained hard-
  verification methodology) — not "verified by construction."
- Alloc/dealloc + hover stat-diff match legacy; heat map + Power Report populate;
  mastery + tattoo popups work; search + `oil:` works.
- Timeless Jewel LUT search returns results matching legacy for a known seed.
- `pob-selftest` green (tree checks already exist); capture diff clean.

## Notes

- The embeddable tree component (4.1) is a dependency for Items (jewel viewer),
  Calcs breakdown (node view), and the timeless socket preview — build it as a
  reusable component, not tree-tab-private.
- PowerBuilder must never run concurrently with a rebuild — invalidate/abort the
  coroutine on `buildFlag`, mirroring legacy frame ordering.


---

## Recon findings — 2026-08-19

Full recon done against the legacy source. Two root causes found; one fixed.

### FIXED: the renderer was handed the wrong tree version

`pob_getTreeData` selected `main.tree[latestTreeVersion]` first and fell back to
`bm.spec.tree` — but `main.tree[latestTreeVersion]` is always present, so the
spec branch was **dead code**. A build on a 3_25 spec rendered **3_28 geometry**
with that spec's allocation ids painted over it. Order corrected; every path
downstream already read `tree.treeVersion` (the tree object's own field) rather
than the selection local, so the change is contained.
`pob_selftestTreeVersion` guards it — note it can only *discriminate* once a
build sits on a non-latest spec (today spec == latest == `3_28`), so it is a
forward guard, not proof of the original defect. The defect itself was
established by inspection: the fallback branch was provably unreachable.

### FIXED — `ImageSize()` is real and sprite UV consumption is coherent (2026-08-19)

`app/lua/pob_host.lua` `NewImageHandle():ImageSize()` returns `1, 1`. Two
consequences, and the first explains a visible parity gap nobody had traced:

1. **Every orbit connector's geometry is garbage.** `PassiveTree.lua:956`
   computes `size = art.width * 2 * 1.33`, so with `width == 1` every arc
   collapses to 2.66 tree units at the group centre. **This is why the port
   draws straight lines instead of arcs** — not a shortcut in the QML renderer.
2. `spriteMap` UVs come out as raw pixels rather than normalised, which
   `pob_host.lua`'s sprite resolution currently *depends on*.

Fixed with a memoised `pob.imageSize(path)` C++ primitive over
`QImageReader::size()` (header-only) and `NewImageHandle:Load` remembering its
filename. The bridge de-normalises the now-real sprite UVs against the resolved
atlas before sending QML pixel source rectangles; it also rejects missing/zero
sheets instead of passing `inf`/`nan` geometry through. `pob_selftestTreeRender`
checks **5,537** icon/frame/group sprites against their named atlas (`0` invalid;
smallest source rectangle `26px`), which catches either raw-UV or wrong-atlas
regression before render work continues.

### Renderer decision: move to a `QQuickItem` scene graph (`TreeScene`)

**LANDED in `7227ad42c`** — the Canvas path is deleted; see session log
2026-09-24. (Original plan: stage behind the existing Canvas until
`tools/verify_style.py` clears, then delete the Canvas path.) Four reasons, each from current code:
1. **Canvas-2D structurally cannot draw legacy connectors** — they are textured
   *quads* (`DrawImageQuad`, `PassiveTreeView.lua:694`) with arc art on
   kite-shaped quads; `Context2D.drawImage` is axis-aligned rects only. In a
   `QSGGeometry` a quad *is* the primitive: ~3 draw calls for all connectors.
2. Pan/zoom re-walks ~9 000 elements in JS every frame; in the scene graph it is
   one `QSGTransformNode` matrix write.
3. Every element crosses QVariant→JS per paint (`model.get(i)` returns a fresh
   `QVariantMap`) — ~9 000 conversions per frame.
4. Multi-instance (Phase 6 needs it) cannot share decoded atlases under Canvas;
   `QSGTexture` is shareable by construction.

### Other confirmed defects worth fixing while in here

- **`pob_allocNode`/`pob_deallocNode` never call `spec:AddUndoState()`** (legacy
  does, `PassiveTreeView.lua:459`/`:489`) — tree undo is currently inert.
- **`altPath` is never passed** to `spec:AllocNode`, so Shift-trace alternate
  pathing is impossible.
- **hitTest is a linear scan that deep-copies a `QVariantMap` per node per
  mouse-move** (`TreeViewController.cpp`), and uses a uniform 25px radius
  instead of the per-node `rsq`, and does not reject proxy nodes.
- **The `allocCount*1000003 + nodeCount` refresh signature** misses same-count
  changes, mastery/tattoo selection, spec switches and all search state.
- **`~7,400 io.open` calls per `pob_getTreeData`** (one per node icon, per node
  frame, per group background). Resolving from the already-in-memory
  `tree.spriteMap` cuts it to ~15 probes **and deletes `_gbByVersion`**
  (the hardcoded-to-3_28 table) as a side effect.
- **`<TreeView>` XML state is not round-tripped** — zoom/pan/search live in C++
  and are never written back, so reopening a build loses the view.
- **qtimageformats/WebP is NOT installed on this machine** (only
  qgif/qico/qjpeg/qsvg present), so 3_27/3_28 ascendancy art cannot decode.
  Needs `mingw-w64-x86_64-qt6-imageformats`.
- **`tree.assets` is stale on 3_20+**: when a tree has no `assets` the engine
  loads `TreeData/3_19/Assets.lua`, so `tree.assets[...]` holds 3_19 CDN URLs.
  Resolve art through `tree.spriteMap`, never `tree.assets`.
- **Group backgrounds are impossible offline for <= 3_19** — those versions only
  reference per-zoom CDN URLs. Use 3_28 + 3_25_ruthless + 3_20 as the
  ">= 3 versions" acceptance set, not 2_6.

### The coroutine job seam — build it generic

Phase 4's PowerBuilder and Phase 6's ItemDB stat-sort are structurally identical
(both are legacy coroutines resumed off the frame loop with % progress). Build
ONE seam: `pob_jobStart(kind, params)` / `pob_jobStep(handle, budgetMs)` /
`pob_jobAbort` / `pob_jobResult`, with `pob_powerStart/Step/Abort` as named
aliases, driven by a C++ `JobRunner` + `QTimer`. Phase 6 plugs in as a second
`kind` with no new plumbing.

**Invalidation must be two-directional:** `pob_jobStep` aborts when `buildFlag`
is dirty or `outputRevision` moved, AND `pob_recalculate()` must abort any live
job before `BuildOutput` — because `BuildOutput` rebuilds the calculators and a
live PowerBuilder holds closures over the *old* env, so resuming would write
stale `node.power` onto live nodes.

**The 100ms yield floor is not tunable** (`CalcsTab.lua:632` uses its own wall
clock), so `budgetMs` controls resumes-per-step, not granularity. Expect 4-14s
total with ~100ms hitches; say so in the progress toast.

### Part 4.5 (Timeless Jewel) — sub-phase it

Smallest honest version: LUTs load and inflate (including GloriousVanity's
5-part concatenation, and redirecting the `.bin` cache to a writable dir — it
currently writes next to the install and fails silently read-only, costing a
51.5MB re-inflate per launch), plus a seed search matching legacy for a fixed
golden fixture. **No popup** — driven from a selftest. The popup itself is a
small application; the trade-URL builder is hard-gated on Phase 10/12 for the
realm/league fetch.

---

## Session log — 2026-08-19 (Part 4.1: three hardening items)

Landed alongside the ImageSize/sprite-UV work, deliberately kept clear of the
`NewImageHandle`/`spriteMap` seam. Gate: `pob-selftest` exit 0; capture diff
clean (see "Capture gate" below).

### 4.1 — `_gbByVersion` generalized (DONE)

`loadSourceGroupBackground()` was a static table with a single `"3_28"` entry, so
**every other tree version drew no group backdrops at all**. Replaced with
resolution from shipped data, in two branches:

- **3_25+ (16 versions)** — `TreeData/<ver>/sprites.lua` ships a `groupBackground`
  atlas asset (filename + the PSGroupBackground1/2/3 sub-rects). Reuses the
  existing `loadSourceSprites()` memo, so no extra file parse.
- **<=3_24 (23 versions)** — no `sprites.lua` exists. Legacy falls back to the
  shared `TreeData/3_19/Assets.lua`, whose `PSGroupBackgroundN` entries are
  scale-keyed CDN URLs that `PassiveTree:LoadImage` resolves to the **standalone**
  `TreeData/PSGroupBackgroundN.png` at the TreeData root (it probes
  `TreeData/<name>` *before* `TreeData/<ver>/<name>`). Those are whole images, not
  atlas pages, so the sub-rect is the entire file.

The standalone branch needs real pixel dimensions, and `tree.assets[...].width/
height` are all `1x1` because they come from the stubbed `ImageSize()`. Rather
than take a dependency on that seam, added a ~20-line `pngSize()` that reads
width/height straight out of the PNG IHDR chunk. `PNG_SIG` is built with
`string.char(137,80,78,71,13,10,26,10)` on purpose — a literal escape sequence
there does not survive some patch/editor round-trips, and a mangled one is a
**syntax error**, not a silent bug.

Also removed the "any rect will do" fallback in `resolveGroupBackground`: the new
`loadSourceGroupBackground` only ever returns a table that HAS `coords[spriteKey]`,
so that branch was unreachable — and had it fired it would have painted a
wrong-size backdrop rather than failing. (Same class of latent dead branch as the
`latestTreeVersion` defect in the recon findings above.)

**Evidence:** all **39/39** versions resolve all three keys (16 via atlas, 23 via
standalone, 0 unresolved) — previously 1/39. `pngSize` verified against real
files: 138x138 / 179x179 / 284x144 for the standalone PNGs, 1006x666 for the
3_28 atlas page, and `nil` for both a missing file and a non-PNG (a `.jpg`).
On 3_28 the change is a **provable no-op**: the sprites.lua rects
(`443,444,138,138` / `723,286,178,178` / `723,0,283,143`) are byte-identical to
the deleted hardcoded table, which the capture diff confirms.

### 4.1 — refresh signature -> engine-sourced revision (DONE)

`TreeViewController.cpp` threw away rebuilds on `allocCount * 1000003 + nodeCount`.
That was blind to two real cases:

1. **An allocation swap** — dealloc one node, alloc another. Both counts are
   identical either side, so the throttle reported "no change" and the canvas kept
   painting the node that was no longer allocated.
2. **Search** — the signature never sampled search state at all, so a search
   highlight could not repaint until some unrelated edit moved the counts.

`pob_getTreeData` now returns an opaque `revision` string folding tree version,
node count, alloc count, an **order-independent** checksum of the allocated ids,
and a search serial bumped by `pob_setTreeSearch`. Order-independent matters:
`pairs()` order over `tree.nodes` is arbitrary and may differ between calls, so the
accumulator has to be commutative — hence a sum, with each id scattered through
Knuth's 2654435761 first (a plain sum of raw ids lets a swap cancel itself out:
`100 + 201 == 101 + 200`, which is precisely the case being fixed). It is a
`:`-joined string rather than a packed int so no component can overflow into
another's bits. `TreeViewController` compares that string; an empty value (a host
predating the field) falls through and rebuilds rather than throttling on a value
it cannot trust.

**Evidence:** `pob_selftestTreeInteract` now asserts the revision behaviour and
`selftest_checks.h` prints it, so the gate shows it rather than implying it:

```
tree-interact ok = true  allocOk = true  deallocOk = true  searchOk = true
  searchClearOk = true  revAllocOk = true  revRestoreOk = true  revSwapOk = true
  swapCountsEqual = true  swapSkipped = false  revSearchOk = true
```

`swapCountsEqual = true` is the important one — it confirms the alloc/node counts
really were identical either side of the swap, i.e. the **old signature would have
collided there**, while `revSwapOk = true` shows the new one does not.
`swapSkipped = false` confirms the swap case actually ran rather than being
skipped for want of a second allocatable node. `revRestoreOk` (revision returns to
its exact prior value after an undo) is what proves the checksum is exact and
order-independent rather than merely changing a lot.

### 4.1 — WebP decoding (DONE)

Root cause was environmental, not code: msys2 ships the webp decoder in a
**separate** package and it was not installed — `mingw64/share/qt6/plugins/
imageformats/` held only `qgif/qico/qjpeg/qsvg`. `QImageReader` therefore returned
a null `QImage` for every `.webp` and the ascendancy/bloodline art rendered blank
**with no error logged anywhere**. Installed
`mingw-w64-x86_64-qt6-imageformats` (6.11.1-1, matching the installed
`qt6-base` exactly, so it pulled no Qt upgrade — only `qwebp.dll` plus
libwebp/libtiff/jasper deps).

**Evidence:** `QImageReader::supportedImageFormats()` now contains `webp`; all
**28/28** `.webp` files under `TreeData/` decode. Widened to the real acceptance
criterion — every sprite sheet **every** version actually loads, mirroring
`PassiveTree.lua`'s `maxZoom` selection (only the highest zoom level is ever
loaded; the lower-zoom variants are referenced in sprite data but never shipped,
so counting them would be noise): **439/439 max-zoom sheets across all 39 versions
decode — 82 jpg, 341 png, 16 webp, 0 failures.**

Deployment: `windeployqt` now picks `qwebp.dll` up automatically and the existing
ldd fixpoint loop pulls `libwebp-7/demux-2/mux-3` in behind it — verified by a
real `deploy-win-standalone.sh` run (exit 0, clean-PATH smoke test passed, 80 DLLs
bundled). Because that is silently dependent on a package being present on the
build machine, the script now **fails loudly** if `imageformats/qwebp.dll` is
missing instead of shipping a dist that is quietly missing artwork; `deploy.sh`'s
Linux prerequisite note gained `qt6-qtimageformats` for the same reason.

### Capture gate

All 10 views differ from `app/tests/capture-baseline/` by a few hundred pixels at
`maxChannelDelta=1`. That is **not** a regression: capturing twice from the *same*
binary produces differences of the same magnitude (tree 380px, notes 375px, config
666px, all delta 1), so it is run-to-run text-rasterization noise. `tree` (468px)
sits in the same band as `notes`/`party` (461px) — views this work cannot touch.
Byte-comparing the PNGs is useless here for the same reason; use a pixel diff.

### Observed, not caused by this work

10 of the 449 max-zoom sheet references do not resolve on disk, all png/jpg, none
webp: **3_19** is missing 8 (`background-3.png`, `ascendancy-background-3.jpg`,
`ascendancy-3.png`, `group-background-3.png`, `frame-3.png`, `jewel-radius.png`,
`line-3.png`, `jewel-3.png` — it ships only `groups-3.png`/`skills*-3.jpg` yet its
sprite data references the 3_20-era asset set), and `jewel-radius.png` is absent
for **3_25_alternate** and **3_25_ruthless_alternate**. These are gaps in the
shipped upstream TreeData, not port defects, and they predate this session.

---

## Session log — 2026-08-19 (Phase 4 interaction hardening continuation)

### Legacy hit testing and undo restoration (DONE)

`TreeViewController::hitTest()` no longer performs a linear scan that materialises
a `QVariantMap` for every node on every mouse move. `pob_getTreeData()` now exports
the legacy `node.rsq` hit-circle data only for real, grouped, non-proxy nodes.
The controller builds a 96-tree-unit C++ grid when the model refreshes, duplicating
each circle into its covered cells, then tests only the current cell's candidates
against the exact legacy radius. This removes invisible proxy targets and preserves
the differing clickable sizes of ordinary, notable, jewel, and mastery nodes.

`pob_allocNode()` and `pob_deallocNode()` now call `spec:AddUndoState()` after the
engine mutation, in the same order as `PassiveTreeView.lua`. The tree interaction
selftest resets its fixture undo baseline and proves allocation snapshot creation,
Undo restoration, Redo restoration, and deallocation snapshot creation. Gate output:

```
tree-interact ok = true  undoAllocSnapshotOk = true
  undoAllocRestoresOk = true  redoAllocRestoresOk = true
  undoDeallocSnapshotOk = true
```

The full `pob-selftest` exited 0. A fresh ten-view capture compared against
`app/tests/capture-baseline/` at SSIM 1.000 for every view (tree's unrounded SSIM
was 0.9997, MSE 2.9; all images non-blank), so this interaction-only change has no
idle-render regression.

## Session log — 2026-09-24 (TreeScene landed: doc sync + re-gate)

Commit `7227ad42c` (2026-08-19 18:09) landed work that the 17:26 handoff
(`HANDOFF-phase4.md`) had listed as deferred, and the phase docs were never
updated for it. What is in the tree, checked against code:

- **Renderer = `TreeScene`** (`app/src/TreeScene.cpp`, a `QQuickItem`), hosted by
  `app/qml/components/TreeViewer.qml`. No Canvas renderer remains in QML (only a
  stale comment at `main.qml:222` still says "Canvas renderer").
- **Connectors are real textured quads**: `pob_getTreeData` exports each
  connector's engine `vert`/`uv` (`isArc` for `Orbit*` types); `TreeScene`
  batches them. The earlier "QML still draws straight lines" note is obsolete.
- Atlases decode once into a per-window `QSGTexture` cache (`s_textureCache`).
- Handoff items 1–7 (checksum non-linearity fix, swap selftests, Dockerfile
  imageformats, normalised-UV sprite consumption, `sheetInfo` memo, dead-code
  removal, sprite-bounds gate) are all in the commit.

Re-gate on the current binaries (`ninja`: no work to do):

```
pob-selftest  EXIT=0
tree-render ok = true  nodeCount = 2782  connectorCount = 3061  spriteChecked = 5537
  spriteBad = 0  arcCount = 1828  lineCount = 1233  badConnectors = 0  spriteMinW = 26
tree-interact ok = true  (alloc/dealloc/search/undo/redo/rev*/swap2/checksum* all true)
pob-qt --headless  EXIT=0  "SELFTEST PASSED"
```

Captures (warm second run) vs `app/tests/capture-baseline/`: 9/10 views SSIM
1.000. **tree SSIM 0.32 — stale baseline, not a regression**: the committed
`tree.png` predates the TreeScene switch (straight connectors, blue fill). Scored
against the legacy reference `skill_tree/legacy.png`: committed baseline SSIM
0.136 / hist-corr 0.38; current TreeScene capture SSIM 0.534 / hist-corr 0.91.
Baseline `tree.png` refreshed from this capture.

Note: `swap2Skipped = true` on the default fixture — no two disjoint
sum-preserving frontier pairs exist from a fresh Scion, so the two-node swap
path is not exercised there; `checksumNonLinearOk` covers the class directly.

Still open in 4.1: the embeddable, parameterized tree component.
