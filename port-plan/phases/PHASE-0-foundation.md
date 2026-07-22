# Phase 0 — Foundation, Provenance & Correctness

**Status:** NOT STARTED
**Goal:** Put the existing port on solid ground: version-control it, fix the QML
regressions that blank 8/10 views, fix the host-contract correctness bugs (settings
save, folder ops, window raise), resolve the `src/` divergence contract, and stand
up the verification gates. End state: all 10 views visibly render, `pob-selftest`
green, a capture baseline committed, and a repo you can bisect.
**Depends on:** nothing (do this first).
**References to load:** [[00-architecture]], [[host-api-contract]],
[[build-test-packaging]]. Load [[data-and-assets]] for Part 0.4, and
[[core-lifecycle]] for the userPath fix in Part 0.3.

## Why this phase first

Nothing is committed; the docs lie; 8 views are invisible despite green selftests.
Every later phase needs a trustworthy baseline and working gates. These are almost
all small, high-leverage fixes — do them before building anything new.

## Part 0.1 — Version control the port

- [x] Create a branch; `git add` `app/`, `TreeData/`, `docker/`, `tools/`,
  `scripts/`, `plans/`, deploy scripts, and this `port-plan/` folder. (S)
  → branch `phase-0-foundation`, commit `cf500ea4` (deploy scripts live under `app/`).
- [x] Separate legacy-engine feature work from port work in distinct commits: the
  uncommitted `src/` edits include a **"Suggest Path"** feature (`TreeTab.lua`
  +210, `PassiveSpec.lua`, `PassiveTreeView.lua`) that is unrelated to the port —
  commit it separately (or stash) so port provenance is clean. (S)
  → Suggest Path in its own commit `a60a9d35`; host seams (Build/Main/Data/UITheme)
  in `bcb46232`.
- [x] Extend `.gitignore`: `build-win/`, `dist/` DLLs, `captures/`, `build_*.log`,
  root `_*.py`/`_*.ps1` scratch files. Keep `src/Data/TimelessJewelData/*.bin`
  ignored (runtime cache). (S)
  → commit `b139c06d`; also ignored a leaked Google API-key file (see STATUS note).
- [x] Restore the 5 locally-deleted timeless-jewel `.zip` LUTs:
  `git checkout -- src/Data/TimelessJewelData/`. (S)

## Part 0.2 — Fix the QML view regressions (makes the app usable)

Verified defects in `app/qml/main.qml` (line numbers drift — re-confirm against the
live file; the *shape* of each bug is what matters):

- [x] **Un-nest 4 views.** `skillsView`, `itemsView`, `calcsView`, `configView`
  are accidentally children of the `treeView` Item (which is `visible:
  activeView==="TREE"`), so they can never show. Move them to be siblings under
  `contentArea`. (S)
  → Also affected `nodeTooltip` + the generic non-TREE content. Fix: close
  `treeView` right after its `Canvas`; the six blocks reparent to `contentArea`.
  Commit `<qml fix>`. (The file's own comments claimed this was already done — it
  was NOT; verified with a brace-balanced parser.)
- [x] **Fix 4 zero-sized views.** `notesView`, `importView`, `compareView`,
  `partyView` use `Layout.fillWidth/fillHeight` under a plain `Rectangle` parent
  (meaningless → 0×0). Switch to `anchors.fill: parent`. (S)
- [x] Re-run `--capture` and confirm all 10 views (TREE, LIST, + 8) render content,
  not just sidebar+topbar. (S)
  → `failed=0`, 10 PNGs @1100×720. skills/items/calcs/config/import show content;
  notes/party/compare correctly sized but empty (no data in the default build).
  NOTE for Phase 8: the CALCS view has a section-label/stat-row overlap (within-
  view layout bug, out of scope for 0.2).

## Part 0.3 — Fix host-contract correctness bugs

See [[host-api-contract]] priority list. All small, all real bugs.
**All verified via a headless probe (scratchpad `probe_host.lua` through
`pob-selftest`) + self-test exit 0 + `--capture` all 10 views.**

- [x] `MakeDir`/`RemoveDir` must return `(ok, errMsg)` in `LuaEngine.cpp`; this
  un-breaks `pob_createFolder`/`pob_deleteFolder` (which today always report
  failure) and the Main.lua folder flows. (S)
  → return contract now `ok` / `false,msg`; probe: `MakeDir_ok=true`, empty path
  → `false, "MakeDir: could not create directory"`. Lua wrappers now `return` it.
- [x] Add `SetForeground()` (raise/activate window) to the `pob` bridge +
  `pob_host.lua`; prevents an `attempt to call nil` crash if OAuth ever succeeds. (S)
  → `pob.setForeground` emits `foregroundRequested` → `win->raise/requestActivate`
  (wired in main.cpp). Headless: bridge absent, Lua wrapper no-ops.
- [x] `GetTime` → monotonic ms-since-start via `QElapsedTimer` (matches legacy
  semantics exactly). (S) → probe: t1=996, t2=997, monotonic & non-epoch.
