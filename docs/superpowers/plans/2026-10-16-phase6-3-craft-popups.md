# Phase 6 Part 6.3 Item 2 — Craft Popups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the display-item craft controls: Apply Enchantment (x2), Anoint (x4), Corrupt (incl. Scourge and unique Roll Ranges), Add Implicit, the two influence dropdowns, quality, catalyst + catalyst quality, and the cluster-jewel skill dropdown + node-count slider.

**Architecture:** Same rule as 6.3 item 1: the LIVE legacy controls are the single source of truth. The editor sections (influence, quality, catalyst, cluster) already exist as live controls on `itemsTab.controls`; the bridge sets a control's state and calls its own closure. The four popups are built by legacy methods (`EnchantDisplayItem`, `AnointDisplayItem`, `CorruptDisplayItem`, `AddImplicitToDisplayItem`) as a local `controls` table passed to `main:OpenPopup`. The bridge **captures** that table by swapping `main.OpenPopup` for the duration of the call, keeps it as one module-local "craft session", and drives those live controls by name. QML popups only render the session state and forward user actions.

**Tech Stack:** LuaJIT bridge (`app/lua/pob_items.lua`), Qt 6 QML (`app/qml`), C++ selftest registry (`app/src/selftest_checks.h`).

**Spec:** `port-plan/phases/PHASE-6-items-tab.md` (Part 6.3, item 2). Also read `port-plan/handoff/HANDOFF-phase6.md` and `port-plan/handoff/phase6-items-recon.md` §6.3 (legacy line map; note its line refs for these popups are IT:478-673, 1765-1812, 2280-2972, 3389-3700 — the handoff's "2973-3760" range covers items 3's custom/crucible popups, not item 2).

**Base:** branch `cloud/phase-6` at `311f5e9` (6.3 item 1). Parts 6.1, 6.2, 6.3 item 1 are DONE; do not redo them.

## Global Constraints

- Bridge functions are top-level globals named `pob_*`; `LuaEngine::invoke` refuses `pob_selftest*` from QML.
- Never marshal an Item, mod table, control, Tooltip or list row raw. Send labels, numbers, booleans and 1-based indices only (calc-touched tables run `luaToVariant` to gigabytes).
- `IsKeyDown` and `GetCursorPos` are host stubs; no new code may depend on them.
- Display-item edits are not undo steps and do not recalc: return `{ ok = true, _emit = { "items" } }` (use `displayEdited(it)`).
- Keep the legacy side-effect order: mutate → `BuildAndParseRaw()` → section rebuild → `UpdateDisplayItemTooltip()` (the closures already do this; do not re-order them).
- QML: `Label` is ONE line; push values imperatively into `EditControl.text` / `CheckBox.state` after a refresh (outside bindings break on first edit); repeat rows with a COUNT model; never bind a `ConfirmPopup.message` to a changing selection (Qt 6.4 crash).
- QML files live in the qrc: add each new file to `app/qml/qml.qrc` and rebuild after any QML change.
- Windows builds and runs need `PATH="/c/msys64/mingw64/bin:$PATH"`; `pob-selftest.exe` needs ABSOLUTE `src runtime host` args.
- `STATUS.md` keeps "ACTIVE: Phase 6" (6.5 is not ticked).
- Out of scope: Windows screenshot re-baselines, the `PopupBase` Keys-on-Dialog bug, 6.3 items 3-4 (affix dropdowns, custom/crucible popups, craft-item popup), 6.4, 6.5.

**Qt skills:** the `qt-development-skills` plugin was not loaded when this plan was written. At the start of Task 5, list that plugin's skills (`/plugin` → Installed). If it is loaded, use its QML coding skill in Tasks 5-7 and its QML review skill in Task 8. If it is not, say so once and continue; Task 8's `qmllint` pass stands in.

## Gate commands (used by every task)

Windows (Git Bash, repo root):

```bash
P=/c/msys64/mingw64/bin; R=$(pwd)
PATH="$P:$PATH" ninja -C build-win pob-selftest pob-qt
PATH="$P:$PATH" QT_FORCE_STDERR_LOGGING=1 build-win/pob-selftest.exe "$R/src" "$R/runtime" "$R/app/lua/pob_host.lua"; echo EXIT=$?
PATH="$P:$PATH" QT_FORCE_STDERR_LOGGING=1 build-win/pob-qt.exe --headless --src "$R/src" --runtime "$R/runtime" --host "$R/app/lua/pob_host.lua"; echo EXIT=$?
```

Lua-only edits need no rebuild for `pob-selftest` (the host file is loaded from `app/lua`); C++ and QML edits do. The exit code is the verdict; the `items-craft ok = ... flag=false` line names the failing flag.

## Review Focus

