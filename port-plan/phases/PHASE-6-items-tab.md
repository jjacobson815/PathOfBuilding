# Phase 6 — Items Tab (the largest tab)

**Status:** NOT STARTED
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

- [ ] Item sets: dropdown (tooltip = set contents) + Manage popup; per-set slot
  assignments; `useSecondWeaponSet`; `EquipItemInSet` with Shift=second-slot. (M)
- [ ] Slot panel (ItemSlotControl per slot): all baseSlots — Weapon 1/2 + Swap
  variants (each with 6 abyssal sub-slots), Helmet/Body/Gloves/Boots/Belt (+ abyssal),
  Amulet, Rings 1/2, conditional **Ring 3** (AdditionalRingSlot), conditional
  **Graft 1/2** (3.27 tree), Flasks 1-5 (active checkboxes), Charms; jewel sockets
  from the tree (labelled "Socket #n", only allocated shown). **Weapon Set I/II
  buttons** (also re-point the main socket group). Each slot: item dropdown with
  validity filtering, tooltip with full item + swap-compare, drag-receive equip. (L)
- [ ] Duplicate passive-tree selector inside the tab (specSelect + Manage). (S)

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
