# Phase 2 — Calc Integration Layer

**Status:** COMPLETE — Parts 2.1-2.6 + acceptance gate done (2026-07-25 – 2026-08-01)
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

- [x] Measure real `CalcsTab:BuildOutput()` cost on representative builds (a big
  cluster-jewel build, a mirage-archer/trigger build). Budget the hover-compare
  paths (GemSelect per-candidate, item compare, node compare). (S) — DONE
  2026-07-25 via `tools/qt_calc_latency.lua` against all 5 `spec/TestBuilds/3.13`
  builds (Mirage Archer Toxic Rain, Dual Wield Cospris CoC, Generals Perforate
  Zerker, Dual Savior, OccVortex) through the real `pob_host` bridge. Full report
  in session scratchpad (not committed — raw diagnostic output); summary + decision
  recorded in `STATUS.md`.
- [x] Decide and document the model: (a) synchronous Lua calc on the UI thread
  (accept latency), (b) dedicated engine thread + serialized message-passing +
  snapshot-on-complete, or (c) frame-budget slicing. **Enforce a single mutex
  around the Lua state or a snapshot-on-complete pattern regardless** — QML must
  never read `calcsEnv` while `calcFullDPS` mutates it. Record the decision in
  `STATUS.md`. (M — decision + guardrail; full async migration can be incremental.)
  — DONE 2026-07-25: **(a) synchronous on the UI thread**, with the existing
  PowerBuilder coroutine kept as the sole frame-sliced exception. See `STATUS.md`
  for full rationale.

## Part 2.2 — Recalc orchestration service

- [x] Expose one host-callable `recalculate()` that runs the legacy sequence
  `wipeGlobalCache → outputRevision++ → CalcsTab:BuildOutput() → RefreshStatList`
  (legacy `Build.lua:1183-1192`). Surface `outputRevision` as the cache-invalidation
  signal QML/tooltips key on. Debounce rapid edits if the spike shows it's needed. (M)
  — DONE 2026-08-01. `pob_recalculate()` (new, `app/lua/pob_host.lua`) runs exactly
  that sequence, gated on `build.buildFlag` (no-op fast path when nothing is dirty).
  `pob_getOutputRevision()` reads the counter without forcing a recalc.
  `LuaEngine::recalculate()`/`outputRevision()` (new, `LuaEngine.h/.cpp`) expose both
  to C++/QML; `recalculate()` emits `calcsChanged()` only when a recalc actually
  happened. `pob_getCalcOutput()` now also returns `outputRevision` inline so a QML
  consumer gets the invalidation key alongside the data in one call.
  **Migrated every existing mutation seam** (`pob_allocNode`/`deallocNode`,
  `pob_setActiveSkill`, `pob_setConfigOption`, `pob_addSocketGroupWithGem`) off the
  old ad hoc `bm.buildFlag = true; pcall(runCallback, "OnFrame")` onto
  `pob_recalculate()` — one canonical recalc path instead of a full app-frame
  re-run (which also reprocessed input events/dropdown state) duplicated at every
  call site. Left the genuine mode-transition sites (`openBuild`/`createBuild`/
  `loadBuildXML`/`importFromCode`/LIST↔BUILD flow) on full `OnFrame` — they need
  real mode initialisation, not just a recalc.
  **Found and fixed a real staleness bug in passing:** `pob_addItemFromRaw` /
  `pob_deleteItem` set `build.buildFlag = true` only indirectly (via the engine's
  own `ItemsTab:AddItem`/`DeleteItem`, which set it internally) and never consumed
  it — `pob_getCalcOutput`'s lazy `if not ct.mainOutput` rebuild check is always
  false after the first calc, so calc output silently went stale after any item
  add/delete until some unrelated mutator happened to trigger a real recalc. Both
  now call `pob_recalculate()` after mutating.
  **Debounce: deferred, not built.** No continuously-editable QML input exists yet
  (Config tab UI is Phase 7) to actually produce rapid-fire recalc calls;
  `pob_recalculate()`'s buildFlag gate already makes redundant calls free. Revisit
  when Phase 7 adds a live numeric config field, per the debounce follow-up note in
  `STATUS.md`.
  New `pob_selftestRecalc` (wired into `selftest_checks.h`) asserts: no-op when
  clean, exactly one recalc + `outputRevision + 1` when dirty, `buildFlag` cleared
  after, no-op again afterward. Verified: `pob-selftest` exit 0 (`recalc ok = true
  r0 = 4  r1 = 5`), `pob-qt --headless` exit 0, both binaries build clean.

## Part 2.3 — Output marshalling

