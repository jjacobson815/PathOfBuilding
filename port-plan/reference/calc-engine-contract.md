# Reference: Calc Engine External Contract

Everything the host/UI touches on the calc engine. The engine internals port
unchanged; this is the boundary the Qt host marshals across. Symbols are stable;
line numbers are legacy-checkout-relative.

## The five entry points (all via `build.calcsTab`)

Module assembled in `src/Modules/Calcs.lua`; loaded once by `CalcsTab.lua:26`.
All UI access is through `build.calcsTab`, never raw `calcs.*`.

1. **`calcs.buildOutput(build, mode)`** (`Calcs.lua:417`) → `env`. Called only from
   `CalcsTabClass:BuildOutput` with mode `"MAIN"` (→ `mainEnv`, `mainOutput =
   mainEnv.player.output`) and `"CALCS"` (→ `calcsEnv`, `calcsOutput`). MAIN also
   computes the **usage sets** (`conditionsUsed`, `multipliersUsed`, `skillsUsed`,
   `tagTypesUsed`, ... ) that drive Config visibility. CALCS also builds
   `BuffList/CombatList/CurseList` strings and `breakdown.*`.
2. **`calcs.getNodeCalculator(build)`** (`Calcs.lua:115`) → `(calcFunc, baseOutput)`.
   Persistent CALCULATOR env; per call wipes mods and applies a node list. Powers
   the tree heat map.
3. **`calcs.getMiscCalculator(build)`** (`Calcs.lua:123`) → `(calcFunc, baseOutput)`.
   `calcFunc(override, useFullDPS)` re-runs full `initEnv+perform`. **This is the
   entire comparison API** (there is no `getItemCalculator`; item compares use
   `override = {repSlotName, repItem}`).
4. **`calcs.calcFullDPS(build, mode, override, specEnv)`** (`Calcs.lua:176`) —
   iterates FullDPS-included skills; returns `{combinedDPS, TotalDotDPS, skills=
   [{name,dps,count,trigger,skillPart,source}], TotalPoisonDPS, ...}`.
5. **`calcs.initEnv` / `calcs.perform`** (`CalcSetup.lua:358` / `CalcPerform.lua:1098`)
   — the primitive pair; perform dispatches defence/triggers/mirages/offence.

**Modes:** `MAIN` (sidebar; buffMode forced EFFECTIVE), `CALCS` (calcs tab;
buffMode from `calcsInput.misc_buffMode` ∈ UNBUFFED/BUFFED/COMBAT/EFFECTIVE;
breakdown tables generated), `CALCULATOR` (comparison closures; party export off).

## The comparison override vocabulary (the whole compare surface)

`calcFunc(override, useFullDPS)` keys (verified against `CalcSetup.lua`):
`spec`, `conditions`, `addNodes`/`removeNodes`, `repSlotName`+`repItem`,
`extraJewelFuncs`, `toggleFlask`/`toggleTincture`. Callers: node hover
(`PassiveTreeView.lua:1603`), item/anoint tooltips (`ItemsTab.lua:2038` etc.),
PowerBuilder, trade query gen, CompareTab. Results are diffed by
`buildMode:AddStatComparesToTooltip`/`CompareStatList` (`Build.lua:1783-1842`)
against the `Modules/BuildDisplayStats` schema. **Port this diff logic once** and
reuse for every "hovering this gives you:" tooltip in the app.

## Data structures crossing the boundary

- **`env`** — live Lua object graph (`build, data, modDB, enemyDB, player, enemy,
  minion, flasks, requirementsTable, radiusJewelList`, plus MAIN-mode usage sets).
- **Actor** (`env.player/.minion/.enemy`) — `{modDB, level, output, breakdown,
  mainSkill, activeSkillList, weaponData1/2}`; `minion.output` **is aliased to**
  `output.Minion`. UI reads `mainSkill.skillFlags` (CheckFlag gating),
  `skillPartName, infoMessage, disableReason, activeEffect.grantedEffect.name`.
- **`output`** — flat string-keyed table; heterogeneous values (numbers, strings
  like `BuffList`, arrays like `SkillDPS`, nested `output.Minion`/`.MainHand`/
  `.OffHand`, keys with `:` like `Spec:LifeInc`). Fresh each perform.
- **`breakdown`** — only in CALCS mode. Per-stat arrays of colour-coded text lines
  plus structured fields consumed by `CalcBreakdownControl:AddBreakdownSection`:
  `radius` (→ visualiser), `rowList`+`colList`, `reservations`, `damageTypes`,
  `slots` (`{base,inc,more,total,source,sourceName,item(objref)}`), `modList`
  (`{mod(objref),value}`). **Contains closures and object refs — not serializable
  as-is.**
- **`GlobalCache`** (`Data/Global.lua:357`) — `{MAIN={},CALCS={},CALCULATOR={}}`
  keyed by skill UUID (`cacheSkillUUID` = `Name_SLOT_slotIdx_groupIdx`). Holds the
  **entire Env ref** per skill. Wiped by `wipeGlobalCache` on every rebuild.
