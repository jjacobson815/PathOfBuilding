# PoB → Qt Port — STATUS (load this every session)

This is the only file loaded at the start of every session. It names the ACTIVE
phase, the invariants, the open decisions, and what is already true. **Read this,
then read only the ACTIVE phase file** (`phases/PHASE-N-*.md`). Load `reference/*`
only when the active phase tells you to. See `README.md` for the full protocol.

---

## ▶ ACTIVE PHASE

**ACTIVE: Phase 4 — Tree Tab — IN PROGRESS** (see the Phase 4 paragraph
below). Phase 3's MVP is done; its gate stays open only on the long-tail
scope call described next.

**Phase 3 — Build Shell — MVP DONE, gate awaiting scope decision (started 2026-08-18).** Spec:
`phases/PHASE-3-build-shell.md`; that file's "Session log — 2026-08-18" and
"Session log — 2026-08-19" sections have full per-item evidence. The MVP core
is landed and gated: top bar (Back / Save / Save As / build name / points /
Auto-Manual / level / class / ascendancy / secondary ascendancy), the live
stat panel and warnings row over Phase 2's output marshalling, the
version-conversion popup (a HANG FIX — an old build previously left BUILD mode
dead with no way out), a recalc-gated save that actually emits the
denormalized `<PlayerStat>` rows, a truthful unsaved flag, and the Ctrl+1..9 /
Ctrl+S / Ctrl+W hotkeys, and the **main-skill selector stack**
(`pob_getMainSkillControls` + 7 setters + `MainSkillPanel.qml`, parameterised on
legacy's `suffix` so Phase 8 reuses it for the Calcs tab's independent
selection). **Part 3.3 is now fully DONE too:** the savers registry +
Tree-deferred load order + PostLoad, and the `<Build>` attribs / denormalized
`<PlayerStat>/<FullDPSSkill>`/`<TimelessData>`, are all genuinely
round-trip-verified (not just save-side) by new `pob_selftestSaveLoadRoundTrip`
— see invariant #7's caveat below for a real bug this uncovered (auto-level
drift via the still-live legacy Control tree). **Still open in Phase 3:**
Loadouts (needs the Phase 5/6/7 set UIs), the Spectre Library popup, and the
full Save-As folder browser — all explicit long tail; Phase 3's acceptance
gate is otherwise clear to close whenever those are judged in/out of scope.

**Phase 4 — Tree Tab — IN PROGRESS.** Recon findings are at the bottom of
`phases/PHASE-4-tree-tab.md`. **Part 4.1 — ALL 5 items DONE (2026-09-24).**
Embeddable viewer: each `TreeScene` owns a per-instance `TreeViewport`
(zoom/pan) over the shared, data-only `TreeViewController`; `TreeViewer.qml`
takes `focusNodeId`/`focusZoom`/`showCrosshair`/`showFocusRing`/`interactive`
(embed recipes in its header). The compare-spec overlay moved to Part 4.3.
Renderer (commit `7227ad42c`): the tree draws through the C++ `QQuickItem`
`TreeScene` (`app/src/TreeScene.cpp`, hosted by
`app/qml/components/TreeViewer.qml`); the old Canvas-2D path is deleted.
Connectors are the engine's real textured orbit quads (`vert`/`uv` per connector
— the gate counts 1828 arcs + 1233 lines, 0 bad), atlases are shared
`QSGTexture`s (`s_textureCache`). Tree capture vs `skill_tree/legacy.png`:
SSIM 0.53 / hist-corr 0.91 (the pre-TreeScene baseline scored 0.14 / 0.38), so
the tree capture baseline was refreshed. Earlier items (2026-08-19;
evidence: the "Session log — 2026-08-19" section of the phase file): group
backgrounds now resolve for **39/39** tree versions instead of 1 (resolved from shipped sprite
data via the memoised `sheetInfo`; the old `_gbByVersion` table and hand-rolled
`pngSize` reader are both deleted); the renderer
rebuild throttle keys off an engine-sourced `revision` instead of
`allocCount*1000003 + nodeCount`, which was blind to allocation SWAPS and to
search state entirely; WebP decoding works (**439/439** max-zoom sprite sheets
across all 39 versions decode). The real `ImageSize()` + coherent sprite-UV
conversion is now gated (`5537` sampled sprites, `0` out of bounds), and tree
interactions use a C++ spatial hit index with each node's legacy `rsq` radius,
proxy rejection, and bridge-side undo snapshots (the selftest exercises
alloc→undo→redo→dealloc). Next: Parts 4.2–4.5.
Already fixed: `pob_getTreeData` rendered `latestTreeVersion` regardless of the
spec's actual tree version (the spec fallback was dead code).

