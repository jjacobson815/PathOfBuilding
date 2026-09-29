# Phase 6 — Items Tab (the largest tab)

**Status:** IN PROGRESS — Parts 6.1 + 6.2 done (6.1: 2026-09-29 cloud session; 6.2: 2026-09-29 Windows session; branch `cloud/phase-6`). Next: 6.3.
**Goal:** Port the item planner: item sets, the full slot panel, item/DB/shared
lists with the drag-drop matrix, and the deep display-item editor (variants,
sockets, enchant/anoint/corrupt/implicit, influences, catalysts, cluster crafting,
crafted affixes with roll sliders, custom/crucible mods), plus the full comparison
tooltip. This is `ItemsTab.lua` — 4771 lines, the biggest single view.
**Depends on:** Phase 1, Phase 2 (item compares), Phase 3 (shell), Phase 4
(embeddable tree viewer for jewel sockets).
**References to load:** [[tabs-catalog]] (Items tab), [[control-library]]
(ItemSlotControl, ItemDBControl, ListControl family), [[calc-engine-contract]]
(item compare via `repSlotName`+`repItem`, jewel-radius spec cloning).

## Part 6.1 — Item sets & slot panel

- [x] Item sets: dropdown (tooltip = set contents) + Manage popup; per-set slot
  assignments; `useSecondWeaponSet`; `EquipItemInSet` with Shift=second-slot. (M)
- [x] Slot panel (ItemSlotControl per slot): all baseSlots — Weapon 1/2 + Swap
  variants (each with 6 abyssal sub-slots), Helmet/Body/Gloves/Boots/Belt (+ abyssal),
  Amulet, Rings 1/2, conditional **Ring 3** (AdditionalRingSlot), conditional
  **Graft 1/2** (3.27 tree), Flasks 1-5 (active checkboxes), Charms; jewel sockets
  from the tree (labelled "Socket #n", only allocated shown). **Weapon Set I/II
  buttons** (also re-point the main socket group). Each slot: item dropdown with
  validity filtering, tooltip with full item + swap-compare, drag-receive equip. (L)
- [x] Duplicate passive-tree selector inside the tab (specSelect + Manage). (S)

## Part 6.2 — Lists (drag-drop matrix)

- [x] All-items list (ItemListControl): drag to slots/shared/minion dropdown,
  double-click edit, Ctrl+click equip (Shift=slot 2), delete/deleteUnused, sort. (M)
- [x] Uniques DB + Rare Templates DB (ItemDBControl): filter dropdowns (slot/type/
  league/requirement/obtainable), search + search-mode dropdown, **stat-sort
  dropdown driving a coroutine-based incremental list build with % progress**
  (sorting runs the calc engine per item×slot — reuse the ItemDBControl coroutine
  pattern, resumed off the frame loop). (M-L)
- [x] Shared item list (SharedItemListControl) — per-Settings.xml items + item sets
  shared across builds. (S)

## Part 6.3 — Display-item editor (deep)

- [ ] Panel: Add-to-build/Save, Edit…, Cancel, **Buy Similar** (→ Phase 12 trader);
  variant dropdowns (up to 6); socket color/link editors (6 dropdowns + link
  checkboxes + add-socket). (M)
- [ ] Craft popups: **Apply Enchantment** (lab/source/skill pickers, 2 slots),
  **Anoint** (up to 4, amulet/talisman rules, oil recipe tooltips), **Corrupt**
  (implicit selection incl. temple double-corrupt), **Add Implicit** (searchable
  incl. eldritch/synth), influence dropdowns (2 of 6), quality + catalyst + catalyst
  quality, cluster-jewel skill dropdown + node-count slider. (L)
- [ ] Crafted-item **prefix/suffix affix dropdowns** (up to 6, tier lists with tag/
  level/cluster-notable tooltips + stat-diff sorting) each with a roll-range slider;
  **Add modifier** custom popup (bench/essence/prefix/suffix/veiled/delve sources,
  sort-by-power option); **Add Crucible mod**; mod-range line dropdown + slider or
  (option) stacked sliders for all unique ranges. (L)