- **ModDB/ModList API queried at render time**: `Sum/More/Flag/Override/List/
  Tabulate/Combine/Max/Min/HasMod/GetCondition/GetMultiplier/GetStat` on
  `ModStore.lua`. Mod shape per `docs/modSyntax.md`: `{name,type∈BASE|INC|MORE|
  OVERRIDE|FLAG|MAX|MIN|LIST, value, source, flags, keywordFlags, tags[]}`.

## Engine→UI write-backs (the entanglement)

`initEnv`/`perform` **write into UI-owned Lua state**: `group.mainActiveSkill[Calcs]`,
`build.mainSocketGroup`, `group.displayLabel/displaySkillList[Calcs]`,
`item.jewelRadiusData`, and `env.build.partyTab:setBuffExports(...)`
(`CalcPerform.lua:3640`). **The "engine unchanged" premise only holds if the Qt
host preserves faithful `skillsTab`/`configTab`/`partyTab`/`itemsTab` Lua object
shapes.** Any C++ re-modelling of those tabs breaks the engine — keep them as Lua
objects and marshal reads, don't replace them.

## Performance & threading

- **Cadence:** every mutation sets `build.buildFlag`; consumed once per frame in
  `buildMode:OnFrame` → `wipeGlobalCache → outputRevision++ → BuildOutput() →
  RefreshStatList`. **Fully synchronous, frame-blocking.**
- **Cost:** one keystroke ≥ 6 full perform passes (MAIN + CALCS + node + misc
  calculators, each also running calcFullDPS per FullDPS skill), commonly 10+.
- **No threads anywhere.** Single Lua state, single UI thread. The only slicing
  mechanism is the **PowerBuilder coroutine** (`CalcsTab.lua:454-719`), resumed
  once per frame from the tree draw, yielding on a 100 ms wall-clock budget.
- **Incremental seams:** `specCopy` via `modDB.parent` pointer reuse;
  `specEnv.accelerate = {nodeAlloc, requirementsItems, requirementsGems, skills,
  everything}` gates `wipeEnv`; GlobalCache per-skill reuse; PowerBuilder dedup by
  `node.modKey`.

## The single biggest architectural decision this forces

Hover tooltips (GemSelect DPS-per-candidate, item compares, node compares) call
`calcFunc` **synchronously during draw/hover**. `ItemDBControl` sorts via a
coroutine yielding every 50 ms. In legacy immediate-mode, stale reads are
impossible. In Qt/QML retained-mode, **any async recalc introduces read-during-
rebuild hazards** (QML reading `calcsEnv` while `calcFullDPS` mutates it). You
must choose and enforce one of:

- (a) synchronous Lua calc calls from the UI thread (accept latency), or
- (b) a dedicated engine thread with serialized message-passing + snapshot-on-
  complete, or (c) frame-budget slicing.

Do the **latency spike early (Phase 2)** on representative builds. Whatever you
pick, a single mutex around the Lua state or a snapshot-on-complete pattern is
mandatory. `tooltip:CheckForUpdate(obj, outputRevision)` is the legacy cache-
invalidation key — preserve `outputRevision` as the host's invalidation signal.

## Config plumbing (ConfigTab → env)

`Modules/ConfigOptions.lua` returns a ~2000-entry varList of `{var, type∈
check|count|integer|float|list|text, label, list, defaults, visibility predicates
(ifCond/ifEnemyCond/ifStat/ifFlag/ifNode/ifOption/... 562 occurrences), apply=
function(val, modList, enemyModList, build)}` (513 apply fns). `ConfigTab:BuildModList`
runs every apply into `configTab.modList`/`enemyModList`; `initEnv` does
`modDB:AddList(configTab.modList)`. **Feedback loop:** option visibility tests
`mainEnv.conditionsUsed/multipliersUsed/...` — config UI can't be drawn correctly
until a MAIN pass has run. Some `apply()` mutate other controls' placeholders and
reach into `build.configTab.varControls` — i.e. the *data* module depends on UI
*controls* existing. **The Qt host must provide a `varControls` shim** (small
engine-adjacent seam). Bandit/Pantheon live here as config vars (mirrored into
`<Build>` attribs).

## Node power / PowerReport

`CalcsTab:PowerBuilder` coroutine writes `node.power = {singleStat, offence,
defence, pathPower, distance, masteryEffects{}}` + `calcsTab.powerMax`. Stat menu
from `data.powerStatList` (`Data.lua:122`), with `GetFromOutput` accessors and
auto-generated `Minion*` variants. `TreeTab:BuildPowerReportList` flattens node
power into report rows. Drive the coroutine resume from a Qt timer/idle hook, not
the tree draw; never run it concurrently with a rebuild.

## Marshalling work items (feed Phase 2)

Recalc orchestration service · output marshalling (handle `:` keys, mixed types,
`output.Minion/.MainHand/.OffHand`) · comparison-calculator bridge (override vocab
→ diffed stat list) · breakdown drill-down serializer (per-interaction, resolves
Combine/Tabulate + item/node cross-refs to ids) · config usage-set export (names
only) · node-power marshalling · FullDPS list · party buffExports seam audit.
**Generate the output-field inventory from `BuildDisplayStats` + `CalcSections` +
`powerStatList`** rather than hand-curating — the effective contract is wider than
the five entry points.