**Phase 2 — Calc Integration Layer — COMPLETE (2026-07-25 – 2026-08-01)**, with
one post-close bug fix on 2026-08-18 (see the Part 2.4 entry in the Done log:
the compare bridge was grafting the equipped amulet's anoint onto every compared
item and clobbering `itemsTab.displayItem`). Spec:
`phases/PHASE-2-calc-integration.md`. All 6 parts + the acceptance gate are DONE.

Phase 1 (QML Component Library & App Shell) is COMPLETE (2026-07-24) — see the
Done log below for the summary; `phases/PHASE-1-component-library.md` has full
per-item evidence.

**CI confirmation: still DEFERRED (skipped by user 2026-07-23, unrelated to
Phase 1).** Pushed the branch to the personal fork
`github.com/jjacobson815/PathOfBuilding` `dev` (`git push fork
phase-0-foundation:dev`, ff `92bc0df0`→`fa3cc1ea`); all workflows dispatched but
GitHub refused to start any job — *"account is locked due to a billing issue"* on
the `jjacobson815` account. So `test.yml`/`qt-selftest.yml` remain **unverified in
CI** (config is valid; jobs never ran). Re-trigger once the billing lock clears
(Actions page re-run, `workflow_dispatch`, or empty commit). `fork` remote is now
configured locally.

**Env gotcha (still true, applies to every future session):**
`pob-selftest.exe` chdirs to its srcDir arg during init, so the host-file arg
MUST be ABSOLUTE (`<repo>/src <repo>/runtime <repo>/app/lua/pob_host.lua`) — the
relative form fails post-chdir with a silent "Host bootstrap error: cannot open
...". Also: on this dev machine, `qDebug`/`qCritical` output from either binary
is invisible under a plain Git-Bash/PowerShell redirect (no real Win32 console
attached) — set `QT_FORCE_STDERR_LOGGING=1` in the environment to see it; the
**exit code alone is still reliable** without it (confirmed by intentionally
passing bogus paths and observing exit 1 vs 0), which is why the gate has always
been checked by exit code first per invariant #5.

**Env gotcha (NEW 2026-08-19):** the msys2 package
`mingw-w64-x86_64-qt6-imageformats` is a REQUIRED build/runtime dependency —
msys2 ships the webp decoder separately from `qt6-base`. Without it
`QImageReader` returns a null `QImage` for every `.webp`, so the 3_27+/3_28+
ascendancy/bloodline tree art renders **blank with no error logged anywhere**.
`deploy-win-standalone.sh` now hard-fails if `imageformats/qwebp.dll` did not
deploy, so this cannot silently ship again.

**Env gotcha (NEW 2026-08-19, recorded 2026-09-24):** always build as
`PATH="/c/msys64/mingw64/bin:$PATH" ninja` (in `build-win/`). Without that PATH
EVERY compile step reports `FAILED: [code=1]` with ZERO diagnostics —
`cc1plus.exe` cannot resolve its own DLLs and exits 127, which gcc swallows. Not
Smart App Control, not a code error. Running `pob-selftest.exe`/`pob-qt.exe`
needs the same PATH prefix (else exit 127). Several `app/` sources had MIXED
CRLF/LF endings (breaks exact-string edits); `* text=auto` normalises on commit,
so converting a file to LF (`sed -i 's/$//'`) is a content no-op for git.

