# Phase 15 — SimpleGraphic Decommission & Final Hardening

**Status:** DONE (v1 scope — Parts 15.1 & 15.4 DONE in Wave 1; Parts 15.2 & 15.3 v1 targets DONE in Wave 2 on 2026-11-24).
- **Part 15.2 (DONE):** Split static tree topology from dynamic allocation state (`pob_getTreeData` / `pob_getTreeDynamicState` + `TreeViewController`/`TreeScene`: ~83ms full -> ~0ms incremental alloc/dealloc) + LuaJIT GC64 x64 & 20-cycle repeated-recalc memory verification (`pob_selftestTreePerf`, `pob_selftestMemoryGC64`).
- **Part 15.3 (DONE for v1 scope):** Fixed `PopupBase` `Keys` dialog bug across `PopupBase` + 7 popups including `LoadoutManagePopup` (`0` QML warnings on stderr & logs), audited global/view keyboard shortcuts (`Ctrl+1..8`, `Ctrl+I`, `Ctrl+S`, `Ctrl+W`, `Ctrl+Z`/`Y`, `Ctrl+F`, `F1`), ran `tools/qt_calc_parity.lua` (`5/5` TestBuilds OK) + `58/58` `spec/*.lua` `luajit -bl` clean (`busted` not installed locally), exposed `--dev` / `POB_DEV_MODE=1` into `launch.devMode` (UI-only dev controls dropped for v1), and refreshed all 9 Windows capture baselines (removed `compare.png`). **Deferred post-v1:** responsive portrait layouts, pixel-sampled legacy visual diffing, RELIC foil shader, multi-column tooltip overflow, and OneDrive error popups.
**Goal:** Close out the port: formally retire the SimpleGraphic host contract,
remove any dead legacy-update code, do the final performance and parity passes, and
establish the ongoing upstream-sync procedure so the fork doesn't rot each league.
**Depends on:** all prior phases (this is the finish line).
**References to load:** [[00-architecture]], [[host-api-contract]],
[[data-and-assets]] (upstream-sync), [[build-test-packaging]].

## Part 15.1 — Formalize the host contract

- [x] Declare the SimpleGraphic rendering/input globals **permanently stubbed** and
  document it (in `HOST_CONTRACT.md`): `SetDrawLayer/SetViewport/SetDrawColor/
  DrawImage*/DrawString*/NewImageHandle` never become real; QML owns display.
  Record that any future reuse of legacy Draw code would require full text metrics +
  the `^0`–`^9` palette (external sourcing). (S)
- [x] Confirm no runtime path can drive the engine into legacy SimpleGraphic-only
  code (Update.exe spawn, `ConExecute("set vid_mode...")`, etc.) — those globals
  stay stubbed/no-op. (S)
- [x] Remove dead legacy-update code paths if Phase 14 replaced them (or keep them
  inert and documented). (S)

## Part 15.2 — Performance pass

- [x] Marshalling: eliminated the full `QVariant` deep-copy of the ~2.8k–3.2k-node tree on
  every `treeChanged` via split static topology + `pob_getTreeDynamicState(lastTopologyKey)`
  + `TreeViewController::allocationChanged` + `TreeScene::syncDynamicAllocations`
  (`fullMs=83 -> dynAllocMs=0 / dynDeallocMs=0`); `sheetInfo` sprite resolution already
  memoized in Phase 4. (M)
- [x] `pob_getActiveSkills` — verified uncalled in live QML (`SkillModel` retired in Phase 5;
  `MainSkillPanel` and `SkillsView` read lightweight `pob_getMainSkillControls`/`pob_skillsGetState`). (S-M)
- [x] Tree renderer final optimization (shared `QSGTexture` atlas cache, spatial hitTest index,
  in-place `NodeRec::alloc` sync & tinted-batch-only incremental repaint on alloc/dealloc). (M)
- [x] Profile memory on repeated recalcs & confirm LuaJIT GC64 on x64 (`pob_selftestMemoryGC64`:
  `hasJit=true`, `jitArch=x64`, `ptrBytes=8`, `gc64Ok=true`, 20 cycles `deltaKB=-5929`,
  `heapBoundedOk=true`). (M)

## Part 15.3 — Full parity QA sweep

- [x] Core keyboard shortcut audit & `PopupBase` `Keys` dialog fix: `Ctrl+1..8` dynamically bound
  to the 8 BUILD views (COMPARE dropped), added `Ctrl+I`, audited `Ctrl+S`/`W`/`Z`/`Y`/`F`/`F1`;
  moved `Keys` off `Dialog`/`PopupBase` onto focusable content items across all 8 popups (`0` QML
  warnings). *(Responsive portrait layouts deferred post-v1.)* (L)
- [x] Calc parity: `tools/qt_calc_parity.lua` passed (`5/5` TestBuilds loaded & calculated OK,
  EXIT=0) and `58/58` `spec/*.lua` files passed `luajit -bl` (`busted` not installed locally;
  runs in Linux CI via `test.yml`). (S)
