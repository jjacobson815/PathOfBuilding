# Phase 8 — Calcs Tab & Breakdown

**Status:** NOT STARTED
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

- [ ] Render the `CalcSections.lua`-driven grid: offence (group 1, 3 cols) +
  defence (groups 2/3) with responsive reflow + portrait fallback; collapsible
  subsections; section/subsection collapse state persisted (`<Section id subsection
  collapsed>`). (M)
- [ ] Cell resolution: a Lua-side "resolve section model" API returning plain rows
  per section — resolve `formatCalcStr` (`{output:Key}`, `{output:Ns.Key}`,
  `{N:output:Key}`, `{N:mod:i,j}` via live Combine against actor.modDB /
  mainSkill.skillModList / enemy.modDB), CheckFlag gating on `mainSkill.skillFlags`,
  `haveOutput`/`flag`/`notFlag` gates. Actor = minion if "Show Minion Stats". (M-L)
- [ ] First section "View Skill Details": **independent `*Calcs` selectors** (socket
  group / active skill / part / stages / mines / minion / spectre / minion-skill),
  "Show Minion Stats" checkbox, **Calculation Mode** dropdown (Unbuffed/Buffed/In
  Combat/Effective — affects only this tab via `calcsInput.misc_buffMode`), buff/
  combat/curse lists. (M)
- [ ] Search box filtering/highlighting cells (Ctrl+F). (S)

## Part 8.2 — Breakdown drill-down (the hard part)

- [ ] On-demand Lua serializer for `actor.breakdown[key]` → plain data: TEXT lines,
  `rowList`+`colList` (+ label/footer/source), `reservations` (fixed schema),
  `damageTypes`, `slots` (`{base,inc,more,total,source,sourceName,item→id}`),
  `radius` (number). Namespaced lookup (`MainHand.X`). (L)
- [ ] Click-time **mod tables**: port `AddModSection` logic to data — issue
  `modStore:Tabulate`/`Combine`, format mod flags/tags, per-source totals; item/
  node cross-refs become ids resolved by the item/tree services. Row tooltips call
  the item tooltip and render an **embedded `PassiveTreeView`** for Tree-sourced
  mods (Phase 4 component). (L)
- [ ] Breakdown UI: hover = transient, click = pinned (green border, click-away
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