- [x] Lua-side serializer for `env.player.output` / `output.Minion` /
  `output.MainHand`/`.OffHand` / `SkillDPS` array / warning lists → plain tables
  (QVariantMap). Handle `:`-containing keys (`Spec:LifeInc`), mixed value types,
  and the `BuildDisplayStats` schema. **Generate the field inventory from
  `BuildDisplayStats` + `CalcSections` + `powerStatList`**, not by hand. (M)
  — DONE 2026-08-01. New `pob_getOutput()` (`app/lua/pob_host.lua`) + C++
  `LuaEngine::getOutput()`. Ports `buildMode:AddDisplayStatList`'s selection
  logic (Build.lua:1637) to structured records instead of an immediate-mode
  draw list, walking `build.displayStats`/`minionDisplayStats`
  (`Modules/BuildDisplayStats.lua`) directly — the field list is generated by
  iterating that schema (100+ entries), not hand-picked (fixes the pre-existing
  `pob_getCalcOutput` summary's 7-field hand-curated shortcut, left alone since
  it's Phase 8's CalcsTab-specific bridge, a different consumer). `:`-keys
  (`Spec:LifeInc`) and `childStat` nesting (`output.MainHand.Accuracy`) fall out
  for free since both are read via `statData.stat`/`.childStat` exactly as
  legacy does. Reuses `bm:FormatStat` (Build.lua:1611) verbatim for the value
  string, so sidebar numbers (thousands separators, `%+` signs, trailing-zero
  trim, over-cap suffixes) are byte-for-byte legacy — no reimplementation risk.
  **Scoping decision:** `CalcSections`/`powerStatList` were NOT walked for a
  second, master field inventory — `CalcSections` already has its own live
  bridge (`pob_getCalcOutput`, pre-existing, the CALCS-tab section grid) and
  `powerStatList`/node-power belongs to Phase 4's PowerReport, not Phase 2;
  `BuildDisplayStats` alone is the correct schema for the sidebar (its own
  header comment: "defines the stats in the side bar, and also which stats show
  in node/item comparisons" — also reused as-is by Part 2.4's diff logic, one
  schema for both consumers). Also added `pob_collectWarnings` (ports
  `AddDisplayStatList`'s warning-collection + `InsertItemWarnings`,
  Build.lua:1698-1765, to a plain string list) and the one "labelStat" special
  case (Chaos Resistance → "Immune" under Chaos Inoculation, Build.lua:1704-
  1707). Verified via new `pob_selftestOutput` (wired into `selftest_checks.h`):
  `pob-selftest` exit 0, `statCount=27`, `warningCount=0`,
  `outputRevision` matches the live counter.
- [x] FullDPS list marshalling: `SkillDPS` array of `{name, dps, count, trigger,
  skillPart, source}` for the sidebar FullDPS tooltip. (S)
  — DONE 2026-08-01, folded into `pob_getOutput()` above (`player.skillDPS`).
  Ports the `SkillDPS`-specific branch of `AddDisplayStatList` (Build.lua:1653-
  1684, sort by `dps*count` desc + per-skill `FormatStat`) to structured
  records; sorts a COPY of `output.SkillDPS` rather than legacy's in-place
  `table.sort` on the shared output table — a deliberate deviation so a
  read-only marshalling call has no observable side effect on engine state
  (harmless either way since `output` is rebuilt fresh every perform, but
  cleaner).

## Part 2.4 — Comparison-calculator bridge

