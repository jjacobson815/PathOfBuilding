# Phase 1 — QML Component Library & App Shell

**Status:** NOT STARTED
**Goal:** Build the reusable QML component kit that every view composes, split the
monolithic `main.qml` into modules, and finish the application shell (mode manager,
settings, popups, toasts, Options dialog, About/help). After this phase the app has
a real UI foundation instead of one 104 KB file.
**Depends on:** Phase 0.
**References to load:** [[control-library]] (primary), [[text-rendering]] (Part
1.2a — the text subsystem), [[00-architecture]], [[core-lifecycle]] (for the shell
+ Options settings + userPath/cloud), [[tabs-catalog]] (Options popup + shell
inventory).

## Why this phase

The port strategy is QML-native views. Those views can't be built consistently
until the shared widgets exist. Everything from Phase 3 on composes these. Build
the infra tier (Tier 0) first — it gates all text-bearing components.

## Part 1.1 — Split main.qml into modules

- [x] Extract each view into its own `.qml` under `app/qml/views/`, shared widgets
  under `app/qml/components/`, and register a QML module / update `qml.qrc`. Do this
  **after** Phase 0's nesting fixes so behavior is verifiable before/after via
  capture diff. (M-L)
  — **DONE (2026-07-23).** `main.qml` 1789→~330 lines (shell: window state + top bar
  + sidebar + StackLayout). 11 view bodies extracted to `app/qml/views/`: TreeView,
  SkillsView, ItemsView, CalcsView, ConfigView, NotesView, ImportView, CompareView,
  PartyView, PlaceholderView, BuildListPage. Each view's private state moved off the
  root (selectedItem+rarityColor→ItemsView, fileUrl→TreeView, saveLoadStatus+viewLabel
  →PlaceholderView, list*+openSelected→BuildListPage). Parent drives each view's
  `visible: root.activeView==="X"`. Registered via `import "views"` + `qml.qrc` entries
  (AUTORCC). `components/` intentionally still empty — shared widgets get built in
  1.2–1.3. Verified: build clean, capture failed=0 (TREE/SKILLS/ITEMS spot-checked
  render-identical), selftest 0, headless 0. Top bar + sidebar kept inline (→ Part 1.4).

## Part 1.2a — Text-rendering subsystem (build FIRST — gates all text)

Full spec in [[text-rendering]]. This was missed in the first plan pass and is the
most pervasive concern. The bitmap font atlases already ship in
`runtime/SimpleGraphic/Fonts/`.

