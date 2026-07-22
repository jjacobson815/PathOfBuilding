# Phase 7 — Config Tab

**Status:** NOT STARTED
**Goal:** Port the configuration tab: config sets, controls generated from the
`ConfigOptions` data table, the conditional-visibility engine driven by live calc
usage sets, search, and the modList plumbing into the calc env.
**Depends on:** Phase 1 (generated controls), Phase 2 (usage-set export + BuildModList
recalc), Phase 3 (shell).
**References to load:** [[tabs-catalog]] (Config tab), [[calc-engine-contract]]
(config plumbing + the `varControls` shim requirement), [[control-library]]
(config-driven control generation).

## Why it needs care

Config is **data-driven** — the ~2000-entry `ConfigOptions` varList (with 513
`apply()` closures and 562 visibility predicates) is the source of truth and cannot
be re-specified in C++. The UI must be generated from it, and option visibility
depends on a completed MAIN calc pass (a feedback loop). Some `apply()` functions
reach into `build.configTab.varControls` — the data module depends on UI controls
existing, which forces a small host shim.

## Part 7.1 — Config sets & generated controls

- [ ] Config sets: dropdown + Manage popup (generic set-manager); active set's
  `input`/`placeholder` maps seeded from defaults. (S)
- [ ] Generate controls from the `ConfigOptions` varList (cached load already in
  `pob_host.lua`): section headers (multi-column flow) + per-var control by type
  (check / count / countAllowZero / integer / float / list / text), placeholder
  support, tooltips (`tooltip`/`tooltipFunc` — the latter reads `mainOutput`). (M —
  a QML control-factory keyed on var type.)
- [ ] `varControls` shim — provide the table `apply()` functions expect on
  `build.configTab.varControls` so placeholder-mutating options (e.g. `enemyIsBoss`
  setting placeholders on enemy stat controls) work. This is a sanctioned host
  seam; keep it in `pob_host.lua`. (S — but load-bearing; see [[calc-engine-contract]].)

## Part 7.2 — Conditional visibility engine

- [ ] Evaluate the visibility predicates (ifNode/ifOption/ifCond/ifMinionCond/
  ifEnemyCond/ifCondTrue/ifMult/ifEnemyMult/ifStat/ifEnemyStat/ifTagType/ifFlag/
  ifMod/ifSkill/ifSkillFlag/ifSkillData + implyCondList) against the Phase 2
  exported usage sets (`conditionsUsed`, `multipliersUsed`, etc.). Evaluate in Lua,
  return per-var booleans to QML. Re-query placeholders after `BuildModList` (some
  `apply()` mutate them). (M)
- [ ] "Show All Configurations" toggle (reveals unmet-condition options minus an
  exclusion list). Non-default-but-hidden options stay visible with red label +
  "invalid" tooltip + colored border. (S)
- [ ] Search box (Ctrl+F, Lua-pattern-tolerant). (S)

## Part 7.3 — Plumbing & persistence

- [ ] Route edits → `configTab.input` → `BuildModList` (into `modList`/
  `enemyModList`) → `buildFlag` → recalc. Bandit + Pantheon selections live here
  (mirrored into `<Build>` attribs). `UpdateLevel` clamps enemy level. Undo/redo on
  the active set's input table. (M)
- [ ] `<Config>` XML: attrib activeConfigSet; `<ConfigSet>` with `<Input>` (non-
  default only) + `<Placeholder>`; legacy flat Input; `enemyIsBoss`/`presetBossSkills`
  back-compat rewrites. `ImportCalcSettings` migrates pre-Config builds. (M)

## Acceptance gate

- Open a build → config options show correct values; conditional options appear/
  hide exactly as legacy (spot-check a keystone-gated option and an enemy-condition-
  gated one).
- Toggle a config (e.g. "is Boss", "Focused") → stat panel recomputes correctly.
- "Show All" reveals hidden options; invalid non-default hidden options show red.
- Save → `<Config>` round-trips through legacy PoB (incl. bandit/pantheon).
- `pob-selftest` config check green; capture diff clean.

## Notes

- Do NOT hand-translate ConfigOptions into C++/QML — generate the UI from the Lua
  table so league updates flow through unchanged.
- The `varControls` shim is the one place the "data depends on UI" coupling leaks;
  get it right or placeholder-driven options (many enemy-stat options) misbehave.