1. **Stale craft session** — the display item is cancelled, replaced or undone while a popup is open (or a popup is opened twice). Expect every craft call to refuse (`ok=false`) and leave the display item untouched. Test: Task 2 `staleRefused`.
2. **Empty numeric field** — clearing the Quality (or Catalyst quality) box. Legacy sets `quality=nil`, which hides the Quality field mid-edit. Expect the field to stay and the value to become 0 (documented difference). Test: Task 1 `qualityEmptyIsZero`.
3. **Re-anoint / remove anoint** — opening Anoint on an already anointed amulet with no row selected. Expect the button to read "Remove <name>" and remove only that anoint. Test: Task 3 `anointRemove`.
4. **Eldritch implicit applied twice** — expect the second Exarch implicit to REPLACE the first (legacy `applyCandidateMod`), not stack. Test: Task 4 `eldritchReplaces`.
5. **Corrupt implicit pair** — the second dropdown must never offer a mod from the group picked in the first. Test: Task 4 `corruptExcludesGroup`.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `app/lua/pob_items.lua` | Modify (section "6.3 Display-item editor" + selftests) | Generic live-control record/set helpers; section-control setter; craft-session capture engine; notable-list pump; `pob_selftestItemsCraft` |
| `app/src/selftest_checks.h` | Modify (after `items-editor`, ~line 965) | Register `items-craft` |
| `app/qml/components/DropDownControl.qml` | Modify | Opt-in `searchable` type-to-filter (legacy dropdowns filter while dropped) |
| `app/qml/views/ItemsView.qml` | Modify (`editCol`, after the socket section) | Craft-button row, influence, quality, catalyst, cluster sections; popup instances |
| `app/qml/components/CraftPopupBase.qml` | Create | Shared craft-session popup shell (open/state/set/click/tooltip/close) |
| `app/qml/components/CraftEnchantPopup.qml` | Create | "Enchant Item" layout |
| `app/qml/components/CraftAnointPopup.qml` | Create | "Anoint Item" layout + list pump timer |
| `app/qml/components/CraftCorruptPopup.qml` | Create | "Corrupted Item" layout incl. Scourge + Roll Ranges |
| `app/qml/components/CraftImplicitPopup.qml` | Create | "Add Implicit to Item" layout |
| `app/qml/qml.qrc` | Modify | Register the five new components |
| `port-plan/phases/PHASE-6-items-tab.md`, `port-plan/STATUS.md`, `port-plan/handoff/HANDOFF-phase6.md` | Modify | Tick item 2, session log, stop point |

---

### Task 1: Editor sections — influence, quality, catalyst, cluster (bridge)

**Files:**
- Modify: `app/lua/pob_items.lua` (`editorRecord` ~458-487; new helpers + setter after `pob_itemsDisplayAddSocket` ~1074; new selftest after `pob_selftestItemsEditor`)
- Modify: `app/src/selftest_checks.h` (~965)

**Interfaces:**
- Consumes: `ctx()`, `fail()`, `shownCtl(ctl)`, `dropLabels(list)`, `displayEdited(it)`, `pob_itemsEditTextSave(text, rarityIndex, alsoAdd)`, `pob_itemsGetLists()`, selftest helpers `itSnapshot / itRestore / finish / linesText`.
- Produces:
  - `local function ctlKind(ctl) -> "drop"|"check"|"edit"|"slider"|"button"|"label"|"list"|nil` — from `ctl._className` (`DropDownControl`, `CheckBoxControl`, `EditControl`, `SliderControl`, `ButtonControl`, `LabelControl`, `NotableDBControl`/any `ListControl`).
  - `local function ctlRecord(ctl) -> table` — `{ type, shown, enabled }` plus: drop `list` (labels), `sel`; check `state`, `label`; edit `text` (= `buf`); slider `val`, `divCount`; button/label `label` (`ctl:GetProperty("label")`, so function labels resolve). `enabled` = `ctl:IsEnabled()` under pcall.
  - `local function setCtl(ctl, value) -> ok:boolean, err:string|nil` — drop: valid 1-based index → `selIndex = i`, then `selFunc(i, list[i])` when present; check: `state = value and true or false`, then `changeFunc(state)`; edit: `buf = tostring(value)`, and when `ctl.filter == "%D"` and `buf == ""` set `buf = "0"` (Review Focus 2), then `changeFunc(buf)`; slider: clamp to 0..1 → `val`, then `changeFunc(val)`; list: `ctl:SelectIndex(i)` + `selIndex = i`. Anything else → `false, "bad value"`.
  - `local SECTION_CONTROLS = { "displayItemInfluence", "displayItemInfluence2", "displayItemQualityEdit", "displayItemCatalyst", "displayItemCatalystQualityEdit", "displayItemClusterJewelSkill", "displayItemClusterJewelNodeCount" }`
  - `function pob_itemsDisplaySetControl(name: string, value) -> { ok=true, _emit={"items"} } | { ok=false, error }` — refuses names not in `SECTION_CONTROLS`, hidden controls, and no display item.
  - `editorRecord(it)` gains (all plain):
    - `craftButtons = { enchant1, enchant2, anoint1, anoint2, anoint3, anoint4, corrupt, addImplicit }` (booleans from `shownCtl` on `displayItemEnchant`, `displayItemEnchant2`, `displayItemAnoint`..`displayItemAnoint4`, `displayItemCorrupt`, `displayItemAddImplicit`)
    - `influence = { shown, list, sel1, sel2 }`
    - `quality = { shown, text }`
    - `catalyst = { shown, list, sel, qualityShown, qualityText }`
    - `cluster = { shown, list, sel, val, divCount, count, minNodes, maxNodes }` (`count` = `displayItem.clusterJewelNodeCount`; nil-safe when not a cluster jewel)
  - `function pob_selftestItemsCraft() -> { ok, <flags> }`, check label `items-craft`.

