# PoB → Qt Port — STATUS (load this every session)

This is the only file loaded at the start of every session. It names the ACTIVE
phase, the invariants, the open decisions, and what is already true. **Read this,
then read only the ACTIVE phase file** (`phases/PHASE-N-*.md`). Load `reference/*`
only when the active phase tells you to. See `README.md` for the full protocol.

---

## ▶ ACTIVE PHASE

**Phase 1 — QML Component Library & App Shell — IN PROGRESS** (started 2026-07-23,
user-approved). Spec: `phases/PHASE-1-component-library.md`. Phase 0 is COMPLETE
(implementation), local gate GREEN (pob-selftest 0, pob-qt --headless 0,
`--capture` all 10).

**CI confirmation: DEFERRED (skipped by user 2026-07-23).** Pushed the branch to
the personal fork `github.com/jjacobson815/PathOfBuilding` `dev` (`git push fork
phase-0-foundation:dev`, ff `92bc0df0`→`fa3cc1ea`); all workflows dispatched but
GitHub refused to start any job — *"account is locked due to a billing issue"* on
the `jjacobson815` account. So `test.yml`/`qt-selftest.yml` remain **unverified in
CI** (config is valid; jobs never ran). Re-trigger once the billing lock clears
(Actions page re-run, `workflow_dispatch`, or empty commit). `fork` remote is now
configured locally.

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
- **Fontin font licensing** (Phase 1) — **DECIDED 2026-07-23: DEFER.** Build the
  TextMetrics + color-code subsystem now against the VAR/FIXED fonts (Liberation
  Sans / mono); stub `fontFontinSC`/`fontFontin` → the VAR face. Revisit the real
  licensing choice (bundle Fontin TTFs w/ exljbris Extended License, reuse the
  already-bundled bitmap atlases [legal Q], or substitute an OFL small-caps face)
  before shipping. 104 item/gem/tree sites will use VAR until then.
- **Parity baseline snapshot** (Phase 0) — Qt repo has 18 System specs, legacy 26;
  pick one as the calc-parity reference.
- **OAuth token storage** (Phase 11) — keep Settings.xml plaintext (legacy) or move
  to OS keychain (deviation; changes LoadSettings/SaveSettings).

---

## ✅ Done log — what is ALREADY TRUE (most important first)

