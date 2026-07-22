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

- [ ] Extract each view into its own `.qml` under `app/qml/views/`, shared widgets
  under `app/qml/components/`, and register a QML module / update `qml.qrc`. Do this
  **after** Phase 0's nesting fixes so behavior is verifiable before/after via
  capture diff. (M-L)

## Part 1.2a — Text-rendering subsystem (build FIRST — gates all text)

Full spec in [[text-rendering]]. This was missed in the first plan pass and is the
most pervasive concern. The bitmap font atlases already ship in
`runtime/SimpleGraphic/Fonts/`.

- [ ] **Bundle + register fonts.** Add Liberation Sans (Regular+Bold) + Bitstream
  Vera Sans Mono (or DejaVu Sans Mono) to a Qt resource; `QFontDatabase::
  addApplicationFont()` in `main.cpp` before QML load. Decide the **Fontin
  licensing** question (exljbris Extended License to bundle, reuse the bundled
  atlases, or substitute an OFL small-caps face) — 104 item/gem/tree sites. (M)
- [ ] **Extend `Theme`** (replace the single `m_fontFamily="sans-serif"` at
  `Theme.cpp:80`): add `fontVar`/`fontVarBold`/`fontFixed` (+ `fontFontinSC`/
  `fontFontin` if licensed) + a name→QFont resolver keyed by the 7 `fontMap`
  strings. Wire QML widgets to the right family (monospace fields → `fontFixed`). (S-M)
- [ ] **`TextMetrics` engine** — a C++ class that loads `runtime/SimpleGraphic/
  Fonts/*.tgf` and reproduces `r_font_c` EXACTLY (per-glyph `ceil`, `width+spLeft+
  spRight`, atlas selection + scale, tab=4×space, tofu for ≥128, inline escape
  skip). **Do NOT use `QFontMetrics`** — it drifts and breaks caret/ellipsis/auto-
  width. Expose to Lua (real `DrawStringWidth`/`DrawStringCursorIndex`, replacing
  the `pob_host.lua:78-83` stubs) AND to QML (`Q_INVOKABLE width`/`cursorIndex`).
  Add golden parity tests vs legacy for a mixed corpus. (L)
- [ ] **Color-code rich-text renderer** — one shared C++ parser: PoB string →
  ordered `(QColor, text)` runs, honoring `^0`–`^9` (exact palette; `fromRgbF` for
  ^8/^9), `^xRRGGBB`/`^XRRGGBB`, literal `^`, and carry-forward default (`^7` =
  reset). Render via `Text.StyledText` spans or a `QQuickPaintedItem`. **Gates every
  text component.** Do NOT reuse `Theme::parseColor` (single-token only). (M)

## Part 1.2 — Tier 0 infrastructure (build in this order)
- [ ] **Theme/chrome kit** — border+fill chrome, hover/pressed/disabled palette,
  arrow/checkmark glyphs, over the existing `Theme.cpp` tokens (`UITheme.lua`). (M)
- [ ] **Tooltip framework** — programmatic `clear/addLine/addSeparator`, param-
  memoized rebuild keyed on `outputRevision` (`CheckForUpdate` equiv), hover
  placement with viewport flip, multi-column overflow, rarity header art (13
  configs), child tooltips. Hover tooltips will later run calc compares (Phase 2
  wires that). (L)
- [ ] **Modal popup framework** — popup **stack**, dim overlay, centered dialog +
  title plate, enter/escape wiring; generic Message / Confirm(2–3 button) /
  TextInput / NewFolder dialogs. Provide a generic `openPopup(controlsModel, enter,
  escape)` so the ~108 legacy call sites map onto one component rather than 108
  bespoke dialogs. (L)
- [ ] **Drag-and-drop framework** — typed payloads (Item / Build / MinionId /
  SocketGroup), `canReceiveDrag`/`receiveDrag` protocol, 10 px threshold, target
  highlight, insertion caret for reorder, cursor-following label. (L)
- [ ] **UndoHandler equivalent** — generic undo/redo ring for edit fields + tab-
  level state (`createUndoState`/`restoreUndoState`, sets `modFlag`). (S)
- [ ] **Input/focus model** — Qt event handling that reproduces the needed legacy
  semantics: TAB-order groups, RETURN/ESC in dialogs, wheel-on-hover, the
  `OnHoverKeyUp` behaviors (wheel-scroll-without-focus, wiki hotkey on hovered row).
  Document what is intentionally dropped. (M)