- [x] **Wire `CanExit`/`OnExit` from the Qt shutdown path** so `main:Shutdown` runs
  → `SaveSettings` persists `Settings.xml`. **Data-loss fix.** Preserve the
  `errorReadingSettings` latch (don't clobber settings after a cloud-read failure).
  (M) → `OnExit` wired to `QGuiApplication::aboutToQuit`; latch respected (we only
  invoke the existing Shutdown path). **PARTIAL:** the interactive unsaved-build
  `CanExit` prompt (`OpenSavePopup`) needs a QML modal + close-event intercept →
  deferred to **Phase 3 (Build Shell)**; settings-save (the data-loss part) is done.
- [x] Make `IsKeyDown` return real modifier state (`queryKeyboardModifiers`). (S)
  → probe: `IsKeyDown("CTRL")` type=boolean, false (headless). CTRL/SHIFT/ALT only.
- [x] Populate `arg` from `QCoreApplication` args (open-on-launch, realized Phase 11).
  (S) → main.cpp collects non-harness positionals (arg[0]=program); set as the Lua
  `arg` global before boot; `pob_host` keeps it via `arg = arg or {}`.
- [x] **Fix userPath — CRITICAL.** (S) → `LuaEngine::init` now returns
  `QStandardPaths DocumentsLocation` (fallback `~/Documents`). Probe:
  `GetUserPath=C:/Users/User/OneDrive/Documents` (real Documents, not temp).
  NOTE: resolved to **OneDrive-redirected** Documents → the latent OneDrive
  `errorReadingSettings` latch (STATUS 7b) is now reachable; **Phase 1** owns it.
- [x] Guard the installed-mode launch branch. (S) → Found the real trigger:
  `app/CMakeLists.txt` installed the remote-style repo `manifest.xml` into `dist/`,
  so the *packaged* app also tripped devMode → source-tree userPath. Fix:
  `pack-manifest.cmake` stamps branch+platform onto the packaged manifest +
  writes `installed.cfg`. `_SRC_DIR != _RUNTIME_DIR` verified (dist/src vs
  dist/runtime). Packaged verification deferred to a deploy run (Phase 14).

## Part 0.4 — Resolve the `src/` divergence contract

- [ ] Document (in a short `app/lua/HOST_CONTRACT.md` or a `pob_host.lua` header)
  that `Build.lua` `viewList` registry, `Main.lua` `sideBarCollapsed`, `Data.lua`
  `TotalDotDPS`, and `UITheme.lua` are **sanctioned host seams**, not engine logic.
  Going forward, prefer `pob_host.lua` over new `src/` edits. (S)
- [ ] **Resync Qt `src/` to the legacy snapshot** so calc parity is meaningful:
  legacy has `ModScalability.lua` + `TradeSiteStats.lua` and merged implicits into
  `ModItemExclusive.lua`; Qt still has separate `ModImplicit.lua`. Move `Modules/*`
  and `Data/*` **together**. Normalize CRLF/LF before diffing so the real changes
  aren't buried under line-ending noise; never let `.gitattributes` rewrite the
  binary `.zip` LUTs. Re-apply the four sanctioned host seams on top. (M — mechanical
  but must be careful; see [[data-and-assets]].)

## Part 0.5 — Remove demo/scaffold code from the production path

- [ ] Delete the 800 ms "Test Build" rename `QTimer` in `main.cpp`. (S)
- [ ] Remove hardcoded stale paths: `main.cpp` `mainLog` (`c:/Users/User/source/
  repos/PathOfBuilding/...` — wrong repo root), `/workdir/*_result.txt` Docker
  outputs, `deploy_deps.ps1` (delete — superseded by `deploy-win-standalone.sh`).
  Parameterize `C:\msys64` in `run_pob_fusion.bat`. (S)
- [ ] Sweep repo-root litter (`build_*.log`, `_patch.py`, `_verify_*.py`,
  `_img_analyze*.ps1`) into a scratch dir or delete. (S)

## Part 0.6 — Stand up the gates + baseline

- [ ] Commit a **capture baseline**: `pob-qt --capture` on a desktop session, save
  the 10 PNGs as the reference set (the future "did I blank a view?" comparison).
  Note: offscreen QPA crashes on Windows — capture needs a real desktop or the
  `POB_CAPTURE_OFFSCREEN` opt-in. (S)
- [ ] Minimal CI: a Linux job running `docker/run-selftest.sh` on push/PR. (S)
- [ ] Stand up the **calc-parity harness** for the Qt host: pick ONE legacy
  snapshot as the parity baseline (Qt repo has 18 System specs, legacy 26 — decide),
  run `busted` `default` task, and add a Qt-host variant that loads the `spec/
  TestBuilds/3.13/*.xml` through `LuaEngine` and diffs `calcsTab.mainOutput` vs the
  committed `.lua` snapshots. (M)
- [ ] Mark stale plans superseded: `agent_handoff.md`, `Re-open-Tree-Render-Fix.md`,
  the `plans/tree_*` trilogy, `beautify_triage.md`. Keep their hard-verification
  methodology note. Fix or delete the dangling `.clinerules` reference to
  `.obsidian-vault/01_Wiki/`. (S)

## Acceptance gate

- All 10 views render content in `--capture` (not just chrome).
- `pob-selftest` exit 0; Linux CI green.
- Quit the app → `Settings.xml` is written; reopen → last build restored.
- **An existing legacy install's builds appear in the library** (userPath now points
  at Documents/Path of Building, not a temp dir).
- Create/rename/delete a build folder → succeeds (no false-failure reports).
- Calc-parity harness runs and passes against the chosen baseline snapshot.
- `git log` shows the port committed, with Suggest-Path split out.

## Notes

- Do NOT try to refactor `main.qml` here — just fix the nesting/layout bugs so
  views render. The component split is Phase 1 (do it after behavior is verifiable
  before/after).
- The offscreen-QPA crash blocks true headless visual CI; capture on a desktop
  runner for now. Full fix is deferred (Phase 14).
