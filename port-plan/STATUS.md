# PoB → Qt Port — STATUS (load this every session)

This is the only file loaded at the start of every session. It names the ACTIVE
phase, the invariants, the open decisions, and what is already true. **Read this,
then read only the ACTIVE phase file** (`phases/PHASE-N-*.md`). Load `reference/*`
only when the active phase tells you to. See `README.md` for the full protocol.

---

## ▶ ACTIVE PHASE

**Phase 0 — COMPLETE (implementation).** Local gate GREEN (pob-selftest 0,
pob-qt --headless 0, `--capture` all 10). **Next: Phase 1 — QML Component Library
& Shell** (`phases/PHASE-1-component-library.md`) — but per the stop-at-phase-
boundaries rule, **do NOT start Phase 1 until the user approves**. Before Phase 1,
a `dev` push should confirm CI green (`test.yml` busted + `qt-selftest.yml`), which
can't be run on the Windows workstation.

---

## ⛔ Hard invariants (override any older doc in the repo)

Full detail in `reference/00-architecture.md`. The short list:

1. **Do NOT emulate SimpleGraphic draw globals.** QML owns all rendering; the draw
   globals stay stubbed. Each view is re-authored in QML over marshalled Lua data —
   that is the whole strategy.
2. **Do NOT modify `src/` calc logic.** Only `app/` + the bridge seam
   (`app/lua/pob_host.lua`, `app/src/LuaEngine.cpp`) may change. The four *already-
   existing* sanctioned `src/` seams (viewList registry, sideBarCollapsed,
   TotalDotDPS, UITheme.lua) are host contract — don't expand the set without
   logging a decision here.
3. **Drive the engine via `build.calcsTab` + `build.buildFlag`**, never raw
   `calcs.*`. Preserve the Lua tab objects (skillsTab/configTab/itemsTab/partyTab) —
   the engine writes back into them; never re-model them in C++.
4. **Keep LuaJIT** (GC64 on x64).
5. **Every phase boundary: `pob-selftest` exit 0 + no view regresses** vs the
   committed capture baseline.
6. **Binaries run with cwd = `src/`** (engine reads data dirs relative to CWD).

---

## ❓ Open decisions (resolve when the relevant phase is reached; then record here)

- **Threading/latency model** (Phase 2) — sync-on-UI-thread vs engine-thread+
  message-passing vs frame-slicing. A mutex/snapshot guard is mandatory regardless.
- **Network strategy** (Phase 10) — real sub-script protocol vs targeted async
  `pob.http` shim of `launch:DownloadPage`.
- **Compare tab** (Phase 13) — in scope? It's fork-specific, session-only, 4986
  lines. Confirm before porting; if dropped, also drop "import as comparison".
- **Trade tooling** (Phase 12) — port now or defer past first shippable release?
  The offline planner (Phases 0–11) is already the core product.
- **Auto-update** (Phase 14) — distribution channel + updater mechanism (installer
  framework / GitHub releases / own server). Determines the replacement for the
  legacy Windows updater.
- **User-data policy** (Phase 1) — SHARE the legacy `Documents/Path of Building`
  dir (lossless round-trip + zero migration, but needs engine-version lockstep) vs
  SEPARATE dir with first-run migration. Recommend SHARE for v1. (The temp-dir
  path bug itself is fixed in Phase 0 regardless.)
- **Fontin font licensing** (Phase 1) — bundle Fontin TTFs (needs an exljbris
  Extended License), reuse the already-bundled bitmap atlases (a legal question),
  or substitute an OFL small-caps face (item-name visual drift). 104 sites.
- **Parity baseline snapshot** (Phase 0) — Qt repo has 18 System specs, legacy 26;
  pick one as the calc-parity reference.
- **OAuth token storage** (Phase 11) — keep Settings.xml plaintext (legacy) or move
  to OS keychain (deviation; changes LoadSettings/SaveSettings).

---

## ✅ Done log — what is ALREADY TRUE (most important first)

This is the "pertinent work already done" record. Verified against code + captures
during the July 2026 analysis; trust code over any older plan doc.

**▶ Phase 0 in progress (2026-07-22), branch `phase-0-foundation` off `dev`.**
- **0.1 done** — port under version control (gitignore `b139c06d`, host seams
  `bcb46232`, port `cf500ea4`, Suggest Path split out `a60a9d35`). `runtime-win32.zip`
  restored (legacy SimpleGraphic bundle — a Phase 14/15 decommission candidate, NOT
  dropped in Phase 0); the leaked `AQ.*.txt` API key was deleted by the user
  (gitignore still guards it).