## Part 1.3 — Tier 1 + Tier 2 widgets

- [ ] Tier 1 (S each): Label (color-code), Section (group box), RectangleOutline,
  **Button** (label/image/+,-,x glyphs, locked/hover/pressed, onHover, tooltip),
  **CheckBox** (left label in hit area, borderFunc, state-aware tooltip), Dragger,
  **Slider** (SHIFT/CTRL wheel speeds, detents, cursor-value tooltip, invert option).
- [ ] Tier 2: ScrollBar behaviors (or ScrollView policy shim: hold-to-repeat accel,
  page-jump, ScrollIntoView, autoHide, wheel-key mapping), PathControl breadcrumb,
  TextListControl (multi-column rich-text scroll + SHIFT-wheel section jumps),
  ResizableEditControl, SearchHost (type-to-filter + highlight ranges).

Defer the Tier 3 deep widgets (EditControl, DropDownControl, ListControl base,
GemSelectControl, ItemSlotControl, CalcSection/Breakdown) to the phases that first
need them, but keep them on the [[control-library]] backlog so they're built once.
(EditControl and DropDownControl are needed early — build them here or at first use
in Phase 3.)

## Part 1.4 — Application shell

- [ ] Mode manager (LIST/BUILD) driven from QML, honoring the OnFrame-deferred
  `SetMode` swap and `GetArgs` persistence (reopen last build). (S — bridge exists;
  verify lifecycle.)
- [ ] Settings.xml round-trip complete (Mode/Args, Accounts, SharedItems, Misc) —
  confirm `OnExit` (wired in Phase 0) saves; userPath now = Documents/"Path of
  Building" (Phase 0). (M)
- [ ] **User-data policy + cloud robustness** (see [[core-lifecycle]]): ratify SHARE
  vs SEPARATE (recommend SHARE — record in STATUS + document the engine-version-
  lockstep requirement; if SEPARATE, add a first-run copy-migration of `Builds/` +
  `Settings.xml`). Make the `errorReadingSettings` latch **non-fatal** (retry-after-
  hydrate / don't latch on first failure) so a transient OneDrive dehydrated read
  doesn't silently kill settings persistence for the session. Implement a real Qt
  `GetCloudProvider` (replace the `pob_host.lua:182` stub) and wire
  `OpenCloudErrorPopup`/`OpenPathPopup` to real QML dialogs (they build
  SimpleGraphic labels today → no-op in QML). (M)
- [ ] **Options dialog** — all ~28 settings: connection protocol, proxy, DPI
  scaling override, build save path, node-power color theme, hex color overrides,
  separators (+ custom chars), name-in-titlebar, default gem level/quality, default
  affix quality, show warnings, slot-only tooltips, migrate eldritch implicits,
  invert slider scroll, beta opt-in, animations, etc. Writes Settings.xml Misc;
  Cancel restores. (M)
- [ ] Toast notification component behind the legacy `Add/Update/Remove/Clear` API. (S)
- [ ] Bottom-left bar (Options / About / Update-check / version) + **F1 context
  help** + About popup (changelog.txt + help.txt viewer). Keep update-check UI
  present but inert until Phase 10/14. (S-M)

## Acceptance gate

- `main.qml` is split; each view loads from its own file; capture diff shows no
  regression vs the Phase 0 baseline.
- Tier 0 + Tier 1/2 components exist and are demonstrably reused by ≥2 views.
- Options dialog round-trips every setting to Settings.xml; theme/separator changes
  apply live.
- A color-coded string (e.g. a rare item name, a stat with `^0`–`^9` and `^xRRGGBB`
  codes) renders with correct per-substring colors in the bundled fonts (VAR + a
  monospace FIXED field visibly differ).
- `TextMetrics.width`/`cursorIndex` match legacy golden values for a mixed corpus
  (a prerequisite for correct EditControl caret + list ellipsis later).
- `pob-selftest` green.

## Notes

- The tooltip and popup frameworks are the highest-leverage infra — nearly every
  later phase depends on them. Budget accordingly.
- Don't wire live-calc tooltip compares yet; that needs Phase 2's calculator bridge.
  Build the tooltip framework so it can accept a memoized async result later.
