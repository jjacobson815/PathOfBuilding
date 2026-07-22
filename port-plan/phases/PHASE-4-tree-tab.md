# Phase 4 — Tree Tab (finish & harden)

**Status:** NOT STARTED
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

- [ ] Decide: keep the Canvas-2D JS renderer and optimize, or move to
  `QQuickItem`/scene-graph nodes. Either way: persist atlas decode (stop recreating
  `Image` objects), add a **spatial index for hitTest** (replace the C++ linear
  scan), and stop the per-call `io.open` asset probing in `pob_getTreeData`. (L)
- [ ] Replace the `TreeViewController` refresh signature (`allocCount*1000003 +
  nodeCount`, which misses same-count changes and ignores search state) with an
  engine-sourced **revision counter** (e.g. spec serial) that includes search. (S)
- [ ] **Generalize `_gbByVersion`** (hardcoded to only "3_28" in `pob_host.lua`)
  so group backgrounds resolve for every tree version. (S)
- [ ] Enable WebP decoding (qtimageformats plugin) for `ascendancy-*.webp`/
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