User-data policy is RESOLVED (SHARE); see resolved decision below +
[[solo-hobby-fork-poc-scope]].

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
7. **There is NO frame loop.** Everything `buildMode:OnFrame` (`Build.lua:1162`)
   recomputed per frame is dead code under Qt — `unsaved` (`:1254`),
   `RefreshSkillSelectControls` (`:1237`), the class/ascend dropdown resync
   (`:1207`), the Ctrl-key hotkey handler (`:1173`). Port each to an explicit
   bridge call or a QML `Shortcut`. **Never reintroduce a frame pump** to "fix"
   one — that re-creates the GUI freeze Phase 0 removed. **Caveat found in
   Phase 3 Part 3.3:** `OnFrame` itself is NOT dead — bridge calls that end in
   `runCallback("OnFrame")` (mode switches, `pob_loadBuildXML`) still run it
   once, and `ProcessControlsInput` (`:1205`) still walks the full legacy
   Control tree every such call even though Qt never draws it. A control
   closure with a side effect (e.g. the point-display control's `width`
   function calling `EstimatePlayerProgress()`, which mutates `characterLevel`
   in auto-level mode — `Build.lua:198,890`) still fires, silently, with no
   rendering symptom to notice it by. Don't assume the Control tree is inert
   just because Qt doesn't draw it; a selftest snapshotting state across an
   `OnFrame`-triggering call should account for this.
9. **Never name a QML component property `data`.** It is QtObject's DEFAULT
   property — the children list — so shadowing it silently swallows every
   declared child. The component still occupies its layout slot and renders
   nothing, with ZERO QML warnings. (Cost real debugging time in
   `MainSkillPanel.qml`.) Related: an EMPTY Lua table crosses the bridge as a
   QVariantMap, not a QVariantList, so `model.length` is `undefined` not `0`;
   guard `int` bindings accordingly. And `parent` is null while a component is
   being constructed inside a Layout.
8. **Measure with TextMetrics; position Qt-painted text with Qt.** The `.tgf`
   atlas is the right source for reproducing legacy *measurements* (column
   widths, ellipsis points). But Qt paints with the bundled TTF, whose extents
   differ slightly, so any `x: anchor - measuredWidth` arithmetic lets glyphs
   overrun the anchor. Give the element a real box and use
   `horizontalAlignment` / Qt's own layout. (Cost a real column collision in the
   Phase 3 stat panel before it was understood.)
10. **`node.sprites[1..4]` are NORMALISED UVs — never read them as pixels.**
   `PassiveTree.lua:288-297` builds them as `coords.x / sheet.width` now that
   `ImageSize()` is real. The bridge de-normalises against the sheet measured
   via `pob.imageSize` (`sheetInfo` in `pob_host.lua`) and takes `sw/sh` from the
   sprite data's integer `width`/`height`. `pob_selftestTreeRender` gates it
   (`spriteBad == 0`, `spriteMinW >= 1`).

---

## ❓ Open decisions (resolve when the relevant phase is reached; then record here)

- **Threading/latency model** (Phase 2) — **RESOLVED 2026-07-25: (a) SYNCHRONOUS
  on the UI thread**, with the existing PowerBuilder coroutine kept as the sole
  frame-sliced exception. Measured via `tools/qt_calc_latency.lua` (new, committed)
  against all 5 `spec/TestBuilds/3.13` builds through the real `pob_host` bridge:
  - **Per-edit recalc** (`buildFlag`→`OnFrame`, the real edit path): min 25-118ms,
    max up to 308ms, scaling with build complexity (cluster-jewel/trigger builds
    costliest). This is the same order of magnitude legacy already pays per
    keystroke (6-10+ synchronous passes) — users already tolerate it; no
    perceptible regression from going Qt.
  - **Hover-compare calls** (`calcFunc` — the "hovering this gives you:" path,
    node/item/flask compares): 2-6.7ms/call across all builds. Cheap enough for
    synchronous UI-thread execution during hover/draw with zero visible lag.
  - **PowerBuilder full sweep (tree heat map) is the one workload that's NOT
    tolerable synchronously**: 4.1s-13.8s wall time (42-131 coroutine resumes).
    MUST stay frame-sliced via its existing coroutine, driven by a Qt timer/idle
    hook (never the tree draw), never run to completion in one call, never
    concurrent with a rebuild.
  - No GlobalCache/heap leak signal over 5 repeated recalcs (heap delta -6.0MB to
    +0.2MB after GC) — current `wipeGlobalCache` cadence looks fine as-is.
  - **Two marshalling hot spots found, logged as Part 2.3 follow-ups (not a
    threading concern, but will silently re-introduce the same latency if called
    unconditionally on every UI refresh):** `pob_getActiveSkills()` costs
    61-470ms (runs ONE BuildOutput PER displayed skill) and `pob_getTreeData()`
    costs ~110ms/call (already flagged in `00-architecture.md` as re-resolving
    sprites every call). Both must be memoized behind `outputRevision` /
    explicit invalidation, never re-fetched on every QML binding update.
  - **Why (a) over (b)/(c) in general:** a dedicated engine thread with
    message-passing adds real engineering cost (Lua state has thread affinity,
    every entry point needs marshalling + cancellation semantics) that the
    measured latencies don't justify — discrete user actions (node click,
    checkbox toggle) at 25-190ms are within normal desktop "click and it
    responds" tolerance, and this is a solo hobby-fork POC
    ([[solo-hobby-fork-poc-scope]]), not a product needing a buttery-smooth
    guarantee. **The mutex/snapshot invariant is satisfied trivially today**:
    only the UI thread ever touches the Lua state, so there's no concurrent
    access to guard against yet. Revisit ONLY if Phase 10's async HTTP work
    puts a second thread anywhere near the Lua state — that seam alone would
    need marshalling back onto the UI thread before any Lua call, not a
    rearchitecture of the whole calc layer.
  - **Follow-up for Part 2.2:** consider a short debounce (~150-200ms) ONLY on
    continuously-editable inputs that would otherwise recalc per keystroke
    (numeric config fields) — discrete actions (clicks/toggles) don't need one.