- [ ] **Step 1: Write the failing selftest (sections part) and register it**

Add `pob_selftestItemsCraft` with the same snapshot / pcall / `SetDisplayItem()` / `itRestore` / `finish` frame as `pob_selftestItemsEditor`. Section-part flags (create each fixture with `pob_itemsEditTextSave(text, rarityIndex, false)` from no display item):

```lua
-- Influence (armour gets the eldritch list).
pob_itemsEditTextSave("Rarity: Rare\nCF Helm\nIron Hat\n", 3, false)
local e = pob_itemsGetLists().display.editor
res.influenceShown = e.influence.shown == true and #e.influence.list == 1 + #itemLib.influenceInfo.all
local shaperIdx, elderIdx
for i, label in ipairs(e.influence.list) do
    if label == "Shaper" then shaperIdx = i elseif label == "Elder" then elderIdx = i end
end
res.influenceSet = pob_itemsDisplaySetControl("displayItemInfluence", shaperIdx).ok
    and pob_itemsDisplaySetControl("displayItemInfluence2", elderIdx).ok
    and it.displayItem.shaper == true and it.displayItem.elder == true
    and it.displayItem:BuildRaw():find("Shaper Item", 1, true) ~= nil
-- Quality, incl. the empty box (Review Focus 2).
pob_itemsDisplaySetControl("displayItemQualityEdit", "15")
res.qualitySet = it.displayItem.quality == 15
pob_itemsDisplaySetControl("displayItemQualityEdit", "")
res.qualityEmptyIsZero = it.displayItem.quality == 0
    and pob_itemsGetLists().display.editor.quality.shown == true
-- A ring is not influence-list "all"; a unique is not influenceable.
pob_itemsEditTextSave("Rarity: Rare\nCF Ring\nGold Ring\nCrafted: true\n", 3, false)
e = pob_itemsGetLists().display.editor
res.ringDefaultInfluence = #e.influence.list == 1 + #itemLib.influenceInfo.default
-- Catalyst on a crafted ring.
res.catalystShown = e.catalyst.shown == true and e.catalyst.qualityShown == false and #e.catalyst.list == 13
pob_itemsDisplaySetControl("displayItemCatalyst", 2)
e = pob_itemsGetLists().display.editor
res.catalystSet = it.displayItem.catalyst == 1 and it.displayItem.catalystQuality == 20
    and e.catalyst.qualityShown == true and e.catalyst.qualityText == "20"
pob_itemsDisplaySetControl("displayItemCatalystQualityEdit", "10")
res.catalystQuality = it.displayItem.catalystQuality == 10
-- Cluster jewel (crafted Large).
pob_itemsEditTextSave("Rarity: Rare\nCF Cluster\nLarge Cluster Jewel\nCrafted: true\n", 3, false)
e = pob_itemsGetLists().display.editor
local cj = it.displayItem.clusterJewel
res.clusterShown = e.cluster.shown == true and #e.cluster.list > 1 and e.cluster.count == cj.minNodes
pob_itemsDisplaySetControl("displayItemClusterJewelSkill", 2)
local skillId = it.controls.displayItemClusterJewelSkill.list[2].skillId
res.clusterSkill = it.displayItem.clusterJewelSkill == skillId
    and it.displayItem.enchantModLines[#it.displayItem.enchantModLines].line == table.concat(cj.skills[skillId].enchant, "\n")
pob_itemsDisplaySetControl("displayItemClusterJewelNodeCount", 1)
res.clusterNodes = it.displayItem.clusterJewelNodeCount == cj.maxNodes
    and it.displayItem.enchantModLines[1].line == "Adds " .. cj.maxNodes .. " Passive Skills"
-- Guard rails.
res.unknownControlRefused = not pob_itemsDisplaySetControl("displayItemAffix1", 1).ok
pob_itemsEditTextSave("Rarity: Unique\nCF Unique\nLeather Belt\n", 4, false)
res.uniqueNoInfluence = pob_itemsGetLists().display.editor.influence.shown == false
```

Register in `app/src/selftest_checks.h` after the `items-editor` line, with a comment naming Part 6.3 item 2:
`if (!pob_run_lua_check(engine, "pob_selftestItemsCraft", "items-craft")) return false;`

- [ ] **Step 2: Run the gate; verify it fails**