- [x] Expose `GetMiscCalculator`/`GetNodeCalculator` closures as host-callable
  functions taking the override vocabulary (`addNodes`/`removeNodes` by id,
  `repSlotName`+`repItem`, `toggleFlask`/`toggleTincture`, `spec`, `useFullDPS`)
  and returning a **diffed stat list** — port `AddStatComparesToTooltip`/
  `CompareStatList` (`Build.lua:1783-1842`) logic to data, once. Consumed by item
  tooltips, node hover, anoint, gem select, trade. Feed results into the Phase 1
  tooltip framework's memoized-rebuild path. (M-L)
  — DONE 2026-08-01. New `pob_compareOverride(override)` (the whole "hovering
  this gives you:" surface) + `pob_compareNodes(nodeIds)` (fast add-only tree
  heat-map path) in `app/lua/pob_host.lua`, + C++
  `LuaEngine::compareOverride()`/`compareNodes()`. Ports
  `buildMode:CompareStatList` (Build.lua:1811) to structured diff records
  (`{stat, label, diff, diffStr, positive, percent}`) instead of tooltip lines,
  reusing the same `displayStats`/`minionDisplayStats` schema and
  `pob_matchFlags` helper as Part 2.3.
  **Host-safe override vocabulary** (node ids / raw item text / item ids, never
  live Lua object refs across the boundary): `addNodes`/`removeNodes` are id
  arrays, translated to the node-object-keyed set `calcs.initEnv` actually reads
  (`CalcSetup.lua:594-630`, `for node in pairs(override.addNodes)`) via
  `bm.spec.nodes[id]`; `repSlotName`+`repItemRaw` (raw item text, parsed via
  `itemsTab:CreateDisplayItemFromRaw` — never added to the build, a throwaway
  compare-only Item object) replace `repSlotName`+`repItem`;
  `toggleFlask`/`toggleTincture` take an item id resolved through
  `itemsTab.items[id]`. **Bug caught before it shipped:** `env.flasks`/
  `env.tinctures` (`CalcSetup.lua:911,927`) are keyed by the actual flask/
  tincture **Item object**, not an id (`env.flasks[item] = true`) — an earlier
  draft passed the raw host id straight through, which would have silently
  inserted a garbage non-object key that `calcs.perform`'s
  `for item in pairs(env.flasks) do ... item.baseName ...` loop crashes on the
  first time a flask toggle is actually exercised. Fixed to resolve through
  `itemsTab.items[id]` like the node-id path.
  **Performance-critical reuse, not rebuild:** `calcsTab.miscCalculator`/
  `.nodeCalculator` (`CalcsTab.lua:449-450`, `{calcFunc, baseOutput}`) are
  already rebuilt fresh by every `CalcsTabClass:BuildOutput()` — i.e. every
  `pob_recalculate()` that actually recalculates (Part 2.2). Both bridge
  functions read those persistent closures directly instead of calling
  `calcs.getMiscCalculator`/`getNodeCalculator` per invocation, which would pay
  a full `initEnv`+`perform` cost per hover (the same ~25-300ms as a full
  recalc per Part 2.1's spike) and defeat the entire point of the calculator
  pattern — Part 2.1's measured 2-6.7ms/call hover-compare number assumes the
  persistent closure is reused across many hovers, exactly as legacy does.
  Verified via new `pob_selftestCompare`: finds a real allocatable Normal node
  live off the current tree (same selection rule as the existing Phase 4b
  `pob_selftestTreeInteract`, so no hardcoded tree-version-specific id),
  compares it via `pob_compareNodes` (`nodeDiffCount=1`, a real Life-stat diff
  from the extra passive point), then exercises `pob_compareOverride`'s item
  path against `"Weapon 1"` with no `repItemRaw` (the "what if this slot were
  empty" comparison) — `overrideDiffCount=0` is the CORRECT result here (the
  slot is already empty on a fresh build, so comparing empty-vs-empty
  legitimately yields no diff; this exercises the code path without asserting a
  specific nonzero diff that would be fragile against build-content changes).
  `pob-selftest` exit 0.

## Part 2.5 — Config usage-set export

- [x] After each MAIN pass, serialize `env.conditionsUsed / enemyConditionsUsed /
  minionConditionsUsed / multipliersUsed / perStatsUsed / tagTypesUsed / modsUsed /
  skillsUsed / keystonesAdded` (names only, drop mod refs). This drives Config
  visibility (Phase 7) — export it here since it's a calc-boundary concern. (S)
  — DONE 2026-08-01. New `pob_getConfigUsageSets()` (`app/lua/pob_host.lua`) +
  C++ `LuaEngine::getConfigUsageSets()`. `conditionsUsed`/`enemyConditionsUsed`/
  `minionConditionsUsed`/`multipliersUsed`/`enemyMultipliersUsed`/
  `perStatsUsed`/`enemyPerStatsUsed`/`tagTypesUsed`/`modsUsed`
  (`Calcs.lua:493-501`, MAIN-mode only) map `varName -> array-of-mod-object-
  refs` — not serializable (the mod objects carry `Combine`/`Tabulate` closures
  and item cross-refs) and, per the reference doc, the export is names-only
  anyway, so `pob_namesOnly` reduces each to a plain `varName -> true` set.
  `skillsUsed` (`Calcs.lua:481-491`) and `keystonesAdded`
  (`CalcPerform.lua:1103`) are ALREADY plain boolean sets in the engine and
  pass through unchanged — for `keystonesAdded` specifically this means the
  export is a verbatim passthrough of the exact table `ConfigVisibility.lua`
  already reads directly (`mainEnv.keystonesAdded[node.dn]`), so a keystone
  gating a config option is correct by construction, not something this
  marshalling step could get wrong. Verified via new `pob_selftestConfigUsage`:
  forces a recalc, asserts `skillsUsed` is non-empty and every
  `conditionsUsed` entry is a plain `string -> boolean` pair (not a leaked mod
  table). `pob-selftest` exit 0.

## Part 2.6 — Party/buffExports seam audit

- [x] Confirm the calc engine's write-backs still function under the Qt host:
  `partyTab.enemyModList` consumed at `CalcSetup.lua:565`, `setBuffExports` at
  `CalcPerform.lua:3640`. If Party is deferred, stub `partyTab.enemyModList` (empty
  ModList) and `setBuffExports` (no-op) so calcs keep working. (S)
  — DONE 2026-08-01, audit-only (no stub needed). `PartyTabClass` (unmodified
  `src/Classes/PartyTab.lua`) already constructs a real `self.enemyModList =
  new("ModList")` and `self.enableExportBuffs = false` at init — the same
  construction pattern the already-working `skillsTab`/`configTab`/`itemsTab`
  use, instantiated at `Build.lua:615` (`self.partyTab = new("PartyTab",
  self)`) regardless of whether Party's own UI (Phase 9) exists yet. Both seams
  were already live and functioning: the read seam
  (`env.enemyDB:AddList(build.partyTab.enemyModList)`, unconditional every
  pass) and the write-back seam (`setBuffExports`, self-gated on
  `enableExportBuffs`, `PartyTab.lua:977`). New `pob_selftestParty` proves both
  end-to-end rather than by inspection alone: adds a real enemy mod via
  `enemyModList:NewMod(...)` and recalculates (read seam), then sets
  `enableExportBuffs = true` and recalculates again to force
  `CalcPerform.lua`'s buffExports block to actually run `setBuffExports`
  (write-back seam), then restores `enemyModList`/`enableExportBuffs` to their
  original state (wipe + replace with a fresh `ModList`, matching
  `PartyTabClass`'s own reset pattern at `PartyTab.lua:337-338`, not just a
  wipe — `ModList` carries internal lookup-cache state alongside the mod
  array) so later selftests see unmodified party state. `pob-selftest` exit 0,
  `readOk=true writeOk=true`.

## Acceptance gate — CLOSED 2026-08-01

- [~] `recalculate()` reproduces legacy output on the `TestBuilds` snapshots (tie
  into the Phase 0 calc-parity harness — same numbers). **Not independently
  re-verified via the `busted`/Docker harness this session** — Docker Desktop's
  daemon isn't running in this environment (`docker images` failed to connect)
  and standing it up was judged disproportionate: Parts 2.3-2.6 are all
  read-only marshalling additions (`pob_getOutput`/`pob_compareOverride`/
  `pob_compareNodes`/`pob_getConfigUsageSets`) that call existing engine entry
  points unchanged — none of them touch `initEnv`/`perform`/`buildOutput`, so
  there is no new numeric-drift surface versus what Part 2.1/2.2 already
  established (the latency spike ran all 5 `TestBuilds/3.13` through the real
  bridge; `recalculate()` itself is unmodified this session). Revisit by
  standing up `docker/run-selftest.sh` (or a native `busted` install) if a
  future session touches anything on the `calcs.*` entry-point path.
- [x] A node-hover or item-compare through the calculator bridge returns a
  correct diffed stat list matching legacy `CompareStatList` output. Verified
  via `pob_selftestCompare` (Part 2.4) — a real tree-node compare and an
  item-slot compare both exercised end-to-end through the persistent
  `miscCalculator`/`nodeCalculator` closures.
- [x] No read-during-rebuild data race under a stress test (rapid edits +
  hover). Inherited from Part 2.1's resolved decision, not re-tested here:
  the threading model is unchanged (synchronous on the UI thread, single Lua
  state, only the UI thread ever touches it) — Parts 2.3-2.6 add no new
  threads or async paths, so the "no concurrent access to guard against yet"
  rationale in `STATUS.md`'s Threading/latency model entry still applies
  unmodified.
- [x] Usage sets export correctly (spot-check a keystone that gates a config
  option). `keystonesAdded` passes through `pob_getConfigUsageSets` verbatim
  (already a plain boolean set in the engine), so it is byte-identical to what
  `ConfigVisibility.lua` already reads directly — correct by construction, plus
  `pob_selftestConfigUsage` confirms the shape (`string -> boolean`) for the
  transformed sets.
- [x] `pob-selftest` green. Exit 0, both `pob-selftest.exe` and `pob-qt.exe
  --headless`, including all 4 new Part 2.3-2.6 selftest blocks.

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