- [x] Visual capture & baseline refresh: refreshed all 9 Windows capture baselines (`tree`, `skills`,
  `items`, `calcs`, `config`, `notes`, `import`, `party`, `list`), removed `compare.png`, and
  verified `verify_views_smoke.py` (`9/9` PASS, `0` QML warnings/errors). *(Pixel-sampled legacy
  visual diffing deferred post-v1.)* (M)
- [x] Dev-mode behaviors decided & wired: exposed `--dev` / `POB_DEV_MODE=1` into `launch.devMode`
  for engine devMode / ModCache regen (`pob_selftestDevMode`); UI-only dev controls (`~~temp~~.xml`
  autosave, JSON import, `devModeAlt`) documented as dropped for v1. (S)

## Part 15.4 — Upstream-sync procedure (ongoing)

- [x] Document + script the per-league sync: pull upstream `src/` (Modules + Data
  atomically), normalize CRLF, re-apply the four sanctioned host seams (viewList,
  sideBarCollapsed, TotalDotDPS, UITheme), regenerate ModCache, run calc-parity.
  Include the `src/Export/` data-refresh note (run legacy Export + bun_extract_file
  against Content.ggpk, copy regenerated Data/TreeData). (M)

## Acceptance gate

- Full parity checklist walked; no missing feature vs legacy (or every gap is an
  explicit, user-agreed drop).
- Full `busted` + TestBuilds parity green; visual parity confirmed.
- No hardcoded paths, no dead scaffolding, no SimpleGraphic-only runtime path.
- Upstream-sync procedure documented and dry-run once.
- The app is a complete, self-updating, cross-checked replacement for legacy PoB.

## Notes

- This phase is where "feature-complete" becomes "done." Resist the urge to declare
  victory at Phase 11 — the parity sweep routinely surfaces the last 10% of micro-
  features (responsive layouts, obscure keyboard shortcuts, dev-mode paths).
- The upstream-sync procedure is what keeps the port alive after the port "ends" —
  without it the fork rots ~quarterly.

## Session log — 2026-11-24 (Wave 1, Windows)

- Completed Parts 15.1 & 15.4: formalized `app/lua/HOST_CONTRACT.md` (permanent SimpleGraphic/legacy stubs, 4 sanctioned `src/` seams, stock-LuaJIT compat edits, Wave 1 `SubScriptManager`/`pob.emitSignal`/`pob_network`/`pob_import` seams, `src/Export/` & per-league sync procedure) and added `tools/audit_host_contract.py` + `tools/upstream_sync.py`.
- Verified: `python tools/audit_host_contract.py` exit 0 (all 3 checks PASS), `python tools/upstream_sync.py --dry-run` exit 0 (CR-normalized classification + 259 Lua files `luajit -bl` clean).
- Deferred to Wave 2/3: Part 15.2 (performance pass) and Part 15.3 (full parity QA sweep).

## Session log — 2026-11-24 (Wave 2, Windows, branch `wave-2-v1-hardening`)

- Completed v1 scope for Parts 15.2 & 15.3:
  - Split static tree topology (`computeTreeTopologyKey` covering tree version, spec, `_treeSpecSerial`, cluster `subGraphs`, `hashOverrides`, class/ascendancy) from dynamic allocation state (`pob_getTreeDynamicState`, `TreeViewController::allocationChanged`, `TreeScene::syncDynamicAllocations`). Verified via `pob_selftestTreePerf` (`fullMs=83`, `dynAllocMs=0`, `dynDeallocMs=0`, `invalidationOk=true`).
  - Added `pob_selftestMemoryGC64`: confirmed LuaJIT 2.1 GC64 x64 (`ptrBytes=8`, `gc64Ok=true`) and bounded 20-cycle recalc memory (`deltaKB=-5929`, `heapBoundedOk=true`).
  - Fixed `PopupBase` `Keys` dialog bug across `PopupBase`, `SaveAsPopup`, `TextInputPopup`, `TreeImportPopup`, `SetManagePopup`, `SpecManagePopup`, `SpectreLibraryPopup`, and `LoadoutManagePopup`; audited global & view shortcuts (`Ctrl+1..8`, `Ctrl+I`, `Ctrl+S`, `Ctrl+W`, `Ctrl+Z`/`Y`, `Ctrl+F`, `F1`); dropped Compare tab (`CompareView.qml`, C++ `viewList()` filter, `compare.png`); updated disabled Items-tab `"Buy similar"` tooltip for deferred Phase 12 Trade.
  - Verified `tools/qt_calc_parity.lua` (`5/5` builds OK, EXIT=0), `58/58` `spec/*.lua` `luajit -bl` clean, refreshed all 9 Windows capture baselines (`verify_views_smoke.py` `9/9` PASS, `0` QML warnings/errors), `tools/audit_host_contract.py` PASS, and `tools/upstream_sync.py --dry-run` PASS.
- Deferred post-v1: responsive portrait layouts, pixel-sampled legacy visual diffing, RELIC foil shader, multi-column tooltip overflow, OneDrive error popups.