- **0.2 done** — un-nested the 8 broken QML views (skills/items/calcs/config were
  trapped in `treeView`; notes/import/compare/party were 0×0). `--capture` renders
  all 10 (`failed=0`). The file's own comments falsely claimed this was already done.
- **0.3 done** — host-contract bugs fixed & probe-verified: userPath →
  `QStandardPaths` Documents (was a temp dir; **resolves to OneDrive Documents** →
  the latent `errorReadingSettings` latch is now reachable, Phase 1); MakeDir/RemoveDir
  return `(ok,err)`; GetTime monotonic; IsKeyDown modifiers; SetForeground; `arg`
  from CLI; `OnExit`→SaveSettings on quit (the unsaved-build `CanExit` *modal* is
  deferred to Phase 3). Packaging guard: `pack-manifest.cmake` stamps the dist
  manifest so installed builds don't trip devMode (deploy-verify in Phase 14).
  Capture harness hardened to wait for the final grab (was dropping LIST's PNG).
- **0.4 done** — resynced `src/` to the legacy snapshot for calc parity. **The
  coupled unit is `Modules/`+`Data/`+`Classes/`+ runtime/lua deps** — NOT just
  Modules/+Data/ (the plan under-scoped it). The initial Modules/+Data/ pass
  crashed build-mode init (`ItemDBControl` `pairs` vs a function-valued
  `powerStatList` entry legacy handles with `ipairs`) → no `calcsTab`. Completed:
  ~34 pure copies across Modules/Data/Classes, seam + Suggest-Path files 3-way
  merged in LF space, +sha2.lua/socket.lua runtime deps. `HOST_CONTRACT.md` has the
  corrected procedure. **Gotcha:** `pob-qt --headless | tail` reads *tail's* exit
  code — always check the binary's exit directly.
- **0.3 follow-up fix** — `IsKeyDown` crashed `pob-qt --headless` (queried GUI
  keyboard modifiers under a QCoreApplication; `qGuiApp` static_cast stays non-null).
  Now guarded with `qobject_cast<QGuiApplication*>`. Was latent since 0.3.
- **0.5 done** — removed production-path scaffold (800 ms Test-Build timer, dead
  LIST_FLOW/FRAMELOOP `/workdir` hooks, wrong-repo `mainLog` path), parameterized
  `C:\msys64`, deleted `deploy_deps.ps1`, swept 101 root litter files → gitignored
  `_scratch/`.
- **0.6 done** — capture baseline (`app/tests/capture-baseline/`, 10 PNGs); Linux
  CI `qt-selftest.yml` (build `Dockerfile.dev` + run `run-selftest.sh`; **needs a
  push to confirm green**); calc-parity baseline = **legacy** (spec/System → 25
  specs, asserted by busted in `test.yml`); `tools/qt_calc_parity.lua` loads all 5
  TestBuilds through the Qt bridge (exit 0) — the 3.13 snapshots are stale vs 3.28
  (~59% match, expected; `#builds` excluded from default busted). Stale plans
  bannered; `.clinerules` fixed.
- **Gate now GREEN locally:** pob-selftest 0, pob-qt --headless 0, `--capture` all 10.
- **Phase 0 implementation COMPLETE.** Verification pending only on CI (a `dev`
  push) and packaged-app/OneDrive behavior (Phase 14/Phase 1). **STOP: await user
  approval before starting Phase 1.**

1. **The C++/Lua bridge is solid and selftest-verified.** `pob-selftest.exe` exits
   0 across 15 headless checks (engine boot, calc output, zlib/HTTP-shim requires,
   save/load XML round-trip, build library, tree data/alloc/search, items, skills,
   calcs, config, misc tabs). This is the foundation everything builds on.
2. **The core architecture is settled** (invariant #1): marshal Lua data → C++
   QObject models → QML-native views; draw globals permanently stubbed. The old
   "implement SimpleGraphic draw calls in Qt" plan (master_migration_plan Phase 2)
   was deliberately abandoned. Event-driven `*Changed` signals replaced the old
   30 ms frame-poll (idle CPU ~0%).
3. **Bridges for all 9 tabs + LIST mode exist and pass headless selftests.** The
   engine-facing plumbing (`pob_host.lua`, ~1,680 lines) is largely done per tab;
   the GUI is what's incomplete.
4. **The tree renders — and only the tree (+ LIST).** As of analysis, **8 of 10
   views are visually broken** (QML nesting/layout bugs — Phase 0 Part 0.2 fixes
   them). The tree render itself is largely FIXED (sprites, frame rings, group
   backgrounds, gold connectors) — the alarming tree-render handoff docs are STALE.
5. **Nothing is committed to git and `src/` has diverged.** Entire port (`app/`,
   `TreeData/`, plans, tools) is untracked on top of upstream 3.28.0j; `src/` has 6
   modified engine files (4 sanctioned host seams + a stray "Suggest Path" feature)
   and 5 deleted timeless-jewel LUTs. Phase 0 fixes provenance.
6. **All networking is dead.** `LaunchSubScript` is a no-op stub → import-from-URL
   (partial via sync `pob.http`), trade, update check, OAuth, PoB Archives, poeurl
   all non-functional. Phase 10 owns this.
7. **Settings never save on exit** (`CanExit`/`OnExit` unwired) and folder ops
   misreport failure (`MakeDir`/`RemoveDir` broken return) — data-loss bugs fixed in
   Phase 0. `SetForeground` missing (OAuth crash).
7b. **userPath points at a temp dir** (`LuaEngine.cpp:39` = `QDir::tempPath()/pob-qt`),
   so existing users would see an **empty build library + reset settings**; saves
   land in an OS-wipeable dir. One-line fix in Phase 0 (`QStandardPaths` Documents).
   Fixing it exposes a latent OneDrive `errorReadingSettings` latch (Phase 1). Found
   by the critic pass.
7c. **The whole text pipeline is stubbed.** `DrawStringWidth`→1, `DrawStringCursorIndex`
   →0, `Theme.cpp:80` hardcodes `sans-serif` (no bundled font, no bold/mono). The
   `.tgf`/`.tga` bitmap font atlases already ship in `runtime/SimpleGraphic/Fonts/`.
   Metrics must be `.tgf`-backed, NOT `QFontMetrics` (caret/ellipsis/auto-width
   depend on it). It's more than 3 fonts (FONTIN family = 104 sites) and 2 color-code
   forms (`^0`–`^9` + `^xRRGGBB`). Phase 1 subsystem; found by the critic pass. See
   `reference/text-rendering.md`.
8. **Build/test/deploy infra exists**: MSYS2 mingw64 + Qt 6.11.1, `docker/run-
   selftest.sh` gate, `--capture` screenshot harness (offscreen QPA crashes on
   Windows → needs desktop session), `deploy-win-standalone.sh`, and the host-
   agnostic `busted`/TestBuilds calc-parity harness (not yet wired to the Qt host).
9. **Data/assets ship verbatim** (`src/Data` 65 MB, `TreeData` 520 MB/39 versions,
   `Assets` 2.5 MB). Timeless-jewel LUTs are zlib streams (not zstd), lazy-loaded.
   WebP tree art needs the qtimageformats plugin. Qt `src/` is an older upstream
   snapshot than legacy — resync (Modules+Data atomically) in Phase 0.

---

## 🗺 Phase index (spec lives in each file; load only the ACTIVE one)

| # | Phase | Gist |
|---|---|---|
| 0 | Foundation, Provenance & Correctness | commit, fix 8 broken views, host-contract bug fixes, resync src, gates |
| 1 | QML Component Library & Shell | split main.qml, Tier-0 infra, widgets, app shell + Options |
| 2 | Calc Integration Layer | recalc service, output marshalling, compare bridge, threading decision |
| 3 | Build Shell | top bar, side bar, stat panel, warnings, save/load orchestration |
| 4 | Tree Tab (finish & harden) | renderer, embeddable viewer, spec mgmt, power report, popups, timeless jewel |
| 5 | Skills Tab | skill sets, socket groups, GemSelect (fuzzy + DPS-sorted) |
| 6 | Items Tab (largest) | slots, lists, display-item editor, crafting, compare tooltips |
| 7 | Config Tab | generated controls, conditional visibility, modList plumbing |
| 8 | Calcs Tab & Breakdown | section grid + per-interaction breakdown drill-down |
| 9 | Notes & Party | color-code editor; party buff import |
| 10 | Network & Async Foundation | sub-script protocol / async HTTP; unblocks all network |
| 11 | Import/Export Tab | OAuth + account import, item/tree/skill import, build sharing |
| 12 | Trade (PoB Trader) | weighted trade search — SCOPE-GATED |
| 13 | Compare Tab | 6-view build comparison — SCOPE-GATED (fork-specific) |
| 14 | Packaging, Update & Distribution | installer, updater replacement, CI matrix, gates |
| 15 | Decommission & Final Hardening | retire SimpleGraphic contract, perf, parity sweep, upstream-sync |

**Dependency spine:** 0 → 1 → 2 → 3 → {4,5,6,7,8,9 in any order, each gated} →
10 → 11 → {12, 13} → 14 → 15. (Tree/Skills/Items/Config/Calcs/Notes/Party are
independent once the shell + calc layer exist; do them in value order. Network
before Import/Trade.)