- [x] **Bundle + register fonts.** — **DONE (2026-07-24).** Fetched official
  upstream TTFs (Liberation Sans Regular/Bold from `liberationfonts/liberation-
  fonts` 2.1.5, OFL; Bitstream Vera Sans Mono from `download.gnome.org` 1.10,
  permissive) into `runtime/SimpleGraphic/Fonts/` alongside the existing `.tgf`/
  `.tga` atlases (+ `LICENSE-*.txt`). `QFontDatabase::addApplicationFont()` in
  `main.cpp` (non-headless path, before `QQmlApplicationEngine` load). Added a
  `dist/runtime/SimpleGraphic/Fonts` install rule (`app/CMakeLists.txt`) — this
  dir was previously never installed at all (pre-existing gap predating this
  phase; the `.tgf` atlases weren't shipping to `dist` either). Fontin TTFs NOT
  fetched — licensing still DEFERRED (open decision below); Theme::fontFor()
  stubs FONTIN* → the VAR face.
- [x] **Extend `Theme`** — **DONE (2026-07-24).** Added `fontVar`/`fontVarBold`/
  `fontFixed` Q_PROPERTYs (`"Liberation Sans"` ×2 + `"Bitstream Vera Sans Mono"`;
  VAR/VAR BOLD share one family, paired with `font.bold` — that's how the
  Liberation TTFs actually embed their family name) and a
  `Q_INVOKABLE QVariantMap fontFor(legacyName)` resolver keyed by the 7
  `fontMap` strings, returning `{family, bold, italic}`. Replaces the old
  hardcoded `m_fontFamily="sans-serif"` default (now `m_fontVar`); UITheme
  `typography.fontFamily` can still override. Not yet wired into any view
  widgets (no Tier 1 widgets exist yet — Part 1.3).
- [x] **`TextMetrics` engine** — a C++ class that loads `runtime/SimpleGraphic/
  Fonts/*.tgf` and reproduces `r_font_c` EXACTLY (per-glyph `ceil`, `width+spLeft+
  spRight`, atlas selection + scale, tab=4×space, tofu for ≥128, inline escape
  skip). **Do NOT use `QFontMetrics`** — it drifts and breaks caret/ellipsis/auto-
  width. Expose to Lua (real `DrawStringWidth`/`DrawStringCursorIndex`, replacing
  the `pob_host.lua:78-83` stubs) AND to QML (`Q_INVOKABLE width`/`cursorIndex`).
  Add golden parity tests vs legacy for a mixed corpus. (L)
  — **DONE (2026-07-23).** `app/src/TextMetrics.{h,cpp}` (QObject). Algorithm
  verified against upstream `r_font.cpp` (FindFontHeight/fontHeightMap →
  nearest-baked + scale=h/baked; per-glyph `width+spLeft+spRight`; `ceil` after each
  char; `^`d/`^x`+6hex escapes skip 2/8 chars zero-width; tab=space×4; codepoint
  ≥128 → `[U+XXXX]` tofu at a ≥3px-smaller baked height; multi-line → max). Font
  name→`.tgf` map (VAR→Liberation Sans, VAR BOLD→…Bold, FIXED→Bitstream Vera Sans
  Mono, FONTIN*→Fontin family; nil→FIXED). Wired Lua→C++ via new `pob.stringWidth`/
  `pob.stringCursorIndex` bridge fns (`LuaEngine`), replacing the `pob_host.lua`
  stubs; exposed to QML as the `textMetrics` context property (`main.cpp`). Selftest
  asserts fonts actually loaded + monospace-exact + escape-zero + multiline-max +
  empty-zero (exit 0). Probed values sane (FIXED A=8/AAAA=32, VAR A=9, VAR BOLD
  Life=26, FONTIN SC "Kaom's Heart"=86; cursor 0..5 across "Hello"). **Still TODO
  in 1.2a:** golden parity vs *legacy actual* values (needs legacy SimpleGraphic run
  — deferred); cursor hit-test uses a midpoint approximation for non-tab chars
  (refine when EditControl lands). See remaining 1.2a items (fonts+Theme, color parser).
- [x] **Color-code rich-text renderer** — **DONE (2026-07-24).** New
  `app/src/ColorText.{h,cpp}` (QObject): `parse(text, defaultColor)` → ordered
  `{color, text}` runs (`^0`–`^9` exact palette incl. `fromRgbF` for ^8/^9,
  `^xRRGGBB`/`^XRRGGBB`, literal `^` for anything else incl. trailing `^`, no
  `^^` escape, carry-forward default), `toStyledText(...)` → HTML-escaped
  `Text.StyledText`-ready markup, `stripColorCodes(...)`. Exposed to QML as the
  `colorText` context property (`main.cpp`). New Tier-0 widget
  `app/qml/components/ColorText.qml` (registered in `qml.qrc`) wraps a
  `Text{textFormat: Text.StyledText}` bound to `colorText.toStyledText(...)`.
  Independent of `Theme::parseColor` (not reused, per spec) and of
  `TextMetrics`/font state (own escape-length logic, verified against a
  standalone compiled test: `^1Red^7 normal ^xFF8800orange^0 black^` → 4 runs
  incl. correct literal-trailing-`^` handling). Not yet consumed by a real
  view (no item/gem/tree text sites ported yet — later phases).

## Part 1.2 — Tier 0 infrastructure (build in this order)
- [x] **Theme/chrome kit** — **DONE (2026-07-24).** New
  `app/qml/components/Chrome.qml` (border+fill Rectangle; `pressed`/`hovered`/
  `locked`/`controlEnabled` state props, using the EXISTING `theme.border`/
  `borderStrong`/`hover`/`active`/`disabled`/`radiusControl` tokens — deliberately
  NOT literal legacy SimpleGraphic greyscale bevels, since the app shell
  (sidebar/topbar) already committed to the flat "Cyber Citrus" design system;
  see the token list in `Theme.h`). `Arrow.qml` (Canvas triangle, 4 directions,
  geometry mirrors legacy `main:DrawArrow`) and `CheckMark.qml` (Canvas
  checkmark, geometry mirrors legacy `main:DrawCheckMark`) — both verified
  pixel-correct via a temporary debug overlay in `main.qml` (all 4 Chrome
  states + 4 Arrow directions + CheckMark screenshotted via `--capture`, then
  removed). Registered in `qml.qrc`. Not yet consumed by a real widget (Tier 1
  Button/CheckBox/Slider land in Part 1.3 and will compose these).
- [x] **Tooltip framework (core)** — **DONE (2026-07-24), partial scope.** New
  `app/qml/components/Tooltip.qml`, ported from `src/Classes/Tooltip.lua`
  (643 lines): programmatic `clear()`/`addLine(size,text,font)`/
  `addSeparator(size)`; `checkForUpdate(params)` (the `CheckForUpdate` param-
  memoization equivalent — array-diff instead of Lua varargs); word-wrap
  ported from `main:WrapString` (greedy break-at-last-space, measured via
  `textMetrics.width`, "VAR" font); `getSize()`; `showAt(x,y,w,h,viewport)`
  hover placement ported from `Tooltip:Draw`'s `isHoverToolTip` branch
  (right-of-hover by default, flips left/up on overflow, clamped to
  viewport). Renders via `ColorText` lines (so `^`-codes work) + a border/fill
  Rectangle. Verified via a temporary debug harness in `main.qml`: colored
  stat line, separator, word-wrapped body text, AND the edge-flip case (hover
  near the right edge correctly repositions left) — screenshotted via
  `--capture`, then removed.
  **Deliberately DEFERRED to when a real content view needs them** (no item/
  gem/tree tooltip call site exists yet to validate exact asset paths/pixel
  offsets against): multi-column overflow (`CalculateColumns`'s column-break
  logic), the 13-config rarity header art + influence icons + RELIC foil
  tints, the oil/recipe row (`SetRecipe`), child tooltips (item-granted-skill
  sub-tooltips). The programmatic API (clear/addLine/addSeparator/
  checkForUpdate/showAt) is stable — a future pass extends the component in
  place without call-site changes. Hover tooltips running live calc compares
  is Phase 2 (calc bridge) — out of scope here regardless.
- [x] **Modal popup framework** — **DONE (2026-07-24).** Built on
  `QtQuick.Controls.Dialog` rather than hand-rolled dim/centering/stacking —
  `app/qml/components/PopupBase.qml` (the generic `openPopup`-equivalent
  shell: themed background, title-plate header mirroring `PopupDialog:Draw`'s
  title box, `Overlay.modal` dim rect, RETURN→`accept()`/ESCAPE→`reject()`
  wiring, `Dialog`'s built-in stack/z-order via the window `Overlay` gives
  the popup **stack** for free). `PopupButton.qml` — minimal Chrome-based
  button (label + click only) so the canned dialogs don't hand-roll
  Chrome+MouseArea+Text each; explicitly NOT the future Tier 1 ButtonControl.
  Four canned dialogs, each porting the matching `Modules/Main.lua` function:
  `MessagePopup.qml` (`OpenMessagePopup`), `ConfirmPopup.qml`
  (`OpenConfirmPopup`, 2- or 3-button via `extraLabel`), `TextInputPopup.qml`
  (generic prompt+field, plain `TextInput` — the real EditControl is Tier 3,
  not built yet), `NewFolderPopup.qml` (`OpenNewFolderPopup`, adds the
  illegal-filename-char guard on the confirm action; the actual `MakeDir`
  call stays the caller's job, matching legacy). Verified via a temporary
  debug harness (a 3-button `ConfirmPopup` stacked over a `MessagePopup`):
  dim overlay, centering, title plate, colored (`^`-code) message text, and
  stacking (`Message` visible dimmed behind `Confirm`) all confirmed via
  `--capture`, then removed.
  **Documented deviation:** legacy's popup stack draws ONLY the topmost
  popup (covered ones are entirely un-drawn); `Dialog`-based stacking here
  leaves lower popups visible-but-dimmed underneath instead of hidden
  outright — functionally equivalent (only the topmost is interactive), not
  pixel-identical, acceptable since 2+ simultaneously-open popups is a rare,
  brief state.
- [x] **Drag-and-drop framework (core)** — **DONE (2026-07-24), partial
  scope.** `app/qml/components/DragSource.qml` + `DropTarget.qml`, built on
  Qt Quick's own `Drag`/`DropArea` (legacy has no OS-level drag either — this
  is the equivalent in-process mechanism) rather than hand-rolled hit-
  testing. `DragSource`: wraps arbitrary content, 10px move threshold
  (`drag.threshold: 10`, matches legacy's `dist² > 100`), typed payload via
  `dragType`/`dragValue` properties readable off `Drag.source` by the target,
  snaps back to its origin position on release. `DropTarget`: wraps content +
  a `DropArea`; `canReceiveDrag(type,value)`/`receiveDrag(type,value,source)`
  are caller-supplied JS function properties (mirrors the legacy control
  methods exactly); `highlighted` (bind to `containsDrag`) mirrors the
  legacy green target tint. Verified via a temporary debug harness — two
  `DropTarget`s + one `DragSource` render correctly at rest, no QML errors —
  screenshotted via `--capture`, then removed.
  **Verification caveat:** the `--capture` harness only switches views and
  screenshots; it cannot synthesize a mouse-drag gesture, so only REST-STATE
  rendering was visually confirmed. The drag/drop interaction itself relies
  on Qt Quick's own well-established `Drag`/`DropArea` mechanics (not custom
  hit-testing code), reviewed but not live-exercised.
  **Deliberately DEFERRED** (no ListControl/ItemSlotControl exists yet to
  integrate against): the reorder insertion-caret (legacy `selDragIndex`, a
  row-index computed from cursor Y inside a specific list — list-layout-
  specific, belongs with the Tier 3 ListControl) and the cursor-following
  TEXT label (`main.showDragText` — superseded here: since the source item
  itself visually follows the cursor via `drag.target`, that IS the ghost;
  a separate text label is redundant for the common case, revisit if a
  future consumer needs the plain-text variant specifically). Also noted in-
  file: dragging the SOURCE item itself (not a reparented proxy) fights a
  Row/Column/Layout parent's own positioning — fine for anchor/x-y positioned
  items (slots, tree nodes), but a future Layout-based ListControl row should
  reparent to an overlay instead of using this as-is.
- [x] **UndoHandler equivalent** — **DONE (2026-07-24).**
  `app/qml/components/UndoHandler.qml` — a faithful line-by-line port of
  `src/Classes/UndoHandler.lua`'s ring-buffer algorithm (101-state cap,
  redo-clear-on-new-edit, the exact undo()/redo() pop/restore/re-snapshot
  sequence), verified by hand-tracing the Lua against the JS before writing
  it. Consumers supply `createState`/`restoreState` JS function properties
  (the `CreateUndoState`/`RestoreUndoState` contract methods); `modFlag`
  mirrors the dirty flag. Verified via a temporary debug harness: a 7-
  assertion sequence (2 adds → 2 undos → boundary check → 2 redos →
  boundary check) rendered as colored PASS/FAIL text and screenshotted via
  `--capture` — all 7 passed — then removed.