- **Network strategy** (Phase 10) — real sub-script protocol vs targeted async
  `pob.http` shim of `launch:DownloadPage`.
- **Compare tab** (Phase 13) — in scope? It's fork-specific, session-only, 4986
  lines. Confirm before porting; if dropped, also drop "import as comparison".
- **Trade tooling** (Phase 12) — port now or defer past first shippable release?
  The offline planner (Phases 0–11) is already the core product.
- **Auto-update** (Phase 14) — distribution channel + updater mechanism (installer
  framework / GitHub releases / own server). Determines the replacement for the
  legacy Windows updater.
- **User-data policy** (Phase 1) — **RESOLVED 2026-07-24: SHARE.** Use the legacy
  `Documents/Path of Building` dir (lossless round-trip + zero migration). This is
  already the implemented behavior (`LuaEngine::init` → `QStandardPaths`
  Documents). The SHARE risks (concurrent-run clobber, engine-version-lockstep key
  stripping, port-bug blast radius on the user's only copy) are all
  **out-of-scope for this project**: it's a solo hobby fork / proof-of-concept to
  show upstream, with no shipped audience, no side-by-side production installs, and
  no independent update cadence — every risk requires a second shipped/concurrent
  consumer that doesn't exist here (see [[solo-hobby-fork-poc-scope]] framing).
  Revisit ONLY if upstream adopts the port and it heads toward real distribution —
  at which point SEPARATE-with-migration becomes the likely answer. The temp-dir
  path bug was fixed in Phase 0 regardless. (Part 1.4's cloud-robustness code —
  errorReadingSettings latch, GetCloudProvider, error popups — is still TODO
  independent of this decision.)
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

**▶ Phase 2 — COMPLETE (started 2026-07-25, finished 2026-08-01).** Parts
2.3-2.6 (this session) close out the phase on top of the already-complete
2.1/2.2 (summarized further down):
- **Part 2.3 (output marshalling) DONE.** New `pob_getOutput()`
  (`app/lua/pob_host.lua`) + `LuaEngine::getOutput()` serialize
  `env.player.output`/`env.minion.output` into structured sidebar records,
  driven by iterating `build.displayStats`/`minionDisplayStats`
  (`Modules/BuildDisplayStats.lua`) directly rather than a hand-picked field
  list — ports `buildMode:AddDisplayStatList`'s selection logic
  (Build.lua:1637) to data and reuses `bm:FormatStat` verbatim so values are
  byte-for-byte legacy (thousands separators, `%+` signs, over-cap suffixes
  included free). `:`-keys (`Spec:LifeInc`) and `childStat` nesting
  (`output.MainHand.Accuracy`) fall out for free from the same `statData.stat`/
  `.childStat` read legacy uses. `SkillDPS` (the FullDPS list) folds into the
  same call (`player.skillDPS`), sorted by `dps*count` desc on a COPY of the
  array (not legacy's in-place sort, so a read has no engine side effect).
  `CalcSections`/`powerStatList` were deliberately NOT walked for a second
  field inventory — `CalcSections` already has its own live bridge
  (`pob_getCalcOutput`, pre-existing) and `powerStatList` belongs to Phase 4's
  PowerReport.
- **Part 2.4 BUG FOUND & FIXED (2026-08-18, after the phase was closed).**
  `pob_compareOverride`'s `repItemRaw` path routed through
  `itemsTab:CreateDisplayItemFromRaw` (`ItemsTab.lua:1658`), which is the
  *editor* entry point and was wrong here on two counts: (a) it runs
  `CopyAnointsAndEldritchImplicits` first (`ItemsTab.lua:1661`), so the item
  being compared silently inherited the **equipped amulet's anoint and the
  equipped Eater/Exarch implicits** — the hover diff described an item the user
  never asked about; (b) it ends in `SetDisplayItem` (`ItemsTab.lua:1666`), so a
  mere hover-compare **clobbers `itemsTab.displayItem`** — harmless only because
  no display-item editor exists yet, and silent data loss the moment Phase 6
  builds one. Now builds the candidate directly with `new("Item", raw)`, which
  also (correctly) skips `NormaliseQuality()` on the compare path. Added
  `repItemId` alongside `repItemRaw` so an in-build item can be compared without
  a lossy raw-text round-trip. `pob_selftestCompare` extended with a sentinel
  assertion that `itemsTab.displayItem` survives a raw compare byte-identical —
  **verified to have teeth** by reintroducing the bug and confirming
  `pob-selftest` exits 1 with `compareOverride clobbered itemsTab.displayItem`.
- **Part 2.4 (comparison-calculator bridge) DONE.** New
  `pob_compareOverride(override)`/`pob_compareNodes(nodeIds)` +
  `LuaEngine::compareOverride()`/`compareNodes()` port
  `buildMode:CompareStatList` (Build.lua:1811) to structured diff records,
  reusing calcsTab's persistent `miscCalculator`/`nodeCalculator` closures
  (`CalcsTab.lua:449-450`, refreshed by every real `pob_recalculate()`) rather
  than rebuilding a calculator per hover — reuse is load-bearing for
  performance (a rebuild would cost the same ~25-300ms as a full recalc per
  Part 2.1's spike, defeating the whole point of the calculator pattern).
  Host-safe override vocabulary: node ids (translated to the node-object-keyed
  set the engine wants via `bm.spec.nodes[id]`), raw item text for
  `repSlotName`+`repItemRaw` (parsed via `CreateDisplayItemFromRaw`, never
  added to the build), item ids for `toggleFlask`/`toggleTincture` (resolved
  via `itemsTab.items[id]` — **caught and fixed before shipping:**
  `env.flasks`/`env.tinctures` are keyed by the actual Item object, not an id;
  an earlier draft passed the raw id through, which would have crashed
  `calcs.perform`'s `for item in pairs(env.flasks) do ... item.baseName`
  loop the first time a flask toggle was exercised).
- **Part 2.5 (config usage-set export) DONE.** New `pob_getConfigUsageSets()`
  + `LuaEngine::getConfigUsageSets()` reduce `env.conditionsUsed`/
  `enemyConditionsUsed`/`minionConditionsUsed`/`multipliersUsed`/
  `enemyMultipliersUsed`/`perStatsUsed`/`enemyPerStatsUsed`/`tagTypesUsed`/
  `modsUsed` (`Calcs.lua:493-501`, `varName -> array-of-mod-object-refs`, not
  serializable) to plain `varName -> true` sets; `skillsUsed`/`keystonesAdded`
  are already boolean sets and pass through unchanged (so `keystonesAdded` is
  byte-identical to what `ConfigVisibility.lua` already reads directly —
  correct by construction for Phase 7's config-visibility predicates).
- **Part 2.6 (party/buffExports seam audit) DONE, no stub needed.**
  `PartyTabClass` (unmodified `src/Classes/PartyTab.lua`, instantiated at
  `Build.lua:615` the same way as skillsTab/configTab/itemsTab) already
  constructs a real `enemyModList`/`enableExportBuffs`, and both the read seam
  (`CalcSetup.lua:565`) and write-back seam (`setBuffExports`,
  `CalcPerform.lua:3640`) were already live under the Qt host — new
  `pob_selftestParty` proves both end-to-end (adds a real enemy mod, forces
  `enableExportBuffs=true`, recalculates, restores original state).
- **Acceptance gate CLOSED**, one item scoped down: the `busted`/Docker
  numeric calc-parity re-verification was **not** run this session (Docker
  Desktop's daemon wasn't running locally) since Parts 2.3-2.6 are all
  read-only marshalling additions that call existing unmodified engine entry
  points — no new numeric-drift surface vs. what Part 2.1's spike already
  covered. Revisit if a future session touches the `calcs.*` entry points
  themselves. All other gate items verified live (see
  `phases/PHASE-2-calc-integration.md` for full per-item evidence). New
  selftests (`pob_selftestOutput`/`pob_selftestCompare`/
  `pob_selftestConfigUsage`/`pob_selftestParty`) wired into
  `selftest_checks.h`; `pob-selftest` exit 0 and `pob-qt --headless` exit 0,
  both including all 4 new checks; full rebuild via `ninja -C build-win` clean
  with no warnings.

**Part 2.2 (recalc orchestration service)
COMPLETE (2026-08-01).** One canonical host-callable recalc path now exists:
`pob_recalculate()` (new, `app/lua/pob_host.lua`) runs the legacy
`wipeGlobalCache → outputRevision++ → BuildOutput → RefreshStatList` sequence,
gated on `build.buildFlag` (idempotent no-op when clean); `pob_getOutputRevision()`
reads the counter without forcing a recalc; both surfaced to C++/QML as
`LuaEngine::recalculate()`/`outputRevision()` (`recalculate()` emits
`calcsChanged()` only on an actual recalc). `pob_getCalcOutput()` now returns
`outputRevision` inline too. **Every existing mutation seam migrated** off the
old per-call-site `bm.buildFlag = true; pcall(runCallback, "OnFrame")` (a full
app-frame re-run, not just a recalc) onto `pob_recalculate()`:
`allocNode`/`deallocNode`, `setActiveSkill`, `setConfigOption`,
`addSocketGroupWithGem`. Real mode-transition sites (open/create/load build,
import, LIST↔BUILD) intentionally kept on full `OnFrame` — out of scope, they
need real mode init. **Bug found & fixed in passing:** `pob_addItemFromRaw`/
`pob_deleteItem` dirtied `buildFlag` only indirectly (via the engine's own
`ItemsTab` methods) and never consumed it, so `pob_getCalcOutput`'s lazy
rebuild-if-`mainOutput`-nil check silently never fired after the first calc —
calc output went **stale after every item add/delete** until an unrelated
mutator happened to trigger a real recalc. Both now call `pob_recalculate()`.
Debounce (the Part 2.2 follow-up) is **deferred, not built**: no
continuously-editable QML input exists yet to fire rapid recalcs (Config tab UI
is Phase 7), and the buildFlag gate already makes redundant `recalculate()`
calls free — revisit when Phase 7 lands a live numeric field. New
`pob_selftestRecalc` (wired into `selftest_checks.h`) verified: `pob-selftest`
exit 0 (`recalc ok = true r0 = 4 r1 = 5`), `pob-qt --headless` exit 0, both
binaries build clean. Full detail: `phases/PHASE-2-calc-integration.md` Part 2.2.

**Part 2.1 (threading/latency spike)
COMPLETE.** `tools/qt_calc_latency.lua` (new, committed — reusable regression
tool, not one-shot) measures every calc-engine entry point the Qt host drives
(recalc, calculators, hover-compares, PowerBuilder sweep, marshalling, memory)
against all 5 `spec/TestBuilds/3.13` builds through the real `pob_host` bridge.
Ran clean (`pob-selftest` exit 0, all 5 builds loaded+measured). **Decision:
synchronous Lua calc on the UI thread**, PowerBuilder kept frame-sliced via its
existing coroutine as the sole exception — full numbers + rationale in the
"Threading/latency model" open-decision entry above (now resolved). Two
marshalling hot spots found in passing (`pob_getActiveSkills` 1-BuildOutput-
per-skill, `pob_getTreeData` re-resolves sprites every call) — logged as Part
2.3 follow-ups, not fixed here (out of scope for the spike).

**▶ Phase 1 — COMPLETE (started 2026-07-23, finished 2026-07-24).** Parts 1.1,
1.2a, 1.2, 1.3 (summarized further down) plus **Part 1.4 (application shell)**
and the **acceptance gate**, closed in the wrap-up session:
- **Part 1.4 bullets 1-4** (mode manager, Settings round-trip, cloud
  robustness, Options dialog) were already code-complete from the prior
  Part 1.4 workflow; this session's Step 0 built the tree fresh (first build
  since Stage 2) and ran the full gate cold — **it passed clean on the first
  try**, including all three previously-unrun selftests
  (`pob_selftestCloudRobustness`/`SettingsRoundTrip`/`Options`) and
  `OptionsDialog.qml` loading with zero QML warnings despite being
  instantiated unconditionally in `main.qml`. Options dialog end-to-end
  verification (bullet 4) completed once bullet 6 supplied a real entry point
  — see below.
- **Part 1.4 bullet 5 (Toast)** — DONE. `pob_host.lua` wraps
  `ToastNotification`'s Add/Update/Remove/Clear at host-bootstrap time (mirror
  list + `pob.toastsChanged()` push, same pattern as `cloudErrorPopup`) →
  `LuaEngine::toastsChanged()` → `getToasts()`/`dismissToast()`; new
  `Toast.qml`/`ToastStack.qml`. **Gotcha (caught by a real test failure, not
  silently):** the wrap must install AFTER `runCallback("OnInit")` —
  `dofile(Launch.lua)` only *defines* `launch:OnInit`, it doesn't run it, so
  `ToastNotification`/`main` don't exist as globals yet at that point.
- **Part 1.4 bullet 6 (Bottom bar + About + F1)** — DONE. `BottomBar.qml` +
  `AboutPopup.qml` (new `pob_getAboutContent()` Lua global re-parses
  changelog.txt/help.txt verbatim per legacy's algorithm) + an F1 `Shortcut`
  in `main.qml`. **Bug found & fixed in passing:** `Button.qml`/`Dragger.qml`/
  `CheckBox.qml`'s disabled-content color (`theme.background`, per Part 1.3's
  original rule) is nearly invisible against the disabled Chrome fill
  (`theme.disabled`) — both are near-identical dark navies (`#0F172A` vs
  `#141822`), not the "medium-grey" Part 1.3 assumed. Fixed by switching to
  `theme.muted` (`#94A3B8`, documented in `Theme.cpp` as "readable on
  #0F172A") across all three widgets — found via a real BottomBar screenshot,
  not by inspection, which is the concrete reason to keep doing visual
  captures even for "should be fine" widget reuse.
- **Acceptance gate — CLOSED.** Tier 0-2 widget kit adopted in
  `views/BuildListPage.qml` + `views/ImportView.qml` (the 2 required non-
  main.qml/OptionsDialog.qml consumers); colour-code + VAR/FIXED-font evidence
  captured (About popup changelog + ImportView's now-monospace share-code
  field). **TextMetrics golden-parity vs legacy is the one item explicitly
  DEFERRED, not faked**: `runtime/Path of Building.exe` is a real, launchable
  PE32+ GUI binary, but SimpleGraphic is closed-source with no discoverable
  headless/CLI mode (`DrawStringWidth` needs a live D3D/OpenGL `RenderInit`),
  so there's no way to script a value dump without reverse-engineering its
  undocumented embedding contract — judged disproportionate to this item.
  Full rationale + what was tried: `phases/PHASE-1-component-library.md`
  Acceptance gate section. Revisit whenever `EditControl`'s caret makes a
  live legacy-vs-Qt comparison worth setting up properly.
- **All 10 `app/tests/capture-baseline/` PNGs were re-baselined** in this
  commit — the prior baseline predated essentially all of Phase 1 (fonts,
  the widget kit, the app shell), so every view had already diverged from it
  by the time this session started; each was reviewed by eye before
  re-baselining and every difference traced to intended Phase 1 work.
- **Observed, not caused by this work (flagged for a follow-up task, not
  fixed):** `views/CalcsView.qml`'s stat rows visibly overlap in
  `--capture` screenshots, and `views/ConfigView.qml` shows raw `^xRRGGBB`
  escape codes as literal label text instead of parsed color — both
  pre-existing (neither file was touched this session), both cosmetic-only,
  both in scope for their respective later phases (Calcs = Phase 8,
  Config = Phase 7).
- Full per-item evidence for every Part 1.4 bullet and acceptance-gate line:
  `phases/PHASE-1-component-library.md`.

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
