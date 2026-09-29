# Phase 6 — Items Tab (the largest tab)

**Status:** IN PROGRESS — Part 6.1 done (2026-09-29, cloud session, branch `cloud/phase-6`)
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

- [ ] All-items list (ItemListControl): drag to slots/shared/minion dropdown,
  double-click edit, Ctrl+click equip (Shift=slot 2), delete/deleteUnused, sort. (M)
- [ ] Uniques DB + Rare Templates DB (ItemDBControl): filter dropdowns (slot/type/
  league/requirement/obtainable), search + search-mode dropdown, **stat-sort
  dropdown driving a coroutine-based incremental list build with % progress**
  (sorting runs the calc engine per item×slot — reuse the ItemDBControl coroutine
  pattern, resumed off the frame loop). (M-L)
- [ ] Shared item list (SharedItemListControl) — per-Settings.xml items + item sets
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
  `withKeys` swaps `IsKeyDown` for the call and restores it). No QML caller yet
  (the Build loadout dropdown is Phase 3 long tail).
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