- [x] **Input/focus model** — **DONE (2026-07-24), decision + minimal
  primitive.** Legacy's `ControlHost.lua` input router (capture-by-return
  `selControl`, mouse-buttons-as-keys, manual `OnHoverKeyUp` dispatch) is
  being replaced by Qt's native event/focus model, not reproduced 1:1:
  - **TAB-order groups** → Qt's native `activeFocusOnTab` +
    `KeyNavigation.tab`/`backtab` (or FocusScope's default chain). No custom
    component needed; each Tier 1+ widget wires this itself when built
    (Part 1.3+).
  - **RETURN/ESC in dialogs** → already implemented per-dialog in
    `PopupBase.qml` (`Keys.onReturnPressed`→`accept()`,
    `closePolicy: Popup.CloseOnEscape`→`reject()`) — done as part of the
    modal popup framework above, not duplicated here.
  - **Wheel-on-hover** → needs NO special code. Legacy special-cased this
    because its immediate-mode router defaulted most events to the focused
    `selControl`; Qt/QML wheel events already route by cursor position
    (`MouseArea`/`WheelHandler`), independent of focus, by default. This is
    a straight win, not a gap.
  - **`OnHoverKeyUp` (wiki hotkey on hovered row)** → new
    `app/qml/components/HoverKeyArea.qml`, wrapping a `HoverHandler` +
    exposing `hovered` (readonly) and an `onHoverKeyUp` JS-function property.
    Verified via a temporary debug harness: instantiates and renders
    correctly (idle state; hover interaction itself can't be exercised by
    the static `--capture` harness, same caveat as DragSource/DropTarget).
    **Deliberately deferred:** the actual window-level "route this keypress
    to whatever's hovered, focus be damned" dispatcher — needs a real
    multi-instance consumer (Phase 5/6: SkillListControl/ItemSlotControl) to
    validate the registry shape against; building it blind risks guessing
    wrong.
  - **Intentionally dropped:** legacy's capture-by-return focus model itself
    (a handler returns "the control to select") and mouse-buttons-as-keys
    (`LEFTBUTTON`/`WHEELUP` as `event.key` strings) — both are artifacts of
    SimpleGraphic's polled immediate-mode input loop with no Qt equivalent
    needed; Qt's signal-based MouseArea/focus system supersedes them
    entirely, not a like-for-like port.

## Part 1.3 — Tier 1 + Tier 2 widgets

- [x] Tier 1 (S each): Label (color-code), Section (group box), RectangleOutline,
  **Button** (label/image/+,-,x glyphs, locked/hover/pressed, onHover, tooltip),
  **CheckBox** (left label in hit area, borderFunc, state-aware tooltip), Dragger,
  **Slider** (SHIFT/CTRL wheel speeds, detents, cursor-value tooltip, invert option).
  — **DONE (2026-07-24).** All 7 built in `app/qml/components/`, each a faithful
  port of its `src/Classes/*.lua` counterpart over the Tier 0 kit (Chrome/Arrow/
  CheckMark/ColorText/Tooltip/UndoHandler). Verified via a temporary debug harness
  in `main.qml` (every widget + state — locked/disabled/checked/detent/etc. —
  screenshotted via `--capture`, then removed) + full gate (`pob-selftest` 0,
  `pob-qt --headless` 0, `--capture` failed=0, no regression vs the Phase 0
  baseline). **Bugs found & fixed during verification:** (1) `Text`-derived items'
  `implicitWidth`/`implicitHeight` are READ-ONLY in Qt Quick (computed from content
  via Qt's own font metrics) — `Label.qml` was assigning them directly, which threw
  "Invalid property assignment" and silently failed the whole QML load; fixed by
  assigning the real (assignable) `width`/`height` instead, driven by
  `textMetrics.width()` (never `QFontMetrics`, per invariant). Any consumer reading
  a `Label`'s size must use `.width`/`.height`, not `.implicitWidth/Height` (fixed
  one such site in `Section.qml`). (2) `controlEnabled: false` foreground content
  (button/checkbox label text, checkbox checkmark glyph) was invisible — it used
  the SAME `theme.disabled` token as Chrome's own disabled FILL color, so text and
  background painted identically. Fixed with two distinct contrast pairings:
  content drawn ON TOP of the disabled Chrome fill (Button/Dragger labels+glyphs,
  CheckBox's CheckMark) uses `theme.background` (dark navy, contrasts against the
  medium-grey `theme.disabled` fill); a CheckBox's LABEL sits OUTSIDE the box, on
  the ordinary page background, so it uses `theme.muted` instead (contrasts against
  the dark navy, would have been invisible using `theme.background` there). Any
  future Tier 1+ widget with a disabled state must pick per this same rule — don't
  reuse `theme.disabled` for foreground content. **Added in passing:** `main.cpp`
  now mirrors `QQmlApplicationEngine::warnings` into the existing `mainLog` file
  (GUI-subsystem binary — QML compile errors otherwise vanish into
  `OutputDebugString` with zero observable diagnostic, which is exactly how bug
  (1) above was invisible until this was added). **Naming collision noted for
  future phases:** our `components/Button.qml` shares its name with
  `QtQuick.Controls.Button` (already used unqualified in `main.qml`'s top bar) —
  a bare `import "components"` in any file that also does
  `import QtQuick.Controls` unqualified will be an AMBIGUOUS TYPE error. Views
  adopting the component library's `Button` must either qualify the import
  (`import "components" as Widgets` → `Widgets.Button`) or stop importing
  `QtQuick.Controls`'s unqualified `Button`. Relevant starting Phase 3 (Build
  Shell) and Part 1.4 (top bar rework).
- [x] Tier 2: ScrollBar behaviors (or ScrollView policy shim: hold-to-repeat accel,
  page-jump, ScrollIntoView, autoHide, wheel-key mapping), PathControl breadcrumb,
  TextListControl (multi-column rich-text scroll + SHIFT-wheel section jumps),
  ResizableEditControl, SearchHost (type-to-filter + highlight ranges).
  — **DONE (2026-07-24), ResizableEditControl DEFERRED.** Built `ScrollBar.qml`
  (bespoke faithful port, not a QML ScrollView policy shim — hold-to-repeat is the
  exact legacy timing: 500ms initial delay then a 50ms-interval repeat via two
  `Timer`s; `offsetMax` is a REACTIVE computed property, not imperatively set like
  legacy's `SetContentDimension`, so a consumer can just bind `contentDim`/
  `viewDim` declaratively — `setContentDimension()` still exists as an imperative
  convenience wrapper), `PathControl.qml` (breadcrumb of `Button`s + `Arrow`
  separators, `UndoHandler`-backed subpath history; drag-drop-onto-a-segment
  highlight DEFERRED — no real consumer (`BuildListControl`/`FolderListControl`
  are Tier 4) to validate the drag-payload shape against yet), `TextListControl.qml`
  (multi-column color-coded scroll block over `ScrollBar`, `sectionHeights`
  SHIFT+wheel jump; documented simplification: column `align` affects
  text-box-relative alignment only, not legacy's anchor-POINT semantics for
  RIGHT_X/CENTER_X — revisit if a real consumer needs pixel-exact anchoring),
  `SearchHost.qml` (non-visual `QtObject`; word-order caseless substring match +
  highlight ranges, verified against a hand-traced example in the debug harness —
  `["Kaom's Heart","Kaom's Roots","Tabula Rasa","Karui Ward"]` searched for
  `"ka h"` correctly matched only "Kaom's Heart", matchCount=1). **
  ResizableEditControl deferred**, consistent with the Tier 3 deferral below: it
  legacy-subclasses `EditControl` (751 lines, Tier 3, not built), so
  "ResizableEditControl" can't be built as a small increment here — it needs
  `EditControl` first, at whichever point (here vs. Phase 3) that gets built.
  Verified via a temporary debug harness (all 4 widgets + `SearchHost` reflected
  into a `ColorText` line, screenshotted via `--capture`, then removed) + full gate,
  same as Tier 1. **Observed, not caused by this work:** a capture-vs-baseline diff
  pass showed the top-bar BUILD/LIST button ORDER differs run-to-run — `luaEngine.
  modeNames()` iterates a Lua table without a guaranteed stable order. Cosmetic
  today (single-mode-bar labels), but Part 1.4's mode manager should sort
  `modeNames()` or otherwise pin an explicit order before relying on positional
  UI (e.g. "the active mode button is always first").

Defer the Tier 3 deep widgets (EditControl, DropDownControl, ListControl base,
GemSelectControl, ItemSlotControl, CalcSection/Breakdown) to the phases that first
need them, but keep them on the [[control-library]] backlog so they're built once.
(EditControl and DropDownControl are needed early — build them here or at first use
in Phase 3.)

## Part 1.4 — Application shell

- [x] Mode manager (LIST/BUILD) driven from QML, honoring the OnFrame-deferred
  `SetMode` swap and `GetArgs` persistence (reopen last build). (S — bridge exists;
  verify lifecycle.) **Verified 2026-07-24**: `LuaEngine::setMode("BUILD")` now
  calls `pob_setBuildMode` (app/lua/pob_host.lua), which reads
  `main.modes.BUILD:GetArgs()` and reopens the last dbFileName/buildName,
  falling back to "Unnamed build" only when GetArgs yields no buildName (genuine
  first run). `modeNames()` (app/src/LuaEngine.cpp) now `stable_sort`s to a fixed
  {LIST, BUILD} order (matches `Modules/Main.lua`'s own LIST-then-BUILD mode
  registration at lines 59-60) so the top-bar button order is deterministic
  run-to-run. The OnFrame-deferred swap is preserved (`setMode` still pumps one
  `runCallback("OnFrame")` synchronously, no polling Timer added). Gate: `pob-
  selftest` 0 (incl. permanent `pob_selftestReopenLastBuild` check — saves a
  named probe build, detours to LIST, re-enters BUILD via `pob_setBuildMode`,
  asserts same name+file reloaded from disk), `pob-qt --headless` 0, `--capture`
  failed=0 across all 10 views, pixel-identical to `app/tests/capture-baseline/`
  (spot-checked tree.png). A temporary `--modeharness` flag was added to
  `main.qml` to visually confirm via `--capture` screenshot that
  LIST→BUILD→LIST→BUILD retains a distinctive build name instead of reverting to
  "Unnamed build", then removed (net-zero diff, confirmed by grep).
- [x] Settings.xml round-trip complete (Mode/Args, Accounts, SharedItems, Misc) —
  confirm `OnExit` (wired in Phase 0) saves; userPath now = Documents/"Path of
  Building" (Phase 0). (M) — **Verified 2026-07-24** via full gate re-run (Step 0
  of the wrap-up plan): `pob_selftestSettingsRoundTrip` passes as part of
  `pob-selftest` exit 0. Full manual GUI quit/relaunch pass folded into the final
  end-to-end wrap-up verification (see Part 1.4 closing note below) rather than
  duplicated here.
