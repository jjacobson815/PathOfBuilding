# Reference: UI Control Library (legacy → QML component kit)

The legacy UI is a custom immediate-mode widget library of ~46 Lua classes in
`src/Classes/`. Since the port uses **QML-native views** (not legacy draw code),
this catalog is the **spec for the QML component kit** — build the reusable
components once (Phase 1), then compose them per view. Tiers estimate porting
effort. Paths are `src/Classes/` unless noted.

## Base concepts to reproduce as QML idioms

- **Class system** (`Common.lua:78-159`): `newClass` multiple-inheritance mixins;
  `Control` (geometry/anchor/focus) + `ControlHost` (child container/input router)
  + mixins `TooltipHost`, `SearchHost`, `UndoHandler`.
- **Dynamic properties** (`Control.lua:47`): any prop (`shown`,`enabled`,`width`,
  `label`,...) may be a value **or a per-frame function**. → **QML property
  bindings** map directly; this is the single most important translation.
- **9-point anchor layout** (`Control.lua:66`) with a `collapse` flag (inherit a
  hidden anchor target's position). → QML anchors + a collapse convention.
- **Input model** (`ControlHost.lua:35`): events `{type=KeyDown|KeyUp|Char, key,
  doubleClick}`; **mouse buttons/wheel are keys** (`LEFTBUTTON`,`WHEELUP`);
  modifiers polled via `IsKeyDown`. Focus = **capture-by-return** (a handler
  returns the control to select). `OnHoverKeyUp` fires on the *hovered* (not
  focused) control — used for wheel-scroll-without-focus and the wiki hotkey.
- **Inline color codes** — two forms, `^0`–`^9` (a fixed 10-value palette) and
  `^xRRGGBB`, embedded in nearly every string (labels, list rows, tooltips, dropdown
  items) and originating inside untouchable calc/data Lua. **A faithful color-code
  rich-text renderer is mandatory infra** (Phase 1) and gates every text-bearing
  component. This is part of the larger text-rendering subsystem (fonts + metrics
  parity + the palette) — see [[text-rendering]] for the full spec and the exact
  `^0`–`^9` values.
- **Draw layers** for z-order: controls 0, dropdown panes sublayer 5, tooltips
  100, popups layer 10, drag-label 20. → QML z / overlay layers.

## Tier 0 — Infrastructure (prerequisites; build first, Phase 1)

- **Color-code rich-text renderer** (`^n`/`^xRRGGBB` → styled runs). Gates everything.
- **Theme/chrome kit** — border+fill chrome, hover/pressed/disabled gray palette,
  `DrawArrow`/`DrawCheckMark` glyphs. (`Theme.cpp` already loads `UITheme.lua` tokens.)
- **Tooltip framework** (`Tooltip.lua`, 643 lines) — programmatic `Clear/AddLine/
  AddSeparator/SetRecipe`; **param-memoized rebuild** (`CheckForUpdate` keyed on
  `outputRevision`); hover placement with viewport flip; multi-column overflow
  (`CalculateColumns`); rarity header art (13 configs: UNIQUE/RARE/MAGIC/GEM/
  PASSIVE/MASTERY, influence icons, foil tints); child tooltips (item-granted
  skills). Hover tooltips routinely run full calc compares — see [[calc-engine-contract]].
- **Modal popup framework** (`PopupDialog.lua` + `Main.lua:1596`) — popup **stack**,
  50% dim overlay, centered dialog, enter/escape control wiring, canned
  Message/Confirm(2–3 button)/NewFolder dialogs. **108 imperative call sites**
  (`56 OpenPopup + 21 OpenConfirm + 31 OpenMessage`) — provide a generic
  `openPopup(controls, enter, escape)` equivalent or every popup becomes bespoke.
- **Drag-and-drop framework** (`ListControl.lua:8-24`) — typed payloads;
  `GetDragValue→type,obj`, `CanReceiveDrag(type,val)`, `ReceiveDrag(type,val,src)`;
  10 px start threshold; target green highlight; insertion caret for reorder;
  cursor-following label. Used for items↔slots↔shared list↔minion dropdown, build
  rows→folders/breadcrumb, socket-group reorder.
- **UndoHandler** — generic undo/redo ring (~101 states); `CreateUndoState`/
  `RestoreUndoState`; sets `modFlag`. Per-tab (tree has its own on spec).
- **Input/focus model decision** — replace capture-by-return + mouse-as-key with
  Qt events; define keyboard-nav parity (TAB groups, RETURN/ESC in dialogs,
  wheel-on-hover, `OnHoverKeyUp` equivalents).

## Tier 1 — Trivial widgets (S each)

LabelControl · SectionControl (group box + floating label) · RectangleOutlineControl
· **ButtonControl** (~250 sites; label/image/+,-,x glyphs, locked/hover/pressed,
onHover, tooltip) · **CheckBoxControl** (label to the left, in hit area; borderFunc;
state-aware tooltip) · DraggerControl (drag-delta grip + right-click reset) ·
**SliderControl** (knob drag/jump, SHIFT 0.25 / CTRL 0.01 wheel steps, detents,
cursor-position value tooltip, invert-scroll option).

## Tier 2 — Medium widgets

- **ScrollBarControl** (`323` lines) — hold-to-repeat + acceleration (500 ms delay,
  50 ms ramp), page-jump, `ScrollIntoView`, autoHide, central wheel-key mapping.
  Consider a QML ScrollView policy shim.
- **PathControl** — breadcrumb; dynamic segment buttons; drag target; undo history.
- **TextListControl** — read-only multi-column rich-text scroll block; SHIFT+wheel
  jumps between sections (sidebar stat list, changelog).
- **ResizableEditControl** — EditControl + resize grip + min/max toggle.
- **SearchHost** — type-to-filter engine (word-order caseless match + highlight ranges).

## Tier 3 — Deep widgets (each is a real project)

- **EditControl** (`751` lines) — single/multiline editor: filter/limit,
  prompt/placeholder, **protected** (password) mode, selection+caret+blink,
  double-click word-select, clipboard with pasteFilter (non-ASCII→"?"), undo/redo
  with caret restore, **UTF-8 word-jump** (Ctrl+arrow, uses lua-utf8), Home/End/
  Page keys, both scrollbars, **numeric spinner** (+/- buttons, wheel, increments
  placeholder value too), clear button, Ctrl+click URL, zoom (Notes), enterFunc,
  tab-advance. Qt gives much of this free but parity on filter patterns
  (`%c`,`\/:%*%?"<>|%c` for filenames) must be mapped.
- **DropDownControl** (`561`) — combobox: drop-up/down + viewport clipping, 20-row
  pane, **type-to-search** with yellow match highlights + red no-match, label+detail
  rows, hover tooltips (BODY/HOVER modes), filtered-index selection mapping, auto
  pane/box width, wheel-select-when-closed. ~200 sites.
- **ListControl** (`478`, abstract) — THE list workhorse: virtualized rows,
  optional sortable column model, ellipsis clipping, icons, zebra/separator,
  selection/hover, empty-state text, keyboard map (UP/DOWN wrap, HOME/END, Ctrl+C/X,
  DELETE, F2), `OnSelClick`/double-click, per-row tooltips, full DnD source/target/
  reorder. **Blocks 15 subclasses** — build on QML ListView/TableView.
- **GemSelectControl** (`754`) — gem autocomplete combobox: tiered match patterns
  (exact→abbreviation "CtF"→prefix→contains) + `:tag`/`:-tag` syntax; **live
  DPS-sorted candidates** via calc engine (`CalcOutputWithThisGem`, memoized on
  group/level/quality/outputRevision); colored rows + DPS-delta markers; hover =
  full gem tooltip + "selecting this gives you:" compare; S/A filter buttons;
  ENTER/ESC commit/revert; supporting-gem cross-highlight; imbued mode. Depends on
  the async-calc decision.
- **ItemSlotControl** — slot dropdown with validity filtering, flask activate
  checkbox, drag-receive equip, **embedded jewel-socket tree viewer on hover**.
- **CalcSectionControl + CalcBreakdownControl** (`290`/`751`) — data-driven
  collapsible stat grid + breakdown panel (TEXT/TABLE/reservation/damage-type/slot/
  mod-table/radius-visual/**embedded node viewer**). See [[calc-engine-contract]].
- **ExtBuildListControl** (`437`) — provider-tabbed card list with async fetch
  (PoB Archives).

## Tier 4 — ListControl subclasses (mostly M once base exists)

ItemListControl · ItemDBControl + NotableDBControl (filter bar + coroutine→async
incremental sort with progress) · SkillListControl (link-color strings, slot icons,
right-click main-skill, Ctrl toggles) · BuildListControl + FolderListControl ·
**one generic "set manager" component** covers PassiveSpecListControl /
SkillSetListControl / ItemSetListControl / ConfigSetListControl · SharedItemListControl
· Minion list pair (dual-pane + search) · PowerReportListControl /
ComparePowerReportListControl · TimelessJewelListControl + TimelessJewelSocketControl
(embedded tree viewer) · PassiveMasteryControl · TradeStatWeightMultiplierListControl.

## Special note: embeddable tree viewer

`PassiveTreeView` is embedded **inside controls** (ItemSlotControl jewel viewer,
TimelessJewelSocketControl, CalcBreakdownControl node view), not just the tree tab.
The Qt tree renderer must be an **embeddable, multi-instance component**, not a
singleton. Design for this in Phase 4.

## Cross-cutting risks

- Immediate-mode → retained-mode impedance: per-frame `GetProperty`, hit-test in
  Draw, and sublayer z have no direct QML analog; easy to miss `noTooltip`
  suppression, `anchor.collapse` chains.
- Text-metrics parity (caret math, ellipsis, dropdown auto-width, tooltip columns)
  depends on escape-aware `DrawStringWidth`/`CursorIndex`. **Do NOT use QFontMetrics**
  — legacy accumulates integer per-glyph advances against bitmap atlases; use the
  `.tgf`-backed `TextMetrics` engine ([[text-rendering]]).
- Custom cross-control DnD is richer than default QML DnD; index-fixups on reorder
  (e.g. `SkillListControl:OnOrderChange` adjusts `mainSocketGroup`).