**▶ Phase 1 (started 2026-07-23):** **Part 1.3 Tier 1 + Tier 2 widgets
COMPLETE (2026-07-24).** 11 new components in `app/qml/components/`
(Label/Section/RectangleOutline/Button/CheckBox/Dragger/Slider = Tier 1;
ScrollBar/PathControl/TextListControl/SearchHost = Tier 2), each a faithful
port of its `src/Classes/*.lua` counterpart over the Tier 0 kit. Verified via
temporary debug harnesses in `main.qml` (one per tier — every widget + state
screenshotted via `--capture`, then removed) + full gate (`pob-selftest` 0,
`pob-qt --headless` 0, `--capture` failed=0, no regression vs the Phase 0
baseline) after each tier. Full detail (bugs found, deviations, deferrals) is
in `phases/PHASE-1-component-library.md` Part 1.3; the two load-bearing
gotchas for future sessions:
- **`Text`-derived items' `implicitWidth`/`implicitHeight` are READ-ONLY in Qt
  Quick** (computed from content via Qt's own font metrics — NOT
  `TextMetrics`). Any custom `Text`/`ColorText`-based widget (like `Label.qml`)
  must size itself via the real `width`/`height` properties instead; assigning
  `implicitWidth`/`implicitHeight` directly throws "Invalid property
  assignment" at QML-load time and silently kills the WHOLE window (`qml.
  rootObjects()` comes back empty, no visible error — see the `main.cpp`
  QML-warnings-to-`mainLog` addition below). Consumers must read a `Label`'s
  size via `.width`/`.height`, never `.implicitWidth/Height`.
- **A disabled control's foreground content (text/glyph) must NOT reuse
  `theme.disabled`** — that token is Chrome's own disabled FILL color, so
  text painted in it over that fill is invisible (same color as its
  background). Content drawn ON the disabled Chrome fill uses
  `theme.background` for contrast; content drawn OUTSIDE the control (e.g.
  CheckBox's label, which sits beside the box on the ordinary page
  background) uses `theme.muted` instead. Pick per-context, not by rote.

**Diagnostic added in passing:** `main.cpp` now mirrors `QQmlApplicationEngine::
warnings` into the existing `mainLog` file — `pob-qt` is a GUI-subsystem binary
so QML compile errors otherwise vanish into `OutputDebugString` with zero
observable output (exactly how the `implicitWidth` bug above was invisible
until this was added). Check `%TEMP%/pob-qt-main.log` first whenever `pob-qt`
loads a blank/nonexistent window.

**Naming collision flagged for Phase 3 / Part 1.4:** `components/Button.qml`
shares its name with `QtQuick.Controls.Button` (already used unqualified in
`main.qml`'s top bar). A bare `import "components"` in any file that also does
`import QtQuick.Controls` unqualified is an AMBIGUOUS TYPE error. Views
adopting the component library must qualify it (`import "components" as
Widgets` → `Widgets.Button`) or drop the unqualified `QtQuick.Controls`
import.

**Observed, not caused by this work:** a capture-vs-baseline diff pass showed
the top-bar BUILD/LIST button ORDER differs run-to-run — `luaEngine.
modeNames()` iterates a Lua table without a guaranteed stable order. Cosmetic
today; Part 1.4's mode manager should sort/pin an explicit order before any
UI relies on position (e.g. "the active mode button is always first").

**ResizableEditControl DEFERRED** (Tier 2 item, but legacy-subclasses
`EditControl`, Tier 3/751 lines, not built) — revisit whenever `EditControl`
gets built (here-or-Phase-3, per the existing Tier 3 deferral note).

Next: Part 1.4 (app shell: mode manager, Settings round-trip, Options
dialog) — see phase file. Tier 3 deep widgets (EditControl, DropDownControl,
ListControl base, etc.) remain backlogged per-phase-first-need.

**Part 1.2 Tier 0 infrastructure
COMPLETE (2026-07-24).** All 6 items done, each verified via a temporary
debug harness in `main.qml` (screenshotted via `--capture`, then removed)
+ full gate (`pob-selftest` 0 / `pob-qt --headless` 0 / `--capture` failed=0)
green after every item:
- **Theme/chrome kit** — `Chrome.qml`/`Arrow.qml`/`CheckMark.qml`, built over
  the EXISTING `theme.border/borderStrong/hover/active/disabled/
  radiusControl` tokens — NOT legacy greyscale; the app shell already
  committed to the flat "Cyber Citrus" design system.
- **Tooltip framework (core)** — `Tooltip.qml`: clear/addLine/addSeparator/
  checkForUpdate/showAt with viewport-flip, word-wrap, ColorText integration.
  Multi-column overflow, 13-config rarity header art, oil/recipe row, child
  tooltips DEFERRED (no real item/gem/tree call site to validate against).
- **Modal popup framework** — built on `QtQuick.Controls.Dialog` (not hand-
  rolled — gives dim overlay/centering/stack-via-Overlay for free):
  `PopupBase.qml` + `PopupButton.qml` (minimal, NOT the future Tier 1
  ButtonControl) + 4 canned dialogs (Message/Confirm/TextInput/NewFolder).
  Documented deviation: stacked popups stay visible-but-dimmed underneath
  the topmost instead of un-drawn like legacy (functionally equivalent).
- **Drag-and-drop framework (core)** — `DragSource.qml`/`DropTarget.qml` on
  Qt Quick's own `Drag`/`DropArea`: typed payload, 10px threshold, target
  highlight. Reorder insertion-caret + text drag-label DEFERRED (no
  ListControl consumer yet). Verified rest-state rendering only — `--capture`
  can't synthesize a mouse-drag gesture.
- **UndoHandler** — `UndoHandler.qml`, a hand-traced faithful port of the
  101-state ring-buffer algorithm; a 7-assertion self-test (add/undo/undo/
  redo/redo + boundary flags) passed via a colored-text debug capture.
- **Input/focus model** — a DECISION more than a component: TAB-order →
  Qt's native `KeyNavigation`; RETURN/ESC → already in `PopupBase`;
  wheel-on-hover → free in Qt (routes by cursor position, not focus, unlike
  legacy); `OnHoverKeyUp` → new `HoverKeyArea.qml` (HoverHandler wrapper).
  The actual "route keypress to whatever's hovered" dispatcher is deferred
  to the first real consumer (Phase 5/6). Legacy's capture-by-return focus
  model + mouse-as-key are intentionally NOT reproduced — Qt's native
  signal/focus system supersedes them.

**Part 1.2a COMPLETE (2026-07-24)** — fonts
bundled (Liberation Sans Regular/Bold + Bitstream Vera Sans Mono TTFs, official
upstream sources, into `runtime/SimpleGraphic/Fonts/` alongside the `.tgf`
atlases) + registered via `QFontDatabase::addApplicationFont` in `main.cpp`;
`Theme` extended with `fontVar`/`fontVarBold`/`fontFixed` + a `fontFor(name)`
resolver over the 7 `fontMap` names (FONTIN* stub → VAR face, licensing still
deferred); new shared `ColorText` parser (`app/src/ColorText.{h,cpp}`, QML
`colorText` context property + `app/qml/components/ColorText.qml`) for
`^0`–`^9`/`^xRRGGBB` markup, independent of `Theme::parseColor`. **Found &
fixed in passing:** `runtime/SimpleGraphic/Fonts/` was never in the `dist/`
install rules at all (pre-existing gap since the `.tgf` atlases were added —
TextMetrics would have shipped broken in a packaged build); added an explicit
install rule as an exception to the "legacy SimpleGraphic not copied" policy.
Verified: build clean, `pob-selftest` 0, `pob-qt --headless` 0, `--capture`
failed=0 (render-identical, no visible regression). Fonts/color-parser not yet
consumed by any real widget — that starts with Part 1.2 Tier 0 (Theme/chrome
kit) and Part 1.3 Tier 1 widgets (Label etc.), which are next in Phase 1.

**Part 1.2a TextMetrics DONE** — `.tgf`-backed
`app/src/TextMetrics.{h,cpp}` reproduces legacy `r_font_c` (verified vs upstream
`r_font.cpp`): real `DrawStringWidth`/`DrawStringCursorIndex` now wired Lua→C++ via
`pob.stringWidth`/`pob.stringCursorIndex` (replacing the 1/0 stubs), also exposed to
QML as the `textMetrics` context property. NEVER use QFontMetrics for measurement.
Selftest gate extended (fonts-loaded + monospace-exact + escape-zero + multiline-max).
Remaining 1.2a: bundle fonts + `QFontDatabase::addApplicationFont` + extend `Theme`
(fontVar/fontVarBold/fontFixed resolver), and the shared `^0`–`^9`/`^xRRGGBB`
color-code rich-text renderer. Fontin DEFERRED → VAR fallback (see open decisions).

**Part 1.1 DONE** — `main.qml` split from 1789
lines into an app shell (~330 lines: window state + top bar + sidebar + StackLayout)
plus 11 view components under `app/qml/views/` (TreeView/SkillsView/ItemsView/CalcsView/
ConfigView/NotesView/ImportView/CompareView/PartyView/PlaceholderView/BuildListPage),
registered via `import "views"` + `qml.qrc`. Per-view state moved off the root Window
into each view; parent drives `visible: root.activeView==="X"`. Top bar + sidebar stay
inline (→ Part 1.4). `app/qml/components/` exists conceptually but is still empty
(widgets land in 1.2–1.3). Verified: build clean, `--capture` failed=0 (render-identical
to Phase 0 baseline), selftest 0, headless 0. **Env gotcha:** unsigned mingw binaries
need Windows **Smart App Control OFF** (else exit 127 / 0xC0E9 crash, no output); pob-qt
writes to OneDrive\Documents so Controlled Folder Access may block it (allow the exe).


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
