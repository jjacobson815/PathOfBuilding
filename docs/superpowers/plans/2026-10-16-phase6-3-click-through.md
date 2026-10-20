# Phase 6.3 item 2: click-through check (craft popups)

Commit under test: `ddf4bee06` on `cloud/phase-6`. Tick each box as it passes. If one fails, write
what you did and what you saw under it (a screenshot helps), then keep going.

## Setup

1. Double-click `run_pob_fusion.bat` in the repo folder. It rebuilds, installs and opens the app.
2. Open one of your own builds that has a few skills in it (this matters for "All skills" in 2.1).
3. Go to the **Items** tab.
4. To make a test item: click **Create custom...**, paste the text, click **Create**. To swap to another
   test item: click **Cancel** in the editor first, then **Create custom...** again.

Test items (copy each block exactly):

| Name | Text |
|---|---|
| A. Rare helmet | `Rarity: Rare` / `Test Helm` / `Iron Hat` |
| B. Exarch helmet | `Rarity: Rare` / `Exarch Helm` / `Iron Hat` / `Searing Exarch Item` |
| C. Amulet | `Rarity: Rare` / `Test Amulet` / `Gold Amulet` |
| D. Crafted ring | `Rarity: Rare` / `Test Ring` / `Gold Ring` / `Crafted: true` |
| E. Cluster jewel | `Rarity: Rare` / `Test Cluster` / `Large Cluster Jewel` / `Crafted: true` |
| F. Unique belt | `Rarity: Unique` / `Test Unique` / `Leather Belt` / `Implicits: 1` / `+(25-40) to maximum Life` / `+(40-50) to maximum Life` |

(Each `/` is a new line.)

## 1. Editor sections

Item **A** (rare helmet):

- [ ] 1.1 The button row shows **Apply Enchantment...**, **Corrupt...** and **Add Implicit...**. No Anoint button.
- [ ] 1.2 Two influence dropdowns show. The list includes Searing Exarch and Eater of Worlds (armour only).
- [ ] 1.3 Pick **Shaper** in the first and **Elder** in the second. The tooltip shows both influences.
- [ ] 1.4 Quality: type `15`. The tooltip updates **as you type**, without pressing Enter.
- [ ] 1.5 Quality: type `1a`. Only `1` is kept. Type `150`. Only `15` is kept (2-character limit).
- [ ] 1.6 Quality: clear the box and click elsewhere. The box shows `0` and stays visible.
- [ ] 1.7 Type `20` in Quality, then click **Add to build** right away (don't press Enter). Double-click
      the new item in the All items list: it has Quality 20.
- [ ] 1.8 Click Cancel. Type `9` in Quality on a fresh item A, then double-click a **different** item in
      the list without clicking away first. The opened item does NOT get Quality 9.

Item **D** (crafted ring):

- [ ] 1.9 The influence list is shorter than the helmet's (no Exarch / Eater).
- [ ] 1.10 The catalyst dropdown shows. Pick **Abrasive (Attack)**. A catalyst quality box appears with `20`.
- [ ] 1.11 Type `10` in catalyst quality. The tooltip updates as you type.

Item **E** (cluster jewel):

- [ ] 1.12 A skill dropdown shows, with **Added Passives:** and a slider under it.
- [ ] 1.13 Pick another skill. The tooltip's enchant lines change to that skill.
- [ ] 1.14 Drag the slider slowly end to end. It moves in steps (8 to 12 passives). The drag doesn't
      lag, and "Adds N Passive Skills" in the tooltip follows the slider.

Item **F** (unique belt):

- [ ] 1.15 No influence dropdowns show.

## 2. Popups

### 2.1 Apply Enchantment (item A)

- [ ] Click **Apply Enchantment...**. The "Enchant Item" popup opens.
- [ ] **All skills:** is unchecked, and the Skill list only shows skills from your build. Check it: the list grows.
- [ ] Open the Enchantment list and type a word (for example `damage`). The list filters to matching rows.
- [ ] With a filter typed, press **Escape** once. The filter clears and the list stays open. Escape again closes the list.
- [ ] Hover a row. A tooltip shows the helmet with that enchant.
- [ ] Pick a row, click **Enchant**. The popup closes and the item tooltip shows the enchant.
- [ ] Reopen, click **Remove**. The enchant is gone.
- [ ] Press **Enter** inside the popup. Nothing happens (expected for now; known separate bug).

### 2.2 Anoint (item C)

- [ ] Click **Anoint...**. The "Anoint Item" popup opens and the notable list fills (may show "Sorting..." first).
- [ ] Hover a notable. The tooltip shows the node, its oil recipe and the stat change.
- [ ] Click notable X. The button reads **Anoint X**.
- [ ] Type part of a **different** notable's name in Search. The highlight stays on X if X is still listed,
      or disappears if it isn't. The button still reads **Anoint X**.
- [ ] Clear the search and click **Anoint X**. The tooltip shows "Allocates X".
- [ ] Reopen Anoint without clicking a notable. The button reads **Remove X**. Click it: the anoint is gone.

### 2.3 Corrupt (item A, then F)

Item A:

- [ ] Click **Corrupt...**. Implicit #1 and #2 show. No Implicits / Roll Ranges buttons.
- [ ] Pick a mod in Implicit #1. That mod's group no longer appears in Implicit #2.
- [ ] Pick a mod in #2 too. Then pick **Corrupted** again in Source. **Both implicits stay as picked.**
- [ ] Switch Source to **Scourge**. Three implicit dropdowns show and the popup grows.
- [ ] Hover the **Corrupt** button. The tooltip previews the corrupted item.
- [ ] Back on Corrupted with two picks, click **Corrupt**. The item is corrupted with those implicits.

Item F:

- [ ] Click **Corrupt...**. **Implicits** and **Roll Ranges** buttons show.
- [ ] Click **Roll Ranges**. A row for the Life line shows with a value of `1.00` and a slider.
- [ ] Drag that slider to the right end. The value reads `1.22` and the line text updates. The rows don't flicker or jump.
- [ ] Click **Corrupt**. The tooltip shows the higher Life roll and the item is corrupted.

### 2.4 Add Implicit (item B, then A)

Item B:

- [ ] Click **Add Implicit...**. Source lists **Searing Exarch**, **Delve**, **Custom**.
- [ ] Hover a Type row. The tooltip shows the mod and its stat change.
- [ ] Pick a Type, then the same Type again. The chosen Modifier stays (it doesn't reset).
- [ ] Click **Add**. One Exarch implicit is added.
- [ ] Do it again with a different Exarch mod. The first Exarch implicit is **replaced**, not stacked.

Item A:

- [ ] Source **Custom**: a text box shows. Type `+10 to Strength`, click **Add**. The line appears as an implicit.
- [ ] Custom again with only spaces, click **Add**. Nothing is added.

## 3. Nothing else broke

- [ ] **Tree** tab: open the spec dropdown and the version dropdown. Both list and pick normally.
- [ ] **Skills** tab: open a gem or socket-group dropdown. It lists and picks normally.
- [ ] Items tab: the Uniques list filters and the slot dropdowns still work.

## Results

Passed: __ / __  ·  Failed: list the box numbers and notes here.