Run: the Windows gate (rebuild needed for the header).
Expected: `pob-selftest` EXIT=1 with `items-craft ok = false` and `influenceShown=false` (or an error naming `pob_itemsDisplaySetControl` as nil).

- [ ] **Step 3: Implement `ctlKind`, `ctlRecord`, `setCtl`, `SECTION_CONTROLS`, `pob_itemsDisplaySetControl`, and the `editorRecord` fields**

Reuse `shownCtl` / `dropLabels`; read every value back from the live control after `SetDisplayItem` synced it (do not recompute from the item). `cluster.val` / `divCount` come from `displayItemClusterJewelNodeCount`.

- [ ] **Step 4: Run the gate; verify it passes**

Expected: both binaries EXIT=0; `items-craft ok = true`; `items-slots`, `items-lists`, `items-editor` still ok.

- [ ] **Step 5: Commit**

```bash
git add app/lua/pob_items.lua app/src/selftest_checks.h
git commit -m "feat(items): 6.3.2 editor sections — influence, quality, catalyst, cluster (bridge)"
```

---

### Task 2: Craft-session capture engine + Apply Enchantment (bridge)

**Files:**
- Modify: `app/lua/pob_items.lua` (new block after Task 1's setter; selftest)

**Interfaces:**
- Consumes: Task 1 `ctlKind`, `ctlRecord`, `setCtl`; `tipLines(fn)`; `displayEdited(it)`.
- Produces:
  - `local craft` — nil or `{ kind, slot, item, controls, frame = { title, width, height } }`; `item` is the `it.displayItem` the popup was opened on.
  - `local CRAFT_OPENERS = { enchant = "EnchantDisplayItem", anoint = "AnointDisplayItem", corrupt = "CorruptDisplayItem", implicit = "AddImplicitToDisplayItem" }` — enchant/anoint take `slot`; corrupt takes `"Corrupted"`; implicit takes nothing.
  - `local function craftLive(it) -> boolean` — `craft ~= nil and it.displayItem ~= nil and craft.item == it.displayItem`; when false, sets `craft = nil`.
  - `local function craftCtl(name) -> ctl|nil` — `"a"` → `craft.controls.a`; `"a.b"` → `craft.controls.a.controls.b` (NotableDB's sort/search/searchMode).
  - `local function withFrame(fn) -> ok, closed, err` — pushes `craft.frame` as `main.popups[1]` for the call (legacy callbacks write `main.popups[1].height`; `NotableDBControl:AddValueTooltip` checks its title), pcalls `fn`, and reports `closed = true` when legacy's `main:ClosePopup()` removed the frame; pops the frame if still there.
  - `function pob_itemsCraftOpen(kind: string, slot: number|nil) -> state` — capture: save `main.OpenPopup`, replace it with a function storing `title, width, height, controls` (no push), call `it[CRAFT_OPENERS[kind]](it, arg)` under pcall, restore `main.OpenPopup` in all cases. Refuses unknown kinds, no display item, and a hidden matching editor button (`craftButtons`).
  - `function pob_itemsCraftState() -> { open=false } | { open=true, kind, slot, title, width, height, controls = { [name] = ctlRecord } }` — `height` is read live from `craft.frame.height`.
  - `function pob_itemsCraftSet(name: string, value) -> state` (with `ok`) — `setCtl` inside `withFrame`; refuses when `not craftLive(it)`.
  - `function pob_itemsCraftClick(name: string) -> { ok, closed, _emit = closed and {"items"} or nil }` — calls the button's `onClick` inside `withFrame`; on `closed` sets `craft = nil`.
  - `function pob_itemsCraftTooltip(name: string, index: number|nil) -> { lines }` — drop row: `ctl.tooltipFunc(tip, "HOVER", index, ctl.list[index])`; button: `ctl.tooltipFunc(tip)`; list row: `ctl:AddValueTooltip(tip, index, ctl.list[index])`; all through `tipLines` inside `withFrame`.
  - `function pob_itemsCraftClose() -> { ok = true }` — drops the session (legacy Cancel only closes).

- [ ] **Step 1: Add the failing enchant flags to `pob_selftestItemsCraft`**

```lua
pob_itemsEditTextSave("Rarity: Rare\nCF Enchant\nIron Hat\n", 3, false)
res.enchantButton = pob_itemsGetLists().display.editor.craftButtons.enchant1 == true
local st = pob_itemsCraftOpen("enchant", 1)
res.enchantOpened = st.open == true and st.title == "Enchant Item"
    and st.controls.enchantment.type == "drop" and #st.controls.enchantment.list > 0
    and st.controls.save.label == "Enchant"
local label = st.controls.enchantment.list[1]
res.enchantTooltip = linesText(pob_itemsCraftTooltip("enchantment", 1).lines):find((label:match("^([^/]+)/") or label), 1, true) ~= nil
pob_itemsCraftSet("enchantment", 1)
local click = pob_itemsCraftClick("save")
res.enchantApplied = click.ok and click.closed and pob_itemsCraftState().open == false
    and it.displayItem.enchantModLines[1].line == (label:match("^([^/]+)/") or label)
pob_itemsCraftOpen("enchant", 1)
pob_itemsCraftClick("remove")
res.enchantRemoved = #it.displayItem.enchantModLines == 0
-- Stale session (Review Focus 1).
pob_itemsCraftOpen("enchant", 1)
pob_itemsCloseDisplayItem()
res.staleRefused = not pob_itemsCraftClick("save").ok and it.displayItem == nil
    and pob_itemsCraftState().open == false
res.badKindRefused = pob_itemsCraftOpen("nope", 1).open == false
```

- [ ] **Step 2: Run `pob-selftest`; verify it fails**

Expected: EXIT=1, `enchantButton=true`, `enchantOpened=false` (or an error naming `pob_itemsCraftOpen`).

- [ ] **Step 3: Implement the engine and the five `pob_itemsCraft*` functions**

Restore `main.OpenPopup` even when the opener errors. Set `craft = nil` in `pob_itemsCloseDisplayItem` and `pob_itemsAddDisplayItem`; any other change of display item (undo, a new paste) is caught by `craftLive`. Map kinds to the editor buttons for the open guard: enchant slot 1/2 → `enchant1/2`, anoint slot n → `anoint<n>`, corrupt → `corrupt`, implicit → `addImplicit`.

- [ ] **Step 4: Run the gate; verify it passes**

Expected: both EXIT=0, `items-craft ok = true`.

- [ ] **Step 5: Prove fail-when-removed**

Temporarily make `withFrame` skip the frame push; run `pob-selftest`. Expected: `enchantApplied=false` (legacy `main:ClosePopup()` then removes nothing, so `closed` is never reported). Restore; re-run → EXIT=0. Record the result for the session log.

- [ ] **Step 6: Commit**

```bash
git add app/lua/pob_items.lua
git commit -m "feat(items): 6.3.2 craft-session capture engine + Apply Enchantment (bridge)"
```

---

### Task 3: Anoint (bridge) — notable list pump

**Files:**
- Modify: `app/lua/pob_items.lua` (`pob_itemsDBStep` ~987-1018 refactor; craft block; selftest)

**Interfaces:**
- Consumes: Task 2 engine (`craft`, `craftLive`, `craftCtl`, `withFrame`); `dbBuilding(db, it)`.
- Produces:
  - `local function stepListBuilder(ctl, it) -> { running, finished, text, error }` — the list-build half of `pob_itemsDBStep` (restart on `outputRevision` / `listBuildFlag`, resume `ListBuilder` once, clear on dead/error). `pob_itemsDBStep` keeps its loader half and calls this.
  - `function pob_itemsCraftStep() -> { running, finished, text, error }` — `stepListBuilder(craft.controls.notableDB, it)` inside `withFrame`; `{ running = false }` when no anoint session.
  - `ctlRecord` for kind `"list"`: `{ type="list", building, text = ctl.defaultText, sel = ctl.selIndex, rows = { label = ctl:GetRowValue(1, i, node) } }`, rows only when not building.

- [ ] **Step 1: Add the failing anoint flags**

```lua
local function pump(max)
    for _ = 1, max do if not pob_itemsCraftStep().running then return true end end
    return false
end
pob_itemsEditTextSave("Rarity: Rare\nCF Amulet\nGold Amulet\n", 3, false)
local st = pob_itemsCraftOpen("anoint", 1)
res.anointOpened = st.open == true and st.title == "Anoint Item" and st.controls.notableDB.type == "list"
res.anointListed = pump(5000) and #pob_itemsCraftState().controls.notableDB.rows > 0
local node = craft.controls.notableDB.list[1]
pob_itemsCraftSet("notableDB", 1)
res.anointLabel = pob_itemsCraftState().controls.save.label == "Anoint " .. node.dn
res.anointTooltip = linesText(pob_itemsCraftTooltip("notableDB", 1).lines):find(node.dn, 1, true) ~= nil
pob_itemsCraftClick("save")
res.anointApplied = it.displayItem.enchantModLines[1].line == "Allocates " .. node.dn
-- Re-open with no selection: "Remove <name>" (Review Focus 3).
pob_itemsCraftOpen("anoint", 1); pump(5000)
res.anointRemove = pob_itemsCraftState().controls.save.label == "Remove " .. node.dn
pob_itemsCraftClick("save")
res.anointRemove = res.anointRemove and #it.displayItem.enchantModLines == 0
-- Search filter narrows the list.
pob_itemsCraftOpen("anoint", 1); pump(5000)
local allRows = #pob_itemsCraftState().controls.notableDB.rows
pob_itemsCraftSet("notableDB.search", node.dn); pump(5000)
local rows = pob_itemsCraftState().controls.notableDB.rows
res.anointSearch = #rows >= 1 and #rows < allRows
pob_itemsCraftClose()
res.anointHiddenOnBelt = (function()
    pob_itemsEditTextSave("Rarity: Rare\nCF Belt2\nLeather Belt\n", 3, false)
    return pob_itemsCraftOpen("anoint", 1).open == false
end)()
```

- [ ] **Step 2: Run `pob-selftest`; verify it fails**

Expected: EXIT=1, `anointOpened=true`, `anointListed=false` (no pump yet).

- [ ] **Step 3: Implement `stepListBuilder`, refactor `pob_itemsDBStep` onto it, add `pob_itemsCraftStep` and the list record**

- [ ] **Step 4: Run the gate; verify it passes**

Expected: EXIT=0; `items-lists` still ok (the DB pump refactor must not change its 44 flags).

- [ ] **Step 5: Prove fail-when-removed**

Temporarily drop the frame push in `withFrame`. Expected: `anointTooltip=false` (`AddValueTooltip` clears the tooltip unless the open popup's title is "Anoint Item"). Restore.

- [ ] **Step 6: Commit**

```bash
git add app/lua/pob_items.lua
git commit -m "feat(items): 6.3.2 Anoint via the live NotableDB list + shared list pump"
```

---

### Task 4: Corrupt and Add Implicit (bridge coverage + fixes)

**Files:**
- Modify: `app/lua/pob_items.lua` (selftest; engine fixes only if a flag exposes one)

**Interfaces:**
- Consumes: Task 2 engine. No new bridge functions: these popups are driven by name (`implicits`, `rolls`, `source`, `sort`, `implicit1..4`, `rollRangeSlider<i>`, `rollRangeValue<i>`, `rollRangeLabel<i>`, `save`, `close`; `source`, `sort`, `modGroupSelect`, `modSelect`, `custom`, `save`, `close`).
- Produces: nothing new for later tasks beyond these control names.

- [ ] **Step 1: Add the failing corrupt + implicit flags**

```lua
-- Corrupt a rare belt.
pob_itemsEditTextSave("Rarity: Rare\nCF Belt\nLeather Belt\n", 3, false)
local st = pob_itemsCraftOpen("corrupt", nil)
res.corruptOpened = st.open and st.title == "Corrupted Item" and st.controls.implicit1.shown
    and st.controls.implicit2.shown and not st.controls.implicit3.shown and not st.controls.implicits.shown
pob_itemsCraftSet("implicit1", 2)
local g = craft.controls.implicit1.list[2].mod.group
local clash = false
for _, row in ipairs(craft.controls.implicit2.list) do if row.mod and row.mod.group == g then clash = true end end
res.corruptExcludesGroup = not clash                                   -- Review Focus 5
local modLine = craft.controls.implicit1.list[2].mod[1]
pob_itemsCraftClick("save")
res.corruptApplied = it.displayItem.corrupted == true
    and it.displayItem.implicitModLines[1].line:find(modLine, 1, true) ~= nil
-- Scourge: 3 dropdowns for a non-unique, popup grows (writes main.popups[1].height).
pob_itemsEditTextSave("Rarity: Rare\nCF Belt3\nLeather Belt\n", 3, false)
pob_itemsCraftOpen("corrupt", nil)
st = pob_itemsCraftSet("source", 2)
res.scourgeSource = st.ok and st.controls.implicit3.shown and not st.controls.implicit4.shown
    and st.height == 103 + 20 * 3
pob_itemsCraftClose()
-- Unique Roll Ranges.
pob_itemsEditTextSave("Rarity: Unique\nCF Roll\nLeather Belt\nImplicits: 1\n+(25-40) to maximum Life\n+(40-50) to maximum Life\n", 4, false)
st = pob_itemsCraftOpen("corrupt", nil)
res.rollButtons = st.controls.implicits.shown and st.controls.rolls.shown
pob_itemsCraftClick("rolls")
pob_itemsCraftSet("rollRangeSlider1", 1)
res.rollLabel = pob_itemsCraftState().controls.rollRangeValue1.label == "^71.22"
pob_itemsCraftClick("save")
res.rollApplied = it.displayItem.corrupted == true
    and math.abs((it.displayItem.explicitModLines[1].corruptedRange or 0) - 1.22) < 1e-9  -- 0.78 + 0.44 is not exactly 1.22 in floating point
-- Add Implicit: Exarch replaces (Review Focus 4), Custom appends, blank adds nothing.
pob_itemsEditTextSave("Rarity: Rare\nCF Helm2\nIron Hat\nSearing Exarch Item\n", 3, false)
st = pob_itemsCraftOpen("implicit", nil)
res.implicitSources = table.concat(st.controls.source.list, ",") == "Searing Exarch,Delve,Custom"
local function exarchCount()
    local n = 0
    for _, l in ipairs(it.displayItem.implicitModLines) do if l.exarch then n = n + 1 end end
    return n
end
pob_itemsCraftClick("save")
local n1 = exarchCount()
pob_itemsCraftOpen("implicit", nil); pob_itemsCraftClick("save")
res.eldritchReplaces = n1 > 0 and exarchCount() == n1
pob_itemsCraftOpen("implicit", nil)
pob_itemsCraftSet("source", 3); pob_itemsCraftSet("custom", "+10 to Strength")
local before = #it.displayItem.implicitModLines
pob_itemsCraftClick("save")
local last = it.displayItem.implicitModLines[#it.displayItem.implicitModLines]
res.customImplicit = #it.displayItem.implicitModLines == before + 1 and last.line == "+10 to Strength" and last.custom == true
pob_itemsCraftOpen("implicit", nil)
pob_itemsCraftSet("source", 3); pob_itemsCraftSet("custom", "   ")
before = #it.displayItem.implicitModLines
pob_itemsCraftClick("save")
res.blankCustomIgnored = #it.displayItem.implicitModLines == before
```

- [ ] **Step 2: Run `pob-selftest`; note which flags fail**

Expected: EXIT=0 or EXIT=1. Any false flag is a real engine gap (most likely `scourgeSource` or `rollLabel`); fix it in the engine, not the test.

- [ ] **Step 3: Fix the engine gaps the flags exposed (if any)**

- [ ] **Step 4: Run the gate; verify it passes**

Expected: both EXIT=0.

- [ ] **Step 5: Prove fail-when-removed**

Temporarily drop the frame push. Expected: `scourgeSource=false` (the Scourge selFunc errors on `main.popups[1].height`). Restore.

- [ ] **Step 6: Commit**

```bash
git add app/lua/pob_items.lua
git commit -m "test(items): 6.3.2 Corrupt (incl. Scourge, Roll Ranges) + Add Implicit through the craft engine"
```

---

### Task 5: Searchable dropdown (QML)

**Files:**
- Modify: `app/qml/components/DropDownControl.qml`

**Interfaces:**
- Consumes: `components/SearchHost.qml` matching rules (word-order, caseless).
- Produces: `property bool searchable: false`. While the list is open and `searchable`, typed characters build a filter string (Backspace edits it, Escape clears then closes); only matching rows are listed, with match ranges highlighted; picking a filtered row emits `selected(originalIndex)`. With `searchable: false` behavior is unchanged (type-ahead stays).

Qt skill check: list the `qt-development-skills` skills now; use its QML coding skill for this task and Tasks 6-7 if loaded.

- [ ] **Step 1: Implement `searchable`** (filtered index → original index mapping kept in one array; the closed control still shows the original `currentIndex` label).
- [ ] **Step 2: Build and run the gate**

Expected: EXIT=0, and no new QML warnings in `pob-qt --headless` output (Tree/Skills/Items dropdowns are unaffected because the default is false).

- [ ] **Step 3: Commit**

```bash
git add app/qml/components/DropDownControl.qml
git commit -m "feat(qml): opt-in searchable DropDownControl (legacy type-to-filter)"
```

---

### Task 6: Editor sections in the Items view (QML)

**Files:**
- Modify: `app/qml/views/ItemsView.qml` (`editCol`, after the socket section, before the tooltip)

**Interfaces:**
- Consumes: Task 1 `editor.craftButtons / influence / quality / catalyst / cluster`; `pob_itemsDisplaySetControl(name, value)`.
- Produces: button handlers that call `<popup>.openCraft(kind, slot)` (popups arrive in Task 7; wire to placeholder ids now, real instances in Task 7).

Legacy layout to match (ItemsTab.lua:474-673): craft row 28 px (Apply Enchantment… 160, Apply Enchantment 2… 160, Anoint… / Anoint 2-4… 100 each, Corrupt… 100, Add Implicit… 120, 8 apart, hidden ones collapse; wrap with a `Flow` if wider than the pane); influence row 28 px (two 100-wide dropdowns, 8 apart); quality row 28 px (`^7Quality:` label + 60-wide numeric edit, commit on Enter / focus-out); catalyst row 28 px (250-wide dropdown + 60-wide edit); cluster block 52 px (300-wide skill dropdown; below it `^7Added Passives:` + 150-wide `Slider` with `divCount`).

- [ ] **Step 1: Add the sections**, each `visible` from its record's `shown`, values pushed imperatively after each refresh (EditControl text, Slider value).
- [ ] **Step 2: Build, run the gate, run a capture**

Capture: scratch host file (as in the handoff's recipe) that loads `spec/TestBuilds/3.13/OccVortex.lua` and opens a crafted rare ring via `pob_itemsEditTextSave("Rarity: Rare\nCap Ring\nGold Ring\nCrafted: true\n", 3, false)`; run `pob-qt.exe --capture <scratch dir> --src … --runtime … --host <scratch host>`. Expected: Items capture shows Anoint is absent (ring), influence pair, catalyst dropdown; no QML errors in the log.

- [ ] **Step 3: Commit**

```bash
git add app/qml/views/ItemsView.qml
git commit -m "feat(items): 6.3.2 editor sections — craft buttons, influence, quality, catalyst, cluster (QML)"
```

---

### Task 7: Craft popups (QML)

**Files:**
- Create: `app/qml/components/CraftPopupBase.qml`, `CraftEnchantPopup.qml`, `CraftAnointPopup.qml`, `CraftCorruptPopup.qml`, `CraftImplicitPopup.qml`
- Modify: `app/qml/qml.qrc`, `app/qml/views/ItemsView.qml` (instances + button wiring)

**Interfaces:**
- Consumes: Task 2-3 `pob_itemsCraftOpen / State / Set / Click / Tooltip / Close / Step`; Task 5 `searchable`; `StatDiff.fillFromLines(tt, lines)`.
- Produces: `CraftPopupBase` (extends `PopupBase`):
  - `property var st` — last craft state
  - `function openCraft(kind, slot)` — invoke open; refuse quietly when `!st.open`; set `title`, size from `st.width/height`; `open()`
  - `function rec(name) -> object` (`st.controls[name] || {}`)
  - `function set(name, value)` / `function click(name)` — invoke, then refresh `st`; `click` calls `close()` when `closed`
  - `function fillTip(tt, name, index)`
  - `onRejected` → `pob_itemsCraftClose`

Layouts follow legacy sizes: Enchant 605×130 (Skill + "All skills:" checkbox, Source, Sort by, Enchantment 495 wide; Enchant / Remove / Cancel); Anoint 380×448 (sort dropdown, search + mode, 360×360 notable list with row tooltips and a job-scoped Timer calling `pob_itemsCraftStep` until `running` is false, showing `text` while building; save button label from state; Cancel); Corrupt 605×`st.height` (Implicits / Roll Ranges buttons for uniques, Source, Sort by, Implicit #1-4, roll rows = value label + 80-wide slider + wrapped line label split into one `Label` per line, "This Items Implicits Cannot Be Changed" label; Corrupt / Cancel); Add Implicit 710×130 (Source, Sort by, Type, Modifier, Custom edit; Add / Cancel). Every dropdown in these popups sets `searchable: true`; row tooltips use a `{label, i}` model so the 1-based index reaches `fillTip`.

- [ ] **Step 1: Create the five components, register them in `qml.qrc`, add instances in `ItemsView.qml`, wire Task 6's buttons**
- [ ] **Step 2: Build and run the gate**

Expected: both EXIT=0; no QML errors.

- [ ] **Step 3: Visual check of each popup**

Run `pob-qt.exe` with the Task 6 scratch host file (swap the fixture per popup: Iron Hat for Enchant / Corrupt / Add Implicit, Gold Amulet for Anoint, the unique belt for Roll Ranges). Open each popup, pick a row, apply, and confirm the item tooltip changes. Save one screenshot per popup in the scratch dir. If no computer-use tools are available, list exactly what was NOT eyeballed (as the earlier session logs do).

- [ ] **Step 4: Commit**

```bash
git add app/qml/components/Craft*.qml app/qml/qml.qrc app/qml/views/ItemsView.qml
git commit -m "feat(items): 6.3.2 craft popups — Enchant, Anoint, Corrupt, Add Implicit (QML)"
```

---

### Task 8: Verify, review, document, push

**Files:**
- Modify: `port-plan/phases/PHASE-6-items-tab.md`, `port-plan/STATUS.md` (lines 12-13 stop point), `port-plan/handoff/HANDOFF-phase6.md` ("Where things stand")

- [ ] **Step 1: Full gate**

Expected: `pob-selftest` EXIT=0 and `pob-qt --headless` EXIT=0, with `items-slots`, `items-lists`, `items-editor`, `items-craft` all ok.

- [ ] **Step 2: Lint the QML**

Run: `/c/msys64/mingw64/bin/qmllint.exe -I app/qml app/qml/components/Craft*.qml app/qml/components/DropDownControl.qml app/qml/views/ItemsView.qml`
Expected: no warnings beyond those `qmllint` already reports on `app/qml/components/ItemTextPopup.qml` (unqualified context properties like `luaEngine` / `theme`).

- [ ] **Step 3: Review**

Run `/code-review high 311f5e9...cloud/phase-6`, plus the Qt QML review skill on the changed `.qml` files if the plugin is loaded. Fix real findings, re-run Step 1, commit fixes.

- [ ] **Step 4: Tick and log**

Tick Part 6.3 item 2 in the phase file; add "Session log — <date> (Part 6.3, item 2)" with: bridge summary (capture engine, `pob_itemsDisplaySetControl`, list pump refactor), `items-craft` flag count, the three fail-when-removed results, what was and was not eyeballed, and **Documented differences**: empty numeric field → 0; popups are QML dialogs over the captured legacy popup controls; searchable dropdown filter semantics; the craft row wraps when wider than the pane. Update STATUS.md lines 12-13 and the handoff table: next = 6.3 item 3 (affix dropdowns + custom / crucible popups).

- [ ] **Step 5: Commit and push**

```bash
git add port-plan/
git commit -m "docs(port-plan): Phase 6 Part 6.3 item 2 done — craft popups"
git push fork cloud/phase-6
```

Expected: push succeeds; draft PR #7 updates.