- [ ] Craft-item popup (rarity/title/type/base with live tooltip) + create/edit-
  text popup (raw text editor with live validity). (M)

## Part 6.4 — Comparison tooltip & rules

- [ ] Full item tooltip anchored below with comparison vs equipped: dps/def diffs
  per slot (via Phase 2 `repSlotName`+`repItem`), slot-only-tooltip option, **jewel-
  radius comparisons via cloned-spec evaluation** for radius-affecting jewels,
  influence header art, source text. (M-L)
- [ ] Rules: `IsItemValidForSlot`, `GetComparisonSlotNameForItem`,
  `CopyAnointsAndEldritchImplicits` on compare/equip. (M)
- [ ] Keyboard: Ctrl+V paste item from game clipboard, `e` edit hovered slot,
  Ctrl+Z/Y undo/redo, Ctrl+F focus DB search (toggle unique/rare), Ctrl+D toggle
  diff display. (S)

## Part 6.5 — Persistence

- [ ] `<Items>` XML round-trip: attribs (activeItemSet, useSecondWeaponSet,
  showStatDifferences); `<Item id variant variantAlt..5>` raw text + `<ModRange>`;
  `<ItemSet>` with `<Slot name itemId itemPbURL active>` + `<SocketIdURL>`;
  `<TradeSearchWeights>`; legacy flat `<Slot>`. (M)

## Acceptance gate

- Open a build → all slots populated correctly incl. abyssal/flask/jewel sockets;
  weapon-set swap works; item tooltips show correct compare diffs vs equipped.
- Paste a game-copied item → parses correctly (rarity, sockets, all mod types,
  influences, foils). Craft a rare via the affix dropdowns → correct mods + rolls.
- Anoint/enchant/corrupt/implicit popups produce correct items.
- Save → `<Items>` round-trips through legacy PoB.
- `pob-selftest` items check green; capture diff clean.

## Notes

- This is the biggest phase — sub-phase it (6.1 slots/sets, 6.2 lists, 6.3 editor,
  6.4 tooltips/rules, 6.5 persistence) and gate each. The editor (6.3) alone rivals
  a full tab.
- The item JSON parser (`ImportItemsAndSkills`) is shared with the Import tab
  (Phase 11) — build the parser here or in Phase 11 but reuse it, not twice.