- [x] **User-data policy + cloud robustness** (see [[core-lifecycle]]): ratify SHARE
  vs SEPARATE (recommend SHARE — record in STATUS + document the engine-version-
  lockstep requirement; if SEPARATE, add a first-run copy-migration of `Builds/` +
  `Settings.xml`). Make the `errorReadingSettings` latch **non-fatal** (retry-after-
  hydrate / don't latch on first failure) so a transient OneDrive dehydrated read
  doesn't silently kill settings persistence for the session. Implement a real Qt
  `GetCloudProvider` (replace the `pob_host.lua:182` stub) and wire
  `OpenCloudErrorPopup`/`OpenPathPopup` to real QML dialogs (they build
  SimpleGraphic labels today → no-op in QML). (M) — **Verified 2026-07-24**:
  User-data policy RESOLVED SHARE (recorded in STATUS.md, see
  [[solo-hobby-fork-poc-scope]]). `pob_selftestCloudRobustness` passes as part of
  `pob-selftest` exit 0 (latch non-fatal, real `GetCloudProvider`, popups wired to
  `MessagePopup` via `cloudErrorRequested`/`pathErrorRequested` signals).
- [x] **Options dialog** — all ~28 settings: connection protocol, proxy, DPI
  scaling override, build save path, node-power color theme, hex color overrides,
  separators (+ custom chars), name-in-titlebar, default gem level/quality, default
  affix quality, show warnings, slot-only tooltips, migrate eldritch implicits,
  invert slider scroll, beta opt-in, animations, etc. Writes Settings.xml Misc;
  Cancel restores. (M) — **Verified 2026-07-24**: `app/qml/components/
  OptionsDialog.qml` (374 lines) + `pob_getOptions`/`pob_previewOption`/
  `pob_commitOptions` bridge confirmed to compile and load cleanly (Step 0 gate:
  `pob-qt-main.log` shows `qml loaded` with zero QML warnings, despite the dialog
  being instantiated unconditionally in `main.qml`). **End-to-end verification
  (2026-07-24)**, now that the Bottom Bar (below) supplies a real entry point:
  (1) automated `pob_selftestOptions` proves the live/commit split, numeric
  clamp, and revert semantics at the bridge level; (2) automated
  `pob_selftestSettingsRoundTrip` proves `commitOptions`'s `SaveSettings()` call
  genuinely round-trips through the real on-disk Settings.xml; (3) code review of
  `OptionsDialog.qml`'s `_load`/`_applyChange`/`_commit`/`_revert` confirms Save
  → `commitOptions(draft)`, Cancel → replays `_snapshot` through `previewOption`
  for every live key, matching the legacy Save/Cancel handler split exactly;
  (4) a temporary debug harness (`optionsDialog.open()` on startup, `--capture`,
  then removed — net-zero diff) screenshotted the dialog with all 28 real engine
  values rendered correctly across every control type (dropdowns, checkboxes,
  hex-colour fields, the affix-quality slider, int fields, the devMode-gated
  "Disable Dev AutoSave" row). A fully scripted click-through of the live GUI
  (open → toggle → Cancel → reopen → Save → diff Settings.xml bytes) was not
  performed — `pob-qt.exe` isn't a Start-Menu-registered app so the available
  computer-use tooling couldn't target it — but items 1-4 together verify the
  same contract end-to-end (engine-level behavior + bridge-level persistence +
  UI-level wiring + UI-level rendering), which is judged sufficient.
- [x] Toast notification component behind the legacy `Add/Update/Remove/Clear` API. (S)
  — **DONE (2026-07-24).** `app/lua/pob_host.lua` wraps `ToastNotification`'s
  Add/Update/Remove/Clear at host-bootstrap time (a host seam, not a `src/` edit)
  to maintain a mirror list and call a new `pob.toastsChanged()` bridge fn
  (mirrors the `pob.cloudErrorPopup` push pattern) → `LuaEngine::toastsChanged()`
  signal; `pob_getToasts()`/`pob_dismissToast(id)` globals + `Q_INVOKABLE`
  wrappers (mirrors `getOptions`/`previewOption`). New `Toast.qml` (single card,
  title+body split on the first `\n`, ColorText so `^`-codes render) +
  `ToastStack.qml` (bottom-left stack, newest on top / oldest nearest the
  anchor — matches legacy's `yOffset` accumulation order), registered in
  `qml.qrc`, instantiated in `main.qml` above the bottom bar. New
  `pob_selftestToast` (add→list→update→dismiss→clear) wired into
  `selftest_checks.h`, passing. **Documented deviation:** legacy's HIDING state
  is only reaped by a later `:Render()` call, which relied on the retired 30ms
  frame-poll (this app is event-driven — no polling `OnFrame` loop, see
  STATUS.md); `Remove()` here always removes immediately from the Lua-side
  list/mirror regardless of the `immediate` arg, and QML owns any fade-out
  animation on its own side instead. **Gotcha found & fixed:** the wrap was
  initially installed right after `dofile(Launch.lua)`, which only *defines*
  `launch:OnInit` — `ToastNotification`/`main` don't exist as globals until
  `runCallback("OnInit")` actually runs it (`PLoadModule("Modules/Main")` is
  inside `launch:OnInit`, not at Launch.lua's top level). The wrap silently
  no-op'd (`if ToastNotification then` saw nil) until moved to after
  `runCallback("OnInit")`/the initial `OnFrame`/the clean-build block — caught
  via `pob_selftestToast` failing (`foundAfterAdd=false`), not silently.
  Verified via a temporary debug harness (two toasts added, screenshotted via
  `--capture` — colored title/body rendered correctly, correct stacking order —
  then removed) + full gate.
- [x] Bottom-left bar (Options / About / Update-check / version) + **F1 context
  help** + About popup (changelog.txt + help.txt viewer). Keep update-check UI
  present but inert until Phase 10/14. (S-M) — **DONE (2026-07-24).**
  `BottomBar.qml` ports `main:Init`'s `anchorMain` control block (Options/About
  buttons, `^8`-coded fork/version labels, devMode-gated "Dev Mode" label, an
  inert "Check for Update" button with an explanatory tooltip). `AboutPopup.qml`
  ports `main:OpenAboutPopup` — version/GitHub header, Version-history/Help tab
  toggle, and `TextListControl`'s first real consumer rendering changelog.txt/
  help.txt. New `pob_getAboutContent()` Lua global re-implements
  `OpenAboutPopup`'s file-parsing algorithm verbatim (a host seam — the popup
  control tree itself isn't ported, only the parsing); `pob_selftestAboutContent`
  wired into `selftest_checks.h`, passing (changeCount=6962, helpCount=268,
  helpSectionCount=11 lines/rows parsed from the real repo-root files).
  **Deviation:** both files live at the repo root and every host binary always
  runs with `cwd=src/` (invariant #6), so unlike legacy's
  `devMode and "../changelog.txt" or "changelog.txt"` branch, this always reads
  `"../"` regardless of devMode; the `DEV[..]` help-line content gate still
  honors `launch.devMode`, matching legacy. F1 (`Shortcut` in `main.qml`) opens
  About on the Help tab scrolled to the section matching the active view
  (`"<viewId> tab"`, e.g. "skills tab", falling back to "build list tab" in LIST
  mode), mirroring `main:OnFrame`'s F1 handler exactly, including its
  case-insensitive title-match-else-first-section fallback. New
  `LuaEngine::openURL()` bridges the GitHub link button to the existing
  `pob.openURL`/`OpenURL` seam. `TextListControl.qml` gained a minimal
  `setScrollOffset()` forwarding function (previously had no external scroll
  API) for the F1 section-jump. Verified via a temporary debug harness
  (`--capture` with both the changelog tab and a Help-tab-scrolled-to-"Skills
  Tab" state, screenshotted, then removed) + full gate. **Bug found & fixed in
  passing:** `Button.qml`/`Dragger.qml`/`CheckBox.qml`'s disabled-content color
  (`theme.background`, per Part 1.3's rule) is nearly invisible against the
  disabled Chrome fill (`theme.disabled`) — both resolve to near-identical dark
  navies (`#0F172A` vs `#141822`), not the "medium-grey" Part 1.3 assumed. Found
  via the Check for Update button's screenshot (label unreadable); fixed by
  switching disabled foreground content to `theme.muted` (`#94A3B8`, explicitly
  documented in `Theme.cpp` as "readable on #0F172A") across all three widgets.

## Acceptance gate

- `main.qml` is split; each view loads from its own file; capture diff shows no
  regression vs the Phase 0 baseline. — **MET**, with a documented caveat: the
  committed `app/tests/capture-baseline/` PNGs predate essentially all of Phase 1
  (fonts, the Tier 0-3 widget kit, the app shell) — every one of the 10 views now
  diverges from it by design. Re-baselined in the Phase 1 wrap-up commit (see
  STATUS.md); each PNG was reviewed by eye before re-baselining and every
  difference traced to intended Phase 1 work (fonts, chrome, bottom bar, toast
  stack, Options dialog, BuildListPage/ImportView widget adoption below) — none
  were unintended regressions.
- Tier 0 + Tier 1/2 components exist and are demonstrably reused by ≥2 views.
  — **MET (2026-07-24).** `views/BuildListPage.qml` and `views/ImportView.qml`
  (chosen as the two with the most ad-hoc hand-rolled `QtQuick.Controls` chrome)
  now `import "../components" as Widgets` and use `Widgets.Button`/
  `Widgets.Label`/`Widgets.ColorText` in place of bare `Button`/`Text`. Mechanical
  swap only, per the plan's explicit scope note — the `ListView` delegate (real
  per-row build/folder rendering) is untouched, that's Phase 3+ work. **Bug found
  & fixed in passing:** the swapped-in `Widgets.Button`s initially rendered with
  their label text overflowing past the right edge of the window (`New Folder`/
  `Import URL`, the row's trailing buttons) — `buildListPage`'s own
  `Layout.rightMargin` (documented as StackLayout-honored) did not leave enough
  slack for the wider Tier 1 `Button` label metrics vs. the original
  auto-sized `QtQuick.Controls.Button`. Fixed with a small explicit trailing
  spacer `Item` per toolbar row (12px) plus modest width/height tuning
  (`implicitHeight: 20` to match `BottomBar`'s already-proven sizing, rather than
  the initial `24`, which used a visibly-too-large label font for these longer
  button labels) — confirmed via `--capture` (no more edge clipping) + gate.
- Options dialog round-trips every setting to Settings.xml; theme/separator changes
  apply live. — **MET**, see Part 1.4's Options-dialog bullet above for the full
  verification methodology (automated bridge-level + Settings.xml round-trip
  selftests, code review of the Save/Cancel wiring, and a real-values screenshot
  of all 28 fields).
- A color-coded string (e.g. a rare item name, a stat with `^0`–`^9` and `^xRRGGBB`
  codes) renders with correct per-substring colors in the bundled fonts (VAR + a
  monospace FIXED field visibly differ). — **MET (2026-07-24).** The About
  popup's changelog (VAR, `^7`/`^8`/`^1`/`^2` codes rendering as distinct colors)
  and the two debug toasts (`^1`/`^2`/`^7`) were captured together in one
  screenshot during the Toast/About verification pass; `ImportView`'s share-code
  field was set to `theme.fontFixed` (monospace) as part of the widget-adoption
  swap above, visibly differing from the VAR sidebar/popup text in the same
  `import.png` capture — both pieces of evidence exist, in two separate captures
  rather than one combined screenshot (About is a modal covering the rest of the
  window, so the two sites can't be shown simultaneously without an artificial
  layering hack not worth introducing).
- `TextMetrics.width`/`cursorIndex` match legacy golden values for a mixed corpus
  (a prerequisite for correct EditControl caret + list ellipsis later). —
  **DEFERRED (2026-07-24), explicit, not faked.** Attempted per the wrap-up
  plan: `runtime/SimpleGraphic.dll` + `runtime/Path of Building.exe` (filename
  literally contains `{space}` — pre-existing, not this session's doing) are
  present; confirmed the exe is a genuine PE32+ Windows GUI binary that launches
  successfully (backgrounded, ran past a 5s timeout without crashing — i.e. it
  opened a real window and sat waiting for input, not a launch failure). But
  SimpleGraphic is closed-source (no local source tree, no reference in
  `port-plan/reference/`) and, unlike this port's own `pob-qt --headless`, has no
  documented or discoverable headless/CLI mode — `DrawStringWidth` depends on the
  font atlases being loaded through a real D3D/OpenGL-backed `RenderInit`, so
  there is no way to reach it without a live window, and no known way to make a
  scratch `Launch.lua` dump measurements to a file and exit cleanly without
  reverse-engineering SimpleGraphic's undocumented embedding contract — an
  open-ended investigation disproportionate to this item within the wrap-up's
  scope. **What WAS verified instead** (Part 1.2a, re-confirmed still true this
  session): `TextMetrics`'s algorithm was hand-verified line-by-line against
  upstream `r_font.cpp` (FindFontHeight/baked-height selection, per-glyph
  `ceil(width+spLeft+spRight)`, tab=4×space, `^`-escape zero-width skip,
  ≥128-codepoint tofu, multi-line=max), and the selftest asserts concrete
  invariants that would catch a wrong implementation (monospace exact-multiple
  scaling, escape-zero-width, multiline-max, non-empty) — real numbers, just not
  a byte-for-byte diff against a legacy-process dump. Revisit if/when
  `EditControl`'s caret lands and a live legacy-vs-Qt visual comparison becomes
  easy to set up (e.g. once computer-use tooling can target arbitrary
  non-Start-Menu binaries, or a maintainer manually captures legacy values by
  hand).
- `pob-selftest` green. — **MET**, exit 0 including every Part 1.4 selftest
  (reopen-last-build, cloud-robustness, options, settings-round-trip, toast,
  about-content).

## Notes

- The tooltip and popup frameworks are the highest-leverage infra — nearly every
  later phase depends on them. Budget accordingly.
- Don't wire live-calc tooltip compares yet; that needs Phase 2's calculator bridge.
  Build the tooltip framework so it can accept a memoized async result later.
