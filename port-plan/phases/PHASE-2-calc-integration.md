# Phase 2 — Calc Integration Layer

**Status:** NOT STARTED
**Goal:** Build the marshalling layer between the Lua calc engine and the Qt/QML
UI: a single recalc-orchestration entry, an output serializer, the comparison-
calculator bridge (the override vocabulary that powers every "hovering this gives
you:" tooltip), config usage-set export, and — critically — a decided-and-enforced
threading/latency model. Every data-bearing tab (sidebar, calcs, config, tooltips)
depends on this.
**Depends on:** Phase 1 (tooltip framework to consume compares).
**References to load:** [[calc-engine-contract]] (primary), [[00-architecture]].

## Why this phase

The engine is driven by `buildFlag` + a synchronous, frame-blocking recalc that
runs 6–10+ full passes per edit, with hover tooltips calling `calcFunc`
synchronously mid-draw. In QML's retained-mode world this creates read-during-
rebuild hazards. Settle the model here, once, before tabs start reading calc data.

## Part 2.1 — Threading / latency spike (do FIRST)

- [ ] Measure real `CalcsTab:BuildOutput()` cost on representative builds (a big
  cluster-jewel build, a mirage-archer/trigger build). Budget the hover-compare
  paths (GemSelect per-candidate, item compare, node compare). (S)
- [ ] Decide and document the model: (a) synchronous Lua calc on the UI thread
  (accept latency), (b) dedicated engine thread + serialized message-passing +
  snapshot-on-complete, or (c) frame-budget slicing. **Enforce a single mutex
  around the Lua state or a snapshot-on-complete pattern regardless** — QML must
  never read `calcsEnv` while `calcFullDPS` mutates it. Record the decision in
  `STATUS.md`. (M — decision + guardrail; full async migration can be incremental.)

## Part 2.2 — Recalc orchestration service

- [ ] Expose one host-callable `recalculate()` that runs the legacy sequence
  `wipeGlobalCache → outputRevision++ → CalcsTab:BuildOutput() → RefreshStatList`
  (legacy `Build.lua:1183-1192`). Surface `outputRevision` as the cache-invalidation
  signal QML/tooltips key on. Debounce rapid edits if the spike shows it's needed. (M)

## Part 2.3 — Output marshalling

- [ ] Lua-side serializer for `env.player.output` / `output.Minion` /
  `output.MainHand`/`.OffHand` / `SkillDPS` array / warning lists → plain tables
  (QVariantMap). Handle `:`-containing keys (`Spec:LifeInc`), mixed value types,
  and the `BuildDisplayStats` schema. **Generate the field inventory from
  `BuildDisplayStats` + `CalcSections` + `powerStatList`**, not by hand. (M)
- [ ] FullDPS list marshalling: `SkillDPS` array of `{name, dps, count, trigger,
  skillPart, source}` for the sidebar FullDPS tooltip. (S)

## Part 2.4 — Comparison-calculator bridge

- [ ] Expose `GetMiscCalculator`/`GetNodeCalculator` closures as host-callable
  functions taking the override vocabulary (`addNodes`/`removeNodes` by id,
  `repSlotName`+`repItem`, `toggleFlask`/`toggleTincture`, `spec`, `useFullDPS`)
  and returning a **diffed stat list** — port `AddStatComparesToTooltip`/
  `CompareStatList` (`Build.lua:1783-1842`) logic to data, once. Consumed by item
  tooltips, node hover, anoint, gem select, trade. Feed results into the Phase 1
  tooltip framework's memoized-rebuild path. (M-L)

## Part 2.5 — Config usage-set export

- [ ] After each MAIN pass, serialize `env.conditionsUsed / enemyConditionsUsed /
  minionConditionsUsed / multipliersUsed / perStatsUsed / tagTypesUsed / modsUsed /
  skillsUsed / keystonesAdded` (names only, drop mod refs). This drives Config
  visibility (Phase 7) — export it here since it's a calc-boundary concern. (S)

## Part 2.6 — Party/buffExports seam audit

- [ ] Confirm the calc engine's write-backs still function under the Qt host:
  `partyTab.enemyModList` consumed at `CalcSetup.lua:565`, `setBuffExports` at
  `CalcPerform.lua:3640`. If Party is deferred, stub `partyTab.enemyModList` (empty
  ModList) and `setBuffExports` (no-op) so calcs keep working. (S)

## Acceptance gate

- `recalculate()` reproduces legacy output on the `TestBuilds` snapshots (tie into
  the Phase 0 calc-parity harness — same numbers).
- A node-hover or item-compare through the calculator bridge returns a correct
  diffed stat list matching legacy `CompareStatList` output.
- No read-during-rebuild data race under a stress test (rapid edits + hover).
- Usage sets export correctly (spot-check a keystone that gates a config option).
- `pob-selftest` green.

## Notes / risks

- **Do NOT re-model the tabs in C++.** The engine writes back into `skillsTab`/
  `configTab`/`partyTab`/`itemsTab` Lua objects; keep them as Lua and marshal reads.
- Breakdown data is NOT serializable up-front (closures + object refs + live
  Combine/Tabulate); leave the full breakdown drill-down to Phase 8 — this phase
  does output + compares, not breakdown tables.
- GlobalCache holds entire Env refs per skill and calculator closures hold
  persistent envs; watch memory in the long-lived Qt process (legacy wipes every
  edit). If you change `wipeGlobalCache` cadence, you can leak.
- `cacheSkillUUID` depends on `skillsTab.socketGroupList` identity/order — never
  rebuild those tables in C++; mutate in place.