- Jewel-radius compare needs the cloned-spec evaluation path — validate it against
  a radius jewel (e.g. a Watcher's Eye / threshold jewel) vs legacy.

## Session log — 2026-09-29 (Part 6.1)

Bridge: `app/lua/pob_items.lua` (new; `require`d by `pob_host.lua`). View: left
column of `app/qml/views/ItemsView.qml`. Gate check: `items-slots` (31 flags).
Recon brief (legacy file:line map) was written to the session scratchpad, not
committed.

- **Item sets:** dropdown (row tooltip = `AddItemSetTooltip`), Manage popup via
  the generic `SetManagePopup` (`pob_items{GetSetList,SetActiveSet,NewSet,
  CopySet,RenameSet,DeleteSet,MoveSet}`). Legacy has no Copy/Delete/Rename
  methods, so those bodies are lifted from `ItemSetListControl.lua` with
  pointers. New/Copy append to `itemSetOrderList` atomically (legacy's cancel
  path left an orphan). `EquipItemInSet` is exposed as `pob_itemsEquipInSet`
  with an explicit `shift` flag (legacy reads `IsKeyDown`, a stub in the host;
  `withKeys` swaps `IsKeyDown` for the call and restores it). No QML caller yet.
  (Correction, 6.2 session: legacy's caller is the sidebar MINION dropdown
  drop, Build.lua:548-557, not a loadout dropdown; 6.2 wires it as
  `pob_itemsDropOnMinion`, which also takes DB / shared items.)
- **Weapon Set I/II:** `pob_itemsSetWeaponSet(n)`, lifted from `ItemsTab.lua:
  222-262`, including moving the main socket group to the other weapon set.
- **Slot panel:** reads the live `orderedSlots` (never rebuilt). Rows are the
  slots whose legacy `shown()` is true and that are not inactive, so Ring 3,
  Graft 1/2, abyssal sockets and unallocated jewel sockets hide exactly as
  legacy does. `UpdateSockets()` is called in the state read because legacy
  only runs it from `Draw`/`AddItemTooltip`. Candidate rows follow the
  all-items list order (legacy `pairs` order is unstable). Equip re-checks
  `IsItemValidForSlot` in the bridge. Flask "active" checkbox persists into the
  set. Row tooltip = `AddItemTooltip(tip, item, slot)` (full item + compare).
- **Passive tree selector:** reuses the Tree tab's `pob_getSpecList` /
  `pob_setActiveSpec` and `SpecManagePopup` (no duplicate bridge).
- Ctrl+Z / Ctrl+Y in the tab (`pob_itemsUndo/Redo`) landed here because they
  were needed to test equip; the 6.4 keyboard item still lists the rest.

**Documented differences from legacy**
- Jewel socket rows do not draw the radius minimap (`ItemSlotHelper` draws with
  SimpleGraphic). The Tree viewer embed is the planned replacement.
- Dropping an item on a slot (drag-receive) is NOT done here; it belongs to the
  Part 6.2 drag-drop matrix. Equipping is via the slot dropdown for now.
- The right column is still the pre-Phase-6 item browser until Part 6.2.
- Slot panel scrolls with the mouse wheel / bar (legacy scrolls the whole tab).

**Verified visually (Xvfb, OccVortex build):** all 22 base/flask/socket rows
populate (3 allocated sockets labelled Socket #1-3); Weapon Set II hides the
main-hand rows and recalculates; Ring 1 dropdown lists only rings; a row
tooltip shows the item with "Equipping this item in Ring 1 will give you" diffs;
Manage Item Sets popup opens.

## Session log — Tue Sep 29 2026 (Part 6.2, first Windows session)

Windows bring-up first: the stale `build-win/` rebuilt with plain `ninja`
(CMake re-ran itself) on Qt 6.11.1 / msys2; both gate binaries exited 0 on the
first run with every Phase 4-6.1 check green. One Windows-only defect fixed:
`SocketGroupList.qml` built `"file://" + "C:/..."` (host "c"), so the Skills
list slot icons never loaded; drive-letter paths now get `file:///`.

Bridge (`app/lua/pob_items.lua`, section "6.2 Lists"): payloads are
`{kind, key}` with kind `item` (id) / `unique` / `rare` (DB item name; the DB
lists are keyed by name) / `shared` (index). Functions: `pob_itemsGetLists`
(all-items rows via the live `ItemListControl:GetRowValue`, shared rows, the
display item), `pob_itemsTooltip`, `pob_itemsCtrlClick` (lift of
ItemListControl.lua:161-185 / ItemDBControl.lua:320-346 with an explicit
`shift`), `pob_itemsOpenForEdit` / `pob_itemsCloseDisplayItem` (double-click;
all-items opens a copy holding the same id), `pob_itemsCopy`,
`pob_itemsDeleteQuery` (the ILC:198-232 confirm text) / `DeleteItem` /
`DeleteAll` / `DeleteUnused` / `SortList` / `MoveItem`, drop targets
`pob_itemsDropOnList` / `CanDropOnSlot` / `DropOnSlot` / `CanDropOnMinion` /
`DropOnMinion` / `DropOnShared`, shared `MoveShared` / `DeleteShared`, shared
sets `GetSharedSets` / `SharedSetTooltip` / `ShareSet` / `ImportSharedSet` /
`RenameSharedSet` / `DeleteSharedSet`, and the DB: `pob_itemsDBState`,
`pob_itemsDBSetFilter` (sets the LIVE control's selIndex / search.buf and runs
its own callback), `pob_itemsDBStep` (one slice: Main.lua's LoadItems
coroutine while loading, then ItemDBControl:Draw's list-build part with one
`ListBuilder` resume). Gate check: `items-lists` (44 flags).

QML: new `components/ItemListBox.qml` (ListControl for item rows: select,
Ctrl+click, double-click, Ctrl+C, Delete, hover tooltip, drag out, drop in with
insertion marker, reorder), `components/DragGhost.qml` (overlay-parented drag
payload, so any DropArea in the window or an open popup sees it) and
`components/ItemDBPanel.qml` (selector + filters + list + the job-scoped
`stepTimer` that pumps `pob_itemsDBStep` and stops when it reports done).
`ItemsView.qml`: column 2 (all items + DB), column 3 (help text / read-only
display item with Cancel, shared items), whole tab in a horizontal Flickable.
Slot rows are DropAreas.

**Replaced UI (not deleted):** the old right column `browserPane` is gone from
`ItemsView.qml`; `app/src/ItemModel.cpp` is no longer instantiated in
`main.cpp` (the file stays in CMakeLists, like SkillModel).
`LuaEngine::addItemFromRaw` / `pob_addItemFromRaw` now have no QML caller
(fix + reuse in 6.3).

**Shared-component changes (logged per the protocol):**
- `SetManagePopup.qml`: optional `sharedFn` adds the shared item sets pane
  (Delete / Rename, drag a build set onto it = share, drag a shared set onto
  the build list = new set, row tooltip = set contents, F2 / Delete act on the
  pane clicked last). Without `sharedFn` (Skills tab) nothing changes.
- `MainSkillPanel.qml`: the minion dropdown is a DropArea when it lists item
  sets (Animate Guardian), sidebar only (`suffix === ""`).
- `SocketGroupList.qml`: the Windows file-URL fix above.

**Documented differences from legacy**
- Legacy shows both DBs stacked when the tab is >= 980 px tall and the
  selector only below that; here the selector is always shown (one DB).
- Shared item list: a drop below the last row APPENDS (legacy inserts at
  `selDragIndex or #list`, i.e. before the last item). Shared set drops append
  too.
- Importing a shared set also runs `PopulateSlots` + `SyncLoadouts` (legacy
  ItemSetListControl:ReceiveDrag skips both).
- Double-click opens the item read-only in column 3 with Cancel; Save / Add to
  build and the editor controls are Part 6.3.
- The shared list is hidden while a display item is shown (legacy draws the
  item over it).
- No "Craft item..." / "Create custom..." buttons yet (Part 6.3).
- The DB list rebuilds on every recalc while the Items tab is visible, like
  legacy's Draw; with a stat sort that is a full calc pass (sliced).
- Header buttons use the Qt font, so "Sort" slightly overlaps "All items:" at
  this width (legacy's narrower font just fits).

**Verified**
- `items-lists` (44 flags, pob-selftest and pob-qt --headless): Ctrl+click
  equip / toggle / Shift to Ring 2, delete question only when used, tooltip
  with explicit SHIFT then `IsKeyDown` restored, CRLF copy, reorder + undo,
  Sort (equipped first), double-click copy with same id + close, Delete
  Unused, Delete All + undo, DB loaded by the pump (1145 uniques), slot filter
  (62 belts), name search, stat sort by Life over the belt subset ordered by
  `measuredPower`, DB Ctrl+click copies (DB item never gets an id), drop on
  list at index / on a valid slot only, Rare Templates DB, minion drop copies a
  DB item into a set, shared append / insert / copy back / delete, shared set
  share / rename / tooltip / import / delete. Shared lists are snapshotted and
  restored in place; `Copy` is swapped (it crashes pob-qt --headless).
- Fail-when-removed: dropping the Shift redirect -> `shiftSecondSlot=false`;
  legacy `#list` insertion -> `shareAppends=false`; no `ListBuilder` resume ->
  `dbLoaded/dbSlotFilter/dbSearch/statSortDone=false`. (Breaking only the
  loader pump did not fail in pob-selftest: earlier checks' OnFrame calls
  already finished the DB load there.)
- Capture (Windows, OccVortex): all-items rows colour-coded, DB filters and
  the Uniques list populated by the step timer, no QML warnings.
- NOT verified (no computer-use tools in this session): mouse drag-drop onto
  slots / lists / the minion dropdown, hover tooltips, Ctrl+click in the GUI,
  the Manage Item Sets shared pane, the "Sorting... (N%)" progress text.
