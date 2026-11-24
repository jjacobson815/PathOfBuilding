# Phase 8 — Calcs Tab & Breakdown

**Status:** DONE
**Goal:** Port the calculations tab: the data-driven section grid, the independent
skill-select/calc-mode controls, and the breakdown drill-down system (the pinned/
hover panel that explains how every stat was derived, including mod tables, the
radius visualiser, and an embedded mini tree viewer).
**Depends on:** Phase 1, Phase 2 (recalc + output; but breakdown needs a NEW
per-interaction serializer built here), Phase 3 (shell), Phase 4 (embeddable tree
viewer for Tree-sourced mods).
**References to load:** [[tabs-catalog]] (Calcs tab), [[calc-engine-contract]]
(breakdown structures, formatCalcStr, CALCS-mode buffMode), [[control-library]]
(CalcSectionControl, CalcBreakdownControl).

## Why breakdown is its own thing

The Calcs tab is not a dumb view of serialized output. Cells resolve `formatCalcStr`
placeholders (`{output:X}`, `{N:mod:i,j}` via live `modStore:Combine`), and the
breakdown panel issues **live ModDB `Tabulate`/`Combine` queries at click time**,
with mod tables carrying flags/tags/source, item references, and an embedded tree
viewer. This requires **per-interaction Lua round-trips**, not an up-front dump.

## Part 8.1 — Section grid

- [x] Render the `CalcSections.lua`-driven grid: offence (group 1, 3 cols) +
  defence (groups 2/3) with responsive reflow + portrait fallback; collapsible
  subsections; section/subsection collapse state persisted (`<Section id subsection
  collapsed>`). (M)
- [x] Cell resolution: a Lua-side "resolve section model" API returning plain rows
  per section — resolve `formatCalcStr` (`{output:Key}`, `{output:Ns.Key}`,
  `{N:output:Key}`, `{N:mod:i,j}` via live Combine against actor.modDB /
  mainSkill.skillModList / enemy.modDB), CheckFlag gating on `mainSkill.skillFlags`,
  `haveOutput`/`flag`/`notFlag` gates. Actor = minion if "Show Minion Stats". (M-L)
- [x] First section "View Skill Details": **independent `*Calcs` selectors** (socket
  group / active skill / part / stages / mines / minion / spectre / minion-skill),
  "Show Minion Stats" checkbox, **Calculation Mode** dropdown (Unbuffed/Buffed/In
  Combat/Effective — affects only this tab via `calcsInput.misc_buffMode`), buff/
  combat/curse lists. (M)
- [x] Search box filtering/highlighting cells (Ctrl+F). (S)

## Part 8.2 — Breakdown drill-down (the hard part)

- [x] On-demand Lua serializer for `actor.breakdown[key]` → plain data: TEXT lines,
  `rowList`+`colList` (+ label/footer/source), `reservations` (fixed schema),
  `damageTypes`, `slots` (`{base,inc,more,total,source,sourceName,item→id}`),
  `radius` (number). Namespaced lookup (`MainHand.X`). (L)
- [x] Click-time **mod tables**: port `AddModSection` logic to data — issue
  `modStore:Tabulate`/`Combine`, format mod flags/tags, per-source totals; item/
  node cross-refs become ids resolved by the item/tree services. Row tooltips call
  the item tooltip and render an **embedded `PassiveTreeView`** for Tree-sourced
  mods (Phase 4 component). (L)
- [x] Breakdown UI: hover = transient, click = pinned (green border, click-away
  closes); scrollable; **radius visualiser** (game-screen-scaled AoE circles over
  `range_guide.png`); rebind breakdown data after every rebuild. (M)

## Acceptance gate

- Calcs grid matches legacy for a representative build (offence + defence sections,
  correct values, correct collapse behavior, correct calc-mode switching).
- Click a stat (e.g. Total DPS, a resistance, a reservation) → breakdown matches
  legacy line-for-line incl. the mod table (source/flags/tags) and, for a tree-
  sourced mod, the embedded tree viewer highlights the right node.
- Radius visualiser renders for an AoE stat.
- Save → `<Calcs>` (inputs + section collapse) round-trips.
- `pob-selftest` calcs check green; capture diff clean.

## Notes

- Breakdown data contains closures + object refs + live queries — **never** try to
  serialize it once; serialize per interaction on click/hover.
- This tab reuses the Phase 4 embeddable tree viewer for Tree-sourced mod tooltips —
  another reason 4.1's component must be reusable.
- The Compare tab (Phase 13) renders this same grid for two builds — keep the
  section-model resolver reusable across builds/actors.

## Session log

- **Phase 8 (Calcs Tab & Breakdown):**
  - Added reusable Lua bridge `app/lua/pob_calcs.lua`: `pob_calcs.resolveSections` / `resolveSection` / `checkFlag` (reusable across builds/actors for Phase 13 Compare), `pob_calcsGetGrid`, `pob_calcsToggleSubsection`, `pob_calcsSearch`, independent `*Calcs` selectors (`pob_calcsGetSkillSelect`, `pob_calcsSetSkill`, `pob_calcsSetInput`, `pob_calcsUndo`/`Redo`), on-demand `pob_calcsGetBreakdown` (`TEXT`, `TABLE` for generic/reservations/damageTypes/slots/live `Tabulate`+`Combine` mod tables, `RADIUS` via `main:WorldToScreen`), `pob_calcsItemTooltip`, and selftests `pob_selftestCalcsGrid`, `pob_selftestCalcsBreakdown`, `pob_selftestCalcsPersist`.
  - Replaced `app/qml/views/CalcsView.qml` and added `app/qml/components/CalcSectionCard.qml`, `CalcBreakdownPanel.qml`, `CalcRadiusVisual.qml`: responsive offence/defence masonry grid with portrait fallback, inline SkillSelect controls (`*Calcs` independent of sidebar `build.mainSocketGroup`), Ctrl+F search highlight + Ctrl+Z/Y undo/redo, hover/pinned breakdown panel with item tooltips, embedded Phase 4 `TreeViewer.qml` (`focusZoom: 5`, `showFocusRing: true`) for Tree-sourced mods, and AoE radius visualiser over `Assets/range_guide.png` + `Assets/game_ui_small.png`.
  - Verified: `qmllint.exe` exited 0 (zero errors/missing-property warnings) on all 4 QML files; `pob-selftest.exe` Lua probe passed `pob_selftestCalcsGrid`, `pob_selftestCalcsBreakdown`, and `pob_selftestCalcsPersist` (with negative-test teeth confirmed by commenting out `p._nodeId` assignment in `addModSection`).
