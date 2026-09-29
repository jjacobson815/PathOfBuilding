# Items tab recon (legacy -> Qt/QML), read-only

Files: `src/Classes/ItemsTab.lua` (IT), `ItemSlotControl.lua` (ISC), `ItemListControl.lua` (ILC), `ItemDBControl.lua` (IDB),
`SharedItemListControl.lua` (SIL), `ItemSetListControl.lua` (ISL), `SharedItemSetListControl.lua` (SISL), `Build.lua`/`Main.lua`.
Host: `app/lua/pob_host.lua` (PH), `app/lua/pob_skills.lua` (PS). All line numbers are current HEAD.
The code-review-graph MCP tools were not exposed in this session, so this was done with Read/Grep.

## 0. Host conventions to follow (from PS + PH)

- Bridge fns are top-level globals named `pob_*`. `LuaEngine::callGlobal` does one `lua_getglobal`, so no dotted names. New module goes in `app/lua/pob_items.lua`, loaded by `require("pob_items")` next to `require("pob_skills")` (PH:6477). Installed by the same `*.lua` rule.
- `LuaEngine::invoke` (app/src/LuaEngine.cpp:1310) refuses names not starting `pob_` and any `pob_selftest*`. It only raises signals when the return is a table with `_emit = {...}`.
  - Valid emit names: `build`, `tree`, `items`, `skills`, `config`, `calcs`. It fires them in that fixed order.
  - Skills uses `EMIT = {"build","skills","calcs"}`. Items should use `{"build","items","calcs"}`, adding `"tree"` for jewel socket / cluster changes.
- PS skeleton to copy (PS:30-56):
  - `ctx()` returns `bm, tab` from `main.modes.BUILD`.
  - `done(extra)` calls `pob_recalculate()`, defaults `ok=true`, and sets `_emit`.
  - `fail(msg)` returns `{ok=false,error=msg}`.
  - Index-based addressing: QML sends 1-based indices or ids and re-reads state after each call, because undo/redo REPLACES tables. `RestoreUndoState` (IT:4754) swaps `self.items` and `self.itemSets`.
- `pob_recalculate()` (PH:1032) is idempotent. It is a no-op unless `bm.buildFlag`, then does wipeGlobalCache, outputRevision++, buildFlag=false, `calcsTab:BuildOutput()`, `RefreshStatList`. Every mutation must set `buildFlag = true` (legacy code does this itself in most paths, see per-part notes), then call `pob_recalculate()`, then `_emit`.
- Mutation order legacy uses after user edits: `PopulateSlots()` -> `AddUndoState()` (UndoHandler.lua:24, also sets `modFlag`) -> `build.buildFlag = true`. `SyncLoadouts()` is called after any item-set add/rename/delete/switch (Build.lua:763).
- Tooltips: PS `tipLines(fn)` (PS:59) builds a real `new("Tooltip")`, runs `fn(tip)` in pcall, and marshals `tip.lines` as `{size,text,center}` or `{sep=true,size}`. Reuse it verbatim (copy or export from a shared helper) for every Items tooltip. Slot dropdown tooltip pattern is `pob_skillsSlotTooltip` (PS:593): call the control's own `tooltipFunc(tip, mode, i, value)`.
  - Tooltip also carries non-line header state: `tooltip.tooltipHeader` (=rarity), `.foilType`, `.color`, `.influenceHeader1/2` (set by `SetTooltipHeaderInfluence` IT:3764), `.childTooltips`. Return these next to `lines` if the QML tooltip wants the rarity frame / influence icons.
  - Tooltip:CheckForUpdate keys on `outputRevision` (see ISC:53). A fresh `new("Tooltip")` per request avoids that cache.
- Input stubs in PH: `GetCursorPos()` returns 0,0 (PH:176). `IsKeyDown` forwards to `pob.isKeyDown` (PH:179). `Copy`/`Paste` forward to `pob.copy`/`pob.paste`. `DrawStringCursorIndex` and `DrawStringWidth` are stubbed (PH:85-88). `GetTime()` is `pob.getTime()`. `PCall` exists (PH:219).
  - SHIFT and CTRL semantics in legacy click handlers go through `IsKeyDown`. The host must NOT rely on it, so take explicit `useSecondSlot` and `ctrl` booleans in bridge args and replicate the branch (see 6.2).
- Existing Items bridge (PH:726-858), all top-level globals:
  - `pob_getItems` (753) returns id/name/baseName/type/rarity/quality/level/modLines/isEquipped/slotName/socketCount, ordered by `itemOrderList`.
  - `pob_getItemSlots` (779) lists only NON-empty non-jewel slots.
  - `pob_getJewelSockets` (796) iterates `pairs(it.sockets)`, so its order is non-deterministic.
  - `pob_addItemFromRaw(raw)` (813) uses CreateDisplayItemFromRaw + AddItem(noAutoEquip=true) + PopulateSlots + pob_recalculate. Side effect: it leaves `it.displayItem` pointing at the added item and never clears it. The editor phase must change this.
  - `pob_deleteItem(id)` (829) uses DeleteItem + PopulateSlots + recalc.
- `pob_compareOverride(override)` (PH:1350-1423) is the ONLY comparison entry.
  - Vocabulary: `addNodes`/`removeNodes` (id lists), `repSlotName` + `repItemId` (item in build) or `repItemRaw` (raw text), `toggleFlask`/`toggleTincture` (item id), `useFullDPS`.
  - `repItemRaw` deliberately uses `new("Item", raw)` and NOT `CreateDisplayItemFromRaw`, because the latter runs `CopyAnointsAndEldritchImplicits` and clobbers `displayItem`. Keep that rule for every compare hover.
  - It does NOT support `override.spec` (jewel-radius cloned spec). It returns structured `{stat,label,diff,diffStr,positive,percent}` rows from `pob_diffStatList`, not tooltip lines.
  - Use `AddItemTooltip` for the legacy-styled text and `pob_compareOverride` for structured diff rows (see 6.4).
- Selftest convention: `pob_selftestX()` returns `{ok=bool,...}`, registered in `app/src/selftest_checks.h` via `pob_run_lua_check(engine, "pob_selftestSkillsList", "skills-list")` (lines ~947-956). Additive, runs before "SELFTEST PASSED". Selftests must clean up (see PH:841 `pob_selftestItems` deletes its item).

## 6.1 Item sets, slot list, ItemSlotControl, spec selector

### Data model (IT ctor 79-1027)
- `itemsTab.items` is `{[id]=Item}`. `itemOrderList` is an array of ids (display order; ILC binds to it directly, ILC:10).
- `itemSets` is `{[setId]=set}` and `itemSetOrderList` is an array of setIds (IT:1020-1021). Set shape: `{id=, title=nil|str, useSecondWeaponSet=bool, [slotName]={selItemId=0, active=bool|nil, pbURL=str}, [nodeId]={pbURL}}`. Only non-socket slots get entries (IT:1373-1377). Jewel sockets store the item in `build.spec.jewels[nodeId]`, NOT the set.
- `activeItemSetId`, `activeItemSet`.
- Live per-slot state lives on the ItemSlotControl (`slot.selItemId`, `slot.active`). `activeItemSet[slotName].selItemId` is kept in sync by `SetSelItemId` (ISC:70). Inactive sets are only written back at switch time (IT:1395-1396).
- The CRITICAL quirk: switching sets copies the live slot into `prevSet` before loading the new set (IT:1391-1405).

### Set operations (all live methods on itemsTab; DeleteItemSet/RenameItemSet do NOT exist as methods)
- `NewItemSet(id?)` (IT:1365) allocates the smallest free id if nil, creates empty slot entries, and registers in `itemSets` only. It does NOT append to `itemSetOrderList` and does NOT set a title. Callers do that.
  - New: ISL:38-41 `NewItemSet()` -> rename popup -> on Save `title=..; modFlag; t_insert(list,id); AddUndoState(); build:SyncLoadouts()`. The bridge must replicate: create, set title, insert in order list, AddUndoState, SyncLoadouts.
- `SetActiveItemSet(id)` (IT:1383) falls back to `itemSetOrderList[1]`. It writes back prevSet, loads slots, sets `build.buildFlag=true`, calls `PopulateSlots()`, then `build:SyncLoadouts()`. It does NOT AddUndoState (caller does: IT:98-99, ISL:114-115).
  - It also does not touch `weaponSwap` buttons, since they are derived from `activeItemSet.useSecondWeaponSet`.
- Copy set: inline at ISL:14-22. `newSet = copyTable(itemSets[selValue])`, first free id, insert into `itemSets`, then RenameSet(addOnName=true), which appends to the order list. Lift it.
- Rename (ISL:44-70): `itemSet.title=..; itemsTab.modFlag=true; AddUndoState(); SyncLoadouts()`. Title `nil` displays as "Default".
- Delete (ISL:119-134): requires `#list>1`. `t_remove(list,index); itemSets[id]=nil`; if it was active then `SetActiveItemSet(list[max(1,index-1)])`; then `AddUndoState(); SyncLoadouts()`. Items are NOT deleted.
- Reorder: `OnOrderChange` only sets `modFlag` (ISL:108). Same as `pob_skillsMoveSet` (PS:387).
- Set tooltip: `AddItemSetTooltip(tooltip,set)` (IT:3753) lists `^7label: <rarity color>item.name` per non-socket slot.
- Shared item sets (SISL, `main.sharedItemSetList`, entries `{title, slots={[slotName]=Item}}`) and shared items (SIL, `main.sharedItemList`, entries are Item objects) are cross-build state in Main. Drag-drop logic: ISL:93-106 (shared -> build) and SISL:80-100 (build -> shared). Lift those bodies as `pob_itemsShareSet(index)` / `pob_itemsUnshareSet(sharedIndex)`. The reader must use `value.slots` items' `.raw`.
- EquipItemInSet(item,setId) (IT:1412) is used by the build loadout dropdown (Build.lua:556). It reads `IsKeyDown("SHIFT")` at line 1424, so pass a flag or wrap with a fake IsKeyDown if needed. If `item.id` is unknown it creates `new("Item", item.raw)` and adds it with noAutoEquip.

### Weapon-set buttons (IT:222-262)
- `weaponSwap1` ("I") when `useSecondWeaponSet` is true: set it false, `AddUndoState`, `build.buildFlag=true`, then if main socket group's slot has `weaponSet==2`, move `build.mainSocketGroup` to the first group whose slot has `weaponSet==1`. `weaponSwap2` is the mirror.
- Lift verbatim as `pob_itemsSetWeaponSet(n)`. Note it reads `self.slots[group.slot].weaponSet`, so the slot must exist. Skills' `group.slot` can be "Weapon 1 Swap" etc.
- `useSecondWeaponSet` is per item set and saved on the set (IT:1199) and on the root `<Items>` attr (IT:1145).

### Slot list construction (IT ctor 127-220; DO NOT rebuild; read `orderedSlots`)
- `baseSlots` (IT:35): Weapon 1, Weapon 2, Helmet, Body Armour, Gloves, Boots, Amulet, Ring 1/2/3, Belt, Graft 1/2, Flask 1-5.
- Weapon 1/2 slots get `weaponSet=1`. `shown()` is `not useSecondWeaponSet`. Each also gets a "<name> Swap" slot with `weaponSet=2`, plus 6 "<name> Swap Abyssal Socket i" slots with `parentSlot=swapSlot`.
- Abyssal sockets: for Weapon 1, Weapon 2, Helmet, Gloves, Body Armour, Boots, Belt, 6 slots "<name> Abyssal Socket i" (label "Abyssal #i"), `parentSlot=slot`, stored in `slot.abyssalSocketList[i]`. `abyssal.inactive = i > parent.selItem.abyssalSocketCount` (set in `Populate`, ISC:104-111), and inactive sockets are force-cleared with `SetSelItemId(0)`.
- Visibility predicates, all closures on the slot (`slot.shown()`; callable from a bridge):
  - Graft 1/2: `build.spec.treeVersion:find("3_27")` (IT:166).
  - Ring 3: `calcsTab.mainEnv.modDB:Flag(nil,"AdditionalRingSlot")` (IT:170).
  - Weapon/swap/abyssal: `activeItemSet.useSecondWeaponSet` vs `weaponSet`.
  - Default `ISC.shown = not self.inactive` (ISC:24). `ISC:IsShown()` also ANDs parent visibility, and for Control anchors this is fine headless.
- Jewel sockets: one `ItemSlotControl` per `build.latestTree.nodes[type=="Socket"]`, sorted by id, named `"Jewel <nodeId>"`, stored in `itemsTab.sockets[nodeId]` and `slots`, label "Socket" (IT:206-220). `UpdateSockets()` (IT:1451) sets `slot.inactive` from `build.spec.allocNodes[nodeId]`, sorts active ones by id, and relabels `"Socket #n"`. It is called from `Draw` (IT:1343) and `AddItemTooltip` (IT:4616), so the bridge MUST call `it:UpdateSockets()` before reading socket state (Draw never runs). Also `PopulateSlots()` after a tree/spec change (TreeTab.lua:554, 597 does this).
- Cluster jewel sockets: expansion sockets have `node.expansionJewel` and `node.charmSocket`. Validity is in `IsItemValidForSlot` (below). Cluster graphs are rebuilt by `spec:BuildClusterJewelGraphs()` on `SetSelItemId` (ISC:66) when the id changes.
- `slot.slotNum` = trailing digit (ISC:31). `slot.label` = slotLabel or slotName. `slot.nodeId` marks a socket. `flask` slots carry a `controls.activate` checkbox (ISC:32-43) storing `slot.active` and `activeItemSet[slot].active`.

### ItemSlotControl (ISC) API for the bridge
- Fields: `slotName`, `label`, `nodeId`, `selItemId`, `items` (array parallel to dropdown rows; `items[1]==0` meaning None), `list` (labels `colorCodes[rarity]..name`), `selIndex`, `active`, `inactive`, `weaponSet`, `parentSlot`, `abyssalSocketList`, `slotNum`.
- `Populate()` (ISC:75) rebuilds `items`/`list` from `pairs(itemsTab.items)` filtered by `IsItemValidForSlot`, NOTE: `pairs` order is NOT `itemOrderList` order, so the candidate list order is non-deterministic across runs. Bridge should sort candidates itself (by `itemOrderList` position) for stable QML lists. It resets selItemId to 0 if the current item is no longer valid.
- `SetSelItemId(id)` (ISC:61): jewel sockets write `spec.jewels[nodeId]` (+ `BuildClusterJewelGraphs()` on change); others write `activeItemSet[slotName].selItemId`.
- selFunc (ISC:12-19) to replicate exactly: `if items[index] ~= selItemId then SetSelItemId(items[index]); itemsTab:PopulateSlots(); itemsTab:AddUndoState(); build.buildFlag=true end`. So `pob_itemsEquip(slotName, itemId)` = validity check + this. Prefer calling `slot.selFunc(index, list[index])` after setting `self.items` index, or just replicate the 4 lines (safer).
- Flask activate checkbox: `slot.active=state; itemSet[slot].active=state; AddUndoState(); buildFlag=true` (ISC:34-38).
- `tooltipFunc(tooltip, mode, index, itemId)` (ISC:48) looks up `itemsTab.items[self.items[index]]` and calls `itemsTab:AddItemTooltip(tooltip,item,self)`. It clears if `main.popups[1]` or `itemsTab.selControl` is set to a non-list control. In the host `selControl` is nil, so it works. Pass mode="HOVER".
- Drag receive (ISC:118-130): if the value has a live id then SetSelItemId, else `new("Item", raw); NormaliseQuality(); itemsTab:AddItem(newItem,true); SetSelItemId(newItem.id)`. Then PopulateSlots, AddUndoState, buildFlag. Lift as `pob_itemsEquipRaw`.
- `Draw`/`DrawViewer` (ISC:132-149, ItemSlotHelper.lua) draws the jewel socket radius minimap with SetViewport/DrawImage. AVOID; QML re-authors with the existing tree viewer (nodeId to tree position).
- `OnHoverKeyUp` (ISC:162): wiki open. Skip.

### `IsItemValidForSlot(item, slotName, itemSet?)` (IT:2076-2122) (pure, safe to call)
- Splits `"Name N"`. Jewel sockets: node from `spec.tree.nodes` or `spec.nodes`. Charm sockets accept only `base.subType=="Charm"` items and vice versa. Cluster jewels only fit expansion sockets whose `expansionJewel.size >= jewel.sizeIndex`. Outer sockets accept anything else.
- `item.type == slotType` matches ("Flask 3" -> "Flask"). Tincture is valid for Flask slots. Abyss jewels are valid for slots containing "Abyssal Socket". Weapon 1/Swap accepts `base.weapon`. Weapon 2/Swap depends on the weapon 1 (or "Weapon 1 Swap") item in `itemSet`: none means shield or one-hand; bow means quiver; one-hand means shield or a one-hand that is not (wand vs non-wand mixed).
- It returns nil (falsy) rather than false in the fall-through case. Coerce to boolean for QML. Ring 3 and Graft have no special check.
- `GetEquippedSlotForItem(item)` (IT:2044): first non-inactive slot with `selItemId==item.id`, else (slot, otherSet) for other sets. `GetComparisonSlotNameForItem` covered in 6.4.

### Spec selector (IT:191-204, 1361)
- `controls.specSelect` selFunc: `if treeTab.specList[index] then build.modFlag=true; treeTab:SetActiveSpec(index) end`. The list is refreshed in Draw via `treeTab:GetSpecList()`. Manage button `treeTab:OpenSpecManagePopup()` is the existing Tree-view bridge (`pob_spec*`, PH:4811-5085). Do not duplicate. The Items view should call the same bridge fn and re-read slots (`UpdateSockets()`, `PopulateSlots()`), because spec change alters `spec.jewels`. TreeTab.lua:579-600 already repopulates item slots and specSelect.
- Item-set selector: `setSelect` (IT:97-110) enabled only if `#itemSetOrderList>1`. selFunc = `SetActiveItemSet(order[index]); AddUndoState()`. Names: `set.title or "Default"` (IT:1331).

### State shape suggestions (plain tables; all read from live objects each call)
```
itemsGetState() -> {
  sets = [{index, id, title, isActive}],  activeSetIndex, useSecondWeaponSet,
  slots = [{slotName,label,nodeId(0 if none),kind:"base|abyssal|flask|jewel|graft",
            selItemId, itemName, rarity, itemType, shown(bool), inactive(bool), weaponSet(0|1|2),
            parentSlotName, abyssalCount, flaskActive(bool|nil),
            candidateIds:[id...], hasItem}],           // sockets: only allocated ones, ordered by UpdateSockets label
  items = [{id,name,rarity,type,baseName,usedText,equippedSlot,isUnused,isFlask}],  // ILC GetRowValue text via lift
  specs = [{index,label}], activeSpec,
  displayItem = nil | <see 6.3>
}
```

## 6.2 ItemListControl / ItemDBControl / SharedItemListControl

Never marshal `ListControl` objects. All three are `ListControl` subclasses whose callbacks are plain fields/methods (`OnSelClick`, `OnSelCopy`, `OnSelDelete`, `GetRowValue`, `AddValueTooltip`, `GetDragValue`, `ReceiveDrag`). Call the methods directly with explicit index/value args, having set the `shift/ctrl` flags via a bridge arg.

### ItemListControl (ILC) - `itemsTab.controls.itemList`; list = `itemOrderList`
- Row label `GetRowValue(1, index, itemId)` (ILC:114): `<rarityColor>name  ^9(Unused)` or `(Used in 'Set')`. Uses `FindEquippedAbyssJewel(id,true)` (93), `FindSocketedJewel(id,true)` (70) and `GetEquippedSlotForItem`. Safe. Call it directly for the row text; it returns a color-coded string that QML must convert (`^7`, `^x` codes).
- Tooltip `AddValueTooltip(tooltip,index,itemId)` (ILC:132) = `AddItemTooltip(tooltip, item)` (no slot, dbMode=nil). Note it uses `IsKeyDown("SHIFT")` for `slotNum`, and `tooltip:CheckForUpdate(...)`, so pass a fresh Tooltip.
- `OnSelClick(index,itemId,doubleClick)` (ILC:161):
  - CTRL-click = equip/unequip in `item:GetPrimarySlot()`. weaponSet==1 and useSecondWeaponSet redirects to `slotName.." Swap"`. SHIFT redirects to `gsub("1","2")` if valid (IT:2076). Toggles to 0 if already equipped there. Then `PopulateSlots; AddUndoState; buildFlag`. Reimplement with explicit args (do not call, it reads IsKeyDown).
  - Double-click = `new("Item", item:BuildRaw()); newItem.id = item.id; SetDisplayItem(newItem)` (opens editor on a COPY holding the same id, so "Save" replaces in place).
- `OnSelCopy` (ILC:193): `Copy(item:BuildRaw():gsub("\n","\r\n"))`. `OnSelDelete` (ILC:198): confirm popup if equipped in a slot/set (message texts at ILC:203, 212, 220), else immediate `DeleteItem(item)`. QML asks the confirm question first (use `GetEquippedSlotForItem`, `FindEquippedAbyssJewel`, `FindSocketedJewel` to build the message), then calls `DeleteItem(item)` which internally does PopulateSlots + AddUndoState + zeroes `spec.jewels` refs across ALL specs (IT:1567-1614). Set buildFlag (DeleteItem does when equipped).
- Buttons to lift:
  - Delete All (ILC:22-39): zero all slots via `SetSelItemId(0)`, zero every `spec.jewels[*]`, `wipeTable(self.list)` and `wipeTable(itemsTab.items)`, PopulateSlots, AddUndoState, buildFlag. Note it does NOT call BuildClusterJewelGraphs.
  - Delete Unused (ILC:43-61): collect ids where `not GetEquippedSlotForItem and not FindEquippedAbyssJewel(id,false) and not FindSocketedJewel(id,false)`, delete in reverse with `DeleteItem(item,true)` (deferUndo), then for all specs `BuildClusterJewelGraphs()`, PopulateSlots, AddUndoState, buildFlag.
  - Sort (ILC:65): `itemsTab:SortItemList()` (IT:1530; does AddUndoState itself).
- Reorder via drag = `OnOrderChange` = `AddUndoState()` (ILC:157). Bridge: `t_insert(list,to,t_remove(list,from)); AddUndoState()` (order differs from set list: undo state IS added here).
- `ReceiveDrag` (ILC:147): creates `new("Item", value.raw); NormaliseQuality(); AddItem(newItem,true, index); PopulateSlots; AddUndoState` (no buildFlag; nothing equipped so OK).

### ItemDBControl (IDB) - `controls.uniqueDB` (main.uniqueDB, "UNIQUE"), `controls.rareDB` (main.rareDB, "RARE")
- `db.list` = table of Item objects (loaded lazily; `db.loading` true while loading; while loading show "Loading...").
- Filters live in dropdown/edit controls (IDB:31-56): `controls.slot.selIndex` (list `slotList` IDB:29), `controls.type.selIndex` (`typeList`, extended by `LoadLeaguesAndTypes` IDB:61 once `db.loading` is false), UNIQUE only: `controls.league.selIndex` (`leagueList`), `controls.requirement.selIndex` (Any/Current level/Current attributes/Current useable), `controls.obtainable.selIndex` (Obtainable[default 1]/Any source/Unobtainable/Vendor Recipe/Upgraded/Boss Item/Corruption), `controls.sort` (`sortDropList` from `data.powerStatList`, IDB:191), and `controls.search.buf` plus `controls.searchMode.selIndex` (1 Anywhere/2 Names/3 Modifiers).
  - The cleanest port: set `.selIndex`/`.buf` directly (assigning without callbacks) then set `listBuildFlag=true`; `SetSortMode(sortMode)` (IDB:185) for sort.
- `DoesItemMatchFilters(item)` (IDB:81) is pure (reads control fields, `build.characterLevel`, `calcsTab.mainOutput.Str/Dex/Int`). Searching uses `PCall(string.matchOrPattern, ...)` (exists in host? `string.matchOrPattern` is defined by engine Common; `PCall` in PH:219). Mirrors well.
- List build is a COROUTINE driven only from `IDB:Draw` (IDB:273-298); in the host `Draw` never runs, so drive it yourself:
  ```
  if build.outputRevision ~= db.listOutputRevision then listBuildFlag=true end
  if listBuildFlag then wipeTable(self.list); self.listBuilder=coroutine.create(self.ListBuilder); self.listOutputRevision=...; listBuildFlag=false end
  repeat coroutine.resume(self.listBuilder, self) until coroutine.status=='dead'   -- or resume in slices, driven by a QTimer, and report progress
  ```
  - Non-stat sort: fast (`table.sort` on `name`/`measuredPower` per `sortOrder`, "The " stripped).
  - Stat sort (`sortDetail.stat`): for every filtered item and every valid slot it calls `calcFunc({repSlotName,repItem})` (or `toggleFlask`/`toggleTincture`) and stores `item.measuredPower` = max (IDB:225-245). It yields every 50 ms with `defaultText = "Sorting... (N%)"` (yield at IDB:241). For the Qt port: resume the coroutine slice by slice from a timer (or bounded loop), read `self.defaultText`/progress from `itemIndex/#list` (progress is only visible inside the local; capture by patching `defaultText` parse, or reimplement `ListBuilder` in the bridge as a lift and keep `itemIndex`), return `{done=false,percent=..}` until dead. Cancel: drop the coroutine when filters change (legacy just re-creates on `listBuildFlag`).
  - `GetTime()` is used for the 50 ms slice test, so it works in host. `self.build` at IDB:228 is nil (`GetMiscCalculator(self.build)` is harmless, arg ignored, IT:743 unpack only).
- `GetRowValue`: `<rarityColor>name`. `AddValueTooltip` -> `AddItemTooltip(tooltip,item,nil,true)` (dbMode=true adds Variant/League/Exclusive/Source/upgradePaths lines, IT:3979-4001).
- `OnSelClick(index,item,doubleClick)` (IDB:320):
  - CTRL: `new("Item", item.raw); NormaliseQuality; AddItem(newItem,true)`; equip in primary slot (same weaponSet/SHIFT redirect as ILC) via `slots[slotName]:SetSelItemId(newItem.id)`; PopulateSlots, AddUndoState, buildFlag.
  - Double-click: `CreateDisplayItemFromRaw(item.raw, true)` (normalise=true, opens editor).
- `OnSelCopy`: `Copy(item.raw:gsub("\n","\r\n"))`.
- Drag targets (IT:1002-1017) are UI only.
- Database items reference the shared DB objects, so NEVER mutate them (always `new("Item", item.raw)`).

### SharedItemListControl (SIL)
- List is `main.sharedItemList` (Items, cross-build, persisted to Settings.xml `<SharedItems>` by Main.lua:757-768 on `SaveSettings`, which the host settings path already calls).
- `ReceiveDrag` (SIL:44): `new("Item", value:BuildRaw())` (NormaliseQuality if `not value.id`), then `t_insert(list, dragIndex or #list, newItem)`. Add via bridge `pob_itemsShareItem(itemId)`. Delete: `t_remove(list,index)` after confirm. Double-click: `CreateDisplayItemFromRaw(item.raw,true)`. Copy: `Copy(item:BuildRaw()...)`. Mutating `main.sharedItemList` needs `main:SaveSettings()`? Legacy relies on the normal settings save on exit/"Save" (check host's SaveSettings call site before promising persistence).
- Shared item sets (SISL, list `main.sharedItemSetList`, `{title,slots}`): rename `title=..; itemsTab.modFlag=true` (no undo); delete = `t_remove`; drag from ISL = `ReceiveDrag` SISL:80-100; drag into ISL creates a new set (ISL:93-106): NewItemSet, title, for each `slots[slotName]` `AddItem(new Item(raw), true)` and `itemSet[slotName].selItemId = id`, insert into order list, AddUndoState (NOTE: no SyncLoadouts and no PopulateSlots; add both).

### Cursor/draw-dependent code to avoid in 6.2
- `ListControl` Draw/hit-test/drag internals (`selDragIndex`, `dragIndex`, `GetHoverValue`, `OnHoverKeyUp`). `ItemDBClass:Draw` (only to be replaced by the manual coroutine pump). `IsKeyDown` reads inside OnSelClick (replace by explicit args). Popups (`main:OpenConfirmPopup`, `main:OpenPopup`) - replaced by QML dialogs.

## 6.3 Display item editor

State: `itemsTab.displayItem` (Item), `displayItemTooltip` (Tooltip 458 wide, `center=true`). `self.displayItem.id` may be an existing id (editing in place), or nil (new). `controls.addDisplayItem` label = `items[displayItem.id] and "Save" or "Add to build"`.

Entry points that set the display item (all end in `SetDisplayItem`, IT:1671):
- `CreateDisplayItemFromRaw(raw, normalise)` (IT:1658): `new("Item",raw)`, if `.base` then `CopyAnointsAndEldritchImplicits(newItem, main.migrateEldritchImplicits, false)`; if normalise `NormaliseQuality(); BuildModList()`; `SetDisplayItem(newItem)`. Silent no-op when base missing.
- Paste hotkey: `Paste()` -> `CreateDisplayItemFromRaw(text, true)` (IT:1274).
- List double-click: see 6.2 (ILC copy keeps `id`; IDB/SIL use normalise=true).
- Craft popup, Edit-text popup, enchant/anoint/corrupt/custom/crucible/implicit popups (all end in `SetDisplayItem(newItem)` with `newItem.id = displayItem.id` preserved).
- Cancel: `SetDisplayItem()` (nil) -> `snapHScroll="LEFT"` only. Add: `AddDisplayItem(noAutoEquip)` (IT:1519): `AddItem(displayItem, noAutoEquip)` (autoequips the first empty valid shown slot when the item is new: IT:1493-1500, only when `item.id==nil`), `SetDisplayItem()`, `PopulateSlots()`, `AddUndoState()`, `buildFlag=true`. `AddItem` with an existing id replaces `items[id]` and calls `BuildModList()`; if replacing and either is a cluster jewel/Timeless Jewel and the id is in `spec.jewels`, `spec:BuildClusterJewelGraphs()` (IT:1509-1515). Add to any bridge `pob_itemsSaveDisplay`.

### SetDisplayItem(item) (IT:1671-1747) - sequence to lift (for a new bridge `pob_itemsSetDisplay`)
1. `self.displayItem = item`; `UpdateDisplayItemTooltip()` (IT:1749) = `displayItemTooltip:Clear(); AddItemTooltip(tooltip, displayItem); center=true` (this runs BEFORE controls are synced; it does full compare calcs for every valid slot, so it is the expensive call).
2. Variant dropdowns: list=`item.variantList`, selIndex=`item.variant` (+ `variantAlt..Alt5` when `hasAltVariantN`). `CheckDroppedWidth(true)` is UI only.
3. `UpdateSocketControls()` (IT:1755): sockets colors and link states `link[i-1] = sockets[i].group == sockets[i-1].group` for `i <= #sockets - abyssalSocketCount`.
4. If `item.crafted`: `UpdateAffixControls()`.
5. Influence: two dropdowns; list = `influenceInfo.all` if `canHaveEldritchInfluence` or type in Helmet/Body Armour/Gloves/Boots, else `.default`; sel1/sel2 = first two `influenceInfo[i].key` set on the item; `displayItemInfluence:SetSel(influence1,true)` (no callback), `displayItemInfluence2:SetSel(influence2)` (callback! runs setDisplayItemInfluence which does `ResetInfluence`, re-sets flags, forces affix selFuncs if crafted, `BuildAndParseRaw`, `UpdateDisplayItemTooltip`). In a bridge, DO NOT replay this; just read flags from the item.
6. Quality edit, catalyst dropdown (`(item.catalyst or 0)+1`), catalyst quality (`max(catalystQuality,0)` or 0).
7. `UpdateCustomControls()` (IT:1953), `UpdateDisplayItemRangeLines()` (IT:2003), and if `clusterJewel and crafted` `UpdateClusterJewelControls()` (IT:1765).

### Per-section: control -> callback (all `selFunc/changeFunc/onClick` are plain closures; effect body is the state to replicate). Common tail: `displayItem:BuildAndParseRaw(); UpdateDisplayItemTooltip()` (+ section-specific)
- Variants (IT:362-421): `displayItem.variant = index` (or `variantAlt`, `variantAlt2..5`), `BuildAndParseRaw()`, `UpdateDisplayItemTooltip()`, `UpdateDisplayItemRangeLines()`. Visibility: `variantList and #variantList>1` (main), `hasAltVariantN`. Height rules IT:351-361.
- Sockets/links (IT:427-472): color drop `sockets[i].color = value.color` (R/G/B/W, `socketDropList`), link checkbox adjusts `.group` of later sockets (IT:438-447), `+` inserts `{color=defaultSocketColor, group=prev.group+1}` at `#sockets - abyssalSocketCount + 1` and bumps later groups (IT:457-468) then `UpdateSocketControls()`. Show when `selectableSocketCount >= i and sockets[i].color ~= "A"`. All then `BuildAndParseRaw(); UpdateDisplayItemTooltip()`.
- Enchant/Anoint/Corrupt/Implicit buttons (IT:478-545), popups:
  - Shown conditions: Enchant = `displayItem.enchantments`; Enchant 2 = also `canHaveTwoEnchants and #enchantModLines>0`; Anoint = `isAnointable(item)` = `canBeAnointed or base.type=="Amulet"` (IT:63); Anoint 2/3/4 need `canHaveTwo/Three/FourEnchants` and `#enchantModLines > 0/1/2`; Corrupt = `item.corruptible`; Add Implicit = complex predicate IT:541-544 (not Tincture/Graft, `corruptible` or (non Flask/Jewel and NORMAL/MAGIC/RARE) and not `implicitsCannotBeChanged`).
  - `EnchantDisplayItem(slot)` (IT:2280): lists `displayItem.enchantments[skill][source]` (or `[source]` directly when no skills), skill list filtered to skills used in socket groups unless "All skills" checked (`skillsUsed` from `skillsTab.socketGroupList[*].gemList[*].gemData.grantedEffectList`), sort by `data.powerStatList` stat via `calcFunc({repSlotName=primarySlot, repItem=item})` (IT:2373-2398). Apply: `enchantItem()` (IT:2348): `new Item(displayItem:BuildRaw()); item.id=displayItem.id`; "A/B" pattern sets both lines, else replaces `enchantModLines[enchantSlot]` inserting `{crafted=true,line=line}`, respects `canHaveTwoEnchants`; `BuildAndParseRaw()`; then `SetDisplayItem(newItem)`. Tooltip preview = `AddItemTooltip(tooltip, enchantItem(index), nil, true)`.
  - `AnointDisplayItem(slot)` (IT:2597): uses `NotableDBControl` (another ListControl, not in scope; lift its data by iterating `build.spec.tree.nodes` for anointable notables, same source), apply = `anointItem(node)` (IT:2527): copy of display item, replace `enchantModLines[anointEnchantSlot]` with `{crafted=true,line="Allocates "..node.dn}`, `BuildAndParseRaw`. Tooltip = `AppendAnointTooltip(tooltip,node)` (IT:2544; compares vs `repSlotName=item.base.type or "Amulet"`; note it passes base.type, not GetPrimarySlot: keep as-is). Helpers `getAnoint(item)`, `getMissingAnointCount(item)`, `AppendAddedNotableTooltip` are plain methods (safe).
  - `CorruptDisplayItem("Corrupted")` (IT:2637): implicit (`Corrupted` type mods 2 dropdowns; `Scourge` source adds 4: upside x2, downside x2) and, for uniques/relics, "Roll Ranges" secondary window (0.78-1.22 `corruptedRange` per scalable explicit line, `itemLib.isModLineScalable`/`applyRange`, slider val `(range-0.78)/0.44`). `corruptItem(addingImplicits)` (IT:2755): `item.corrupted=true`; implicit lines `{tags:..}` + line; scourge lines prefixed `{scourge}` when `ScourgeUpside`; roll mode sets `modLine.corruptedRange`. Two selects exclude each other's `mod.group` (selFunc IT:2949-2953). Sorting: `getSortValue` computes via calcFunc; for the port, lift with a small `pob_items*` function.
  - `AddImplicitToDisplayItem` (IT:3389): sources EXARCH/EATER (only if `cleansing`/`tangle` flags, non-unique armour), DelveImplicit, Custom (free text -> `{line=buf, custom=true}`). Grouping `modGroups`/`modList`. `applyCandidateMod(item, listMod)` (IT:3552) replaces an existing eldritch implicit of same type else appends `{line, modTags, [type]=true}`. Sorting stat = `data.powerStatList`.
  - `AddCustomModifierToDisplayItem` (IT:2973): sources MASTER (bench: `data.masterMods` filtered by `craft.types[item.type]` and group exclusion), ESSENCE (`data.essences[*].mods[item.type]`), VEILED, BEASTCRAFT, DELVE, NECROPOLIS, PREFIX/SUFFIX (only non-crafted; `GetModSpawnWeight(mod)>0`), CUSTOM free text (`{line, custom=true}`). `addModifier()` (IT:3208): adds `{line=..., modTags=..., [listMod.type]=true}` to `explicitModLines` of a new Item copy; flags: `crafted` (bench), `custom`. `checkLineForAllocates(line, spec.nodes)` (IT:2017) rewrites "Allocates <id>" to names. Tooltip via `AddModComparisonTooltip(tooltip, mod)` (IT:2027), which builds a new item with the mod, compares `repSlotName=displayItem:GetPrimarySlot()`, repItem=displayItem vs newItem, header "\nAdding this mod will give: ". Shown when rarity is MAGIC or RARE.
  - `AddCrucibleModifierToDisplayItem` (IT:3277): `data.crucible` mods filtered by `displayItem:CanHaveMod(mod)`, 5 dropdowns by `mod.nodeLocation` (node 1..5), preselect from `crucibleModLines` via `itemModMap`/`nodeSelections` (IT:3347-3373), apply resets `crucibleModLines={}` then adds `{line, modTags, [type]=true}`. Shown for `GetPrimarySlot()=="Weapon 1"` or Shield or `canHaveShieldCrucibleTree`.
- Influence (IT:548-592): `setDisplayItemInfluence(indexList)` = `ResetInfluence()`, set `item[influenceInfo[idx].key]=true` (or all three default when `HasElderShaperAndAllConquerorInfluences`), if crafted re-fire affix selFuncs, `BuildAndParseRaw()`, `UpdateDisplayItemTooltip()`. Visible when `canBeInfluenced`. Two dropdowns (index 1 = none).
- Quality (IT:598-610): `displayItem.quality = tonumber(buf)`, `BuildAndParseRaw`, tooltip. Note the shown() predicate uses `or`, so it is effectively always true when `item.quality` is set (legacy bug; QML should show only when `quality ~= nil`).
- Catalyst (IT:616-652): dropdown list of 13 (0 = none, the index-1 mapping), quality edit. If `catalystQuality` is nil sets 20 and updates the edit box. If crafted re-fire affix selFuncs. Shown when `(crafted or hasModTags) and base.type in Amulet/Ring/Belt`.
- Cluster jewel (IT:655-673): skill dropdown (`clusterJewel.skills`, minus affliction_strength/dexterity/intelligence; sorted by name; default first) sets `item.clusterJewelSkill` then `CraftClusterJewel()` (IT:1792): wipe `enchantModLines`, add "Adds N Passive Skills" / socket lines / `table.concat(skill.enchant,"\n")` all `crafted=true`, `BuildAndParseRaw()`, `UpdateAffixControls()` and re-fire each `displayItemAffixN.selFunc`. Node count slider maps `val` -> `round(val*(max-min)+min)` (IT:671), `divCount = max-min`. Shown when `crafted and clusterJewel`.
- Affix dropdowns (IT:691-916; up to 6, `affixLimit`): `UpdateAffixControls()` (IT:1814) -> per-control `UpdateAffixControl(control,item,"Prefix"/"Suffix","prefixes"/"suffixes",index)` (IT:1829): builds candidate `affixList` filtered by `not excludeGroups[mod.group]`, `not CheckIfModIsDelve`, `GetModSpawnWeight(mod, extraTags)>0` (plus the retained selected one flagged "[Retained]"), sorted by `statOrder`/level. Jewels (non-abyss) list one row per mod (label = joined lines); others group "tier series" by equal `statOrder` (`lastSeries.modList`, label collapses ranges to "#" when >1 tier). Slider: `slider.val=(tierIndex-1+range)/divCount`, `divCount=#modList` (nil if 1), shown iff row `haveRange`. Range-boundary fudge at IT:1941-1943 must be kept.
  - selFunc (IT:734-749): `affix = {modId="None"}`; if `value.modId` then `affix.modId, affix.range = value.modId, slider.val` elseif `value.modList` then `slider.divCount=#modList; idx,range = slider:GetDivVal(); affix.modId = modList[idx]; affix.range = verifyRange(range, idx, drop)`; then `displayItem[drop.outputTable][drop.outputIndex] = affix; displayItem:Craft(); UpdateDisplayItemTooltip(); UpdateAffixControls()`. `verifyRange` (IT:694-733) is a local closure that flips range for step-1 tier boundaries; it must be copied (it only needs `displayItem.affixes` and the drop list). Slider change: IT:869-877 same but writes into existing affix, then `Craft(); UpdateDisplayItemTooltip()`.
  - The list rows are Lua tables holding `modList` (array of modIds), not safe as plain rows; marshal `{label, modIds[], haveRange, selected, retained}` and keep an index-based bridge (`pob_itemsSetAffix(slotIndex, rowIndex, range01)`).
  - `Craft()` (Item.lua:1413) rebuilds explicit lines from `prefixes/suffixes`.
  - Affix hover tooltip (IT:753-865): tier lines + level + tags, and for cluster notables "1 Added Passive Skill is X" adds `socketViewer:AddNodeName`, stat lines, reminder text, comparison `AppendAddedNotableTooltip`, and `clusterJewelInfoForNotable`. Non-notable uses `AddModComparisonTooltip(tooltip, mod)` with default-quality tier `modList[1+round((#modList-1)*main.defaultItemAffixQuality)]`. `socketViewer:AddNodeName` may touch the drawing viewer; test in host. If it errors (wrapped by `tipLines` pcall) fall back to node.dn only.
- Custom-modifier "Remove" rows (IT:1953-2000): for `explicitModLines` (+ `crucibleModLines`) entries with `.custom/.crafted/.crucible`; Remove = `t_remove` from the right list, `item:BuildAndParseRaw()`, `local id=item.id; CreateDisplayItemFromRaw(item:BuildRaw()); displayItem.id=id` (this re-runs CopyAnoints...(!): the remove path silently re-copies the equipped amulet's anoint/eldritch implicit; keep or consciously drop). Label truncation at 330px uses `DrawStringCursorIndex` (stubbed): re-implement truncation in QML with elide. `item.customCount` is used for layout only.
- Range lines (IT:942-992): `rangeLineList = [{line, range}]`. Single dropdown+slider for normal items (slider writes `rangeLineList[sel].range`), or stacked sliders (max 20) when `main.showAllItemAffixes and rarity=="UNIQUE"` (IT:966-992). Slider change: `range=val; BuildAndParseRaw(); UpdateDisplayItemTooltip(); UpdateCustomControls()`. Note `UpdateDisplayItemRangeLines()` resets the selection to line 1 and slider val to line 1's range (do not call it from slider changes, only after variant changes).
- Craft item popup (IT:2138): rarity drop (`rarityDropList` NORMAL/MAGIC/RARE/UNIQUE/RELIC), title edit (rarity>=3, "New Item" if blank), type drop = `data.itemBaseTypeList`, base drop = `data.itemBaseLists[type]` (entries `{name, base}`). `makeItem(base)`: fresh `new("Item")`, fields `name, base, baseName, buffModLines..crucibleModLines={}`, `quality=nil` for Amulet/Belt/Jewel/Quiver/Ring/Graft else 0; flask/charm/tincture clamp rarity RARE -> MAGIC; rarity index 2/3 sets `crafted=true`; `rarity=list[sel].rarity`; `title` if index>=3; implicit lines from `base.implicit` (`modLib.parseMod` per line; `implicitModTypes`); `NormaliseQuality(); BuildAndParseRaw()`. Create = `SetDisplayItem(item)`; then if not crafted and rarity ~= NORMAL, open EditDisplayItemText; remember `lastCraftRaritySel/TypeSel/BaseSel`. Lift makeItem as `pob_itemsCraftNew(rarityIdx,title,typeIdx,baseIdx)`. Base tooltip = `AddItemTooltip(tip, makeItem(value), nil, true)`.
- Edit-text popup (IT:2225): textarea, rarity dropdown. `buildRaw()`: text as-is if it starts with "Item Class: ...\nRarity: " or "Rarity: ", else prepends `"Rarity: X\n"`. Enabled only if `new("Item", raw).base ~= nil`. Save: `id = displayItem and displayItem.id; CreateDisplayItemFromRaw(raw, not displayItem); displayItem.id = id; if alsoAddItem then AddDisplayItem() end`. `pasteFilter=sanitiseText` (global). Initial text `displayItem:BuildRaw():gsub("Rarity: %w+\n","")`. Validation tooltip: `AddItemTooltip(tooltip,item,nil,true)` or the "item is invalid" help lines (IT:2264-2270).
- Buy similar (IT:340): `buySimilar.openPopup(displayItem, GetComparisonSlotNameForItem(displayItem), build)` from `Classes/CompareBuySimilar` (opens a browser URL; out of scope unless required).

### Order of side effects (the rule to keep)
`mutate item -> item:BuildAndParseRaw() (or :Craft() for affixes) -> [section-specific rebuild: UpdateSocketControls/UpdateAffixControls/UpdateCustomControls/UpdateDisplayItemRangeLines/UpdateClusterJewelControls] -> UpdateDisplayItemTooltip()`. NOTE `AddModComparisonTooltip` is only a tooltip helper (never mutates). `AddModComments` does not exist in this legacy file (grep confirms); no comment-adding side effect to port.
- The displayItem is NOT part of the undo stack. Only `AddDisplayItem`, equip, delete, set ops call `AddUndoState`. Undo state (IT:4737) deep-copies ALL items (`copyTableSafe(...,true,true)`), `itemOrderList`, slotSelItemId, `itemSets`, `itemSetOrderList`: each `AddUndoState` is O(items), so avoid calling it in drag/slider loops.
- Hotkey Ctrl+Z/Y in the tab: `Undo()/Redo(); build.buildFlag=true` (IT:1285-1290). After undo the `items` table is replaced: any cached Item references in the bridge are stale.

### Dangerous to marshal raw / what to send instead
- Item objects (`items[id]`) carry `base` (shared data table), `modList`/`baseModList`/`slotModList` (ModStore with closure refs), `weaponData/armourData/flaskData`, `jewelData` tables that reference the tree/calc env, `affixes` (huge shared table), `sockets`, `raw`. Never hand these to the QVariant converter.
- `Tooltip` objects, `ListControl`s, `DropDownControl.list` entries with `modList`/`mod` (mod tables include `statOrder`, `modTags`, refs into `data.itemMods`): marshal labels + integer keys only.
- `calcsTab.mainEnv.flasks[item]` and `env.tinctures` are keyed by OBJECT (see PH:1397-1410): always resolve id -> `itemsTab.items[id]` inside Lua.
- Suggested shapes (plain tables, primitives, arrays):
  - Item summary row: `{id,name,baseName,type,rarity,quality,level,sockets:"R-G B", usedText,equippedSlot,isUnused}`.
  - Display item (editor state): `{id|0, isNew, rarity, title, baseName, type, quality|nil, corrupted, mirrored, fractured, crafted, canBeInfluenced, influences:[keys], catalyst,catalystQuality, canCatalyst, variantList:[str], variantSel:[n1..n6], sockets:[{color,group}], selectableSocketCount, abyssalSocketCount, defaultSocketColor, canEnchant, canAnoint:[bool x4], canCorrupt, canAddImplicit, canAddCustom(rarity MAGIC/RARE), canAddCrucible, clusterJewel:{skills:[{id,label}],sel,minNodes,maxNodes,count}|nil, affixes:[{kind:"Prefix|Suffix", outputTable, index, rows:[{label,modIds[],haveRange,retained}], sel, range01, divCount}], customMods:[{index,label,kind:custom|crafted|crucible}], rangeLines:[{line,range}], showAllRanges, tooltip:{lines,header,influenceHeader1/2,color}, enchantLines, implicitLines, explicitLines, raw}`.
  - Tooltip payload: `{lines:[{size,text,center}|{sep,size}], header=rarity, foilType, color, influenceHeader1, influenceHeader2}` via `tipLines`.
  - Compare payload: reuse PH `pob_compareOverride` output rows.
- Keep the working display item in a module-local Lua slot (`bm.itemsTab.displayItem`, as legacy) and address it implicitly (QML has no handle). All editor bridge fns operate on `it.displayItem` and return `{displayItem=<summary>, _emit={"items"}}` (NO recalc needed for edit-only; recalc only on Add/Save/equip/delete because the display item is not in calcs). Only tooltip/compare hovers do calcs (miscCalculator, no full rebuild).

## 6.4 Comparison tooltip, IsItemValidForSlot, GetComparisonSlotNameForItem, shortcuts

### AddItemTooltip(tooltip, item, slot, dbMode, maxWidth) (IT:3947-4735)
- Pure builder on a Tooltip; `tooltip.maxWidth=min(maxWidth or 600,600)`. Reads `main.showFlavourText`, `main.slotOnlyTooltips`, `launch.devModeAlt`, `IsKeyDown("SHIFT")` (`slotNum = slot.slotNum or (SHIFT and 2 or 1)`, IT:4005, and granted-skill child tooltips gated on SHIFT IT:4344). Ring 1/2 dual-slot (`item.slotModList[slotNum]`, `weaponData[slotNum]`): pass a real `slot` when known.
- Sections: title/base, influence lines, dbMode fields, weapon/armour/flask/tincture/jewel blocks, catalyst, sockets, talisman tier, `build:AddRequirementsToTooltip`, mod lines via `item:CheckModLineVariant` + `itemLib.formatModLine(modLine, dbMode)` for enchant/scourge/implicit/explicit/crucible, cluster notables from `spec.tree.clusterNodeMap`, corrupted/split/mirrored, flavour text (with Grand Spectrum special case), granted-skill child tooltips (`tooltip.childTooltips[i]`, uses `gemTooltip.AddGemTooltip`; only filled when SHIFT held).
- Comparison section (`showStatDifferences` gates; early return with the Ctrl+D tip when off, IT:4365):
  - Flask (4371-4578): computes effective flask stats from `mainEnv.modDB` and `calcsTab.mainOutput`, then `calcFunc({toggleFlask=item})` vs `calcBase`, header "Deactivating/Activating this flask will give you:" depending on `mainEnv.flasks[item]`.
  - Tincture (4579-4614): same with `toggleTincture`.
  - Else (4615-4726): `UpdateSockets()`; `compareSlots` = every slot where `IsItemValidForSlot`, not inactive, `weaponSet` matches active set, and `slot.shown()`. For each slot `getReplacedItemAndOutput`: `override={repSlotName=slot.slotName, repItem = item ~= selItem and item or nil}`; when the slot is a jewel socket and either item changes the radius (`itemChangesPassiveTreeRadius`: conqueredBy / intuitiveLeapLike / impossibleEscapeKeystone) then `override.spec = buildSpecForJewelComparison(...)`.
  - Sort: empty sockets first, then similar (same base type/subType non-unique, or same unique), FullDPS, CombinedDPS, TotalEHP, label, slotName (IT:4703-4720). Limited uniques: only compare vs slots already holding the same unique when the limit is reached (IT:4673). `main.slotOnlyTooltips and slot` => only that slot (IT:4652).
  - Header lines: "Removing this item from X will give you:" if `item == selItem`; else "Equipping this item in X will give you:" + "(replacing <name>)". Diff lines via `build:AddStatComparesToTooltip(tooltip, calcBase, output, header)`.
- `calcFunc, calcBase = build.calcsTab:GetMiscCalculator()` (CalcsTab.lua:743 = `unpack(miscCalculator)`) is the persistent closure rebuilt each `BuildOutput`; PH:1358 uses the same. `calcFunc` accepts `repSlotName/repItem/toggleFlask/toggleTincture/addNodes/removeNodes/spec`.
- Jewel-radius cloned spec (IT:3836-3945): `cloneSpecForJewelComparison(spec)` copies scalar spec keys (`sharedSpecKeysForJewelComparison`, IT:3845), clones all nodes minus `linked/depends/intuitiveLeapLikesAffecting/path/power`, re-links, reallocs, copies `jewels/masterySelections/hashOverrides/ignoredNodes`. `buildSpecForJewelComparison(itemsTab, compareSlot, replacementItem)` sets `spec.jewels[nodeId]` to the replacement (a temp negative id in `itemsTab.items` if the item is not in the build; removed after `BuildAllDependsAndPaths()` in xpcall) and rebuilds. All are file-LOCAL functions of ItemsTab.lua, not reachable from bridge code. Do not copy them: simply call `it:AddItemTooltip(tip, item, slot)`, which handles them. Only if structured (non-text) jewel compare rows are needed, `pob_compareOverride` must be extended with a `radiusJewelSlot` case that lifts these three fns (IT:3836-3945, ~110 lines, pure Lua, no cursor/draw).
- The whole AddItemTooltip cost = N slots x calcFunc. `ItemSlotControl.tooltipFunc` dedupes with `tooltip:CheckForUpdate(item, devModeAlt, outputRevision, SHIFT)` (ISC:53); in the bridge use fresh tooltips + QML-side cache keyed by `(outputRevision,itemId,slot)`.
- Draw and layout code (IT:1232-1362: scrollbars, `GetPos`, `displayItemTooltip:Draw`, anchors) is irrelevant. Avoid `Draw`, `GetDynamicSize`.

### GetComparisonSlotNameForItem(item) (IT:2060)
- Equipped slot if any (`GetEquippedSlotForItem`), else for Jewels the first non-inactive, shown, empty, valid slot, else `item:GetPrimarySlot()` (Item.lua:1487: weapon -> Weapon 1; Quiver/Shield -> Weapon 2; Ring -> Ring 1; Flask/Tincture -> Flask 1; Graft -> Graft 1; else base type). Used by Buy similar and by compare hovers. Pure, safe.

### CopyAnointsAndEldritchImplicits(newItem, copyEldritch, overwrite, sourceSlotName) (IT:1616-1655)
- Only call on the EDITOR path (paste / double-click / raw create), never for compare hover (see PH:1379). `newItemType = sourceSlotName or (weapon and "Weapon 1" or base.type)`; reads `activeItemSet[newItemType].selItemId` and `items[...]`.
- Copies: anoint (single-anoint amulets only, `#currentAnoint==1`); eldritch implicits + `tangle/cleansing` for NORMAL/MAGIC/RARE Helmet/Body Armour/Gloves/Boots when not corrupted/mirrored and no influence flags, with `main.migrateEldritchImplicits` (the option flag passed by CreateDisplayItemFromRaw); harvest/heist enchants for weapons and body armour. Ends with `newItem:BuildAndParseRaw()`. Note: it ALIASES `enchantModLines`/`implicitModLines` tables from the equipped item (shared reference, not a copy); subsequent edits to the display item would mutate the equipped item's lines until `BuildAndParseRaw` re-parses. The `new Item(displayItem:BuildRaw())` copies in every popup break the alias before saving, but a bridge editing `displayItem` directly right after creation could mutate the equipped item. Mitigation: after CreateDisplayItemFromRaw, do `displayItem = new("Item", displayItem:BuildRaw())` (preserve id) or deep-copy the two lists.

### Keyboard shortcuts (IT:1272-1306) - implement as QML Shortcuts
- Ctrl+V: `Paste()` -> `CreateDisplayItemFromRaw(text, true)`. In the host expose `pob_itemsPaste(text)`.
- `E` over a slot: triggers `itemList:OnSelClick(0, slot.selItemId, true)` (open the slot's item in the editor as a copy). Lift the body (ILC:186-190), needs hover context from QML.
- Ctrl+Z / Ctrl+Y: `Undo()/Redo()` + `buildFlag=true`; then `PopulateSlots` is done in `RestoreUndoState`.
- Ctrl+F: focus DB search (UI only). Ctrl+D: toggle `itemsTab.showStatDifferences` + `buildFlag=true` (saved as `showStatDifferences` attr, IT:1146).
- Wiki key: `itemLib.wiki.matchesKey/openItem(item)` - UI (ISC:163, ILC:235, IDB:357).

## 6.5 Save/Load XML (IT:1029-1230; the host already loads/saves through Build.lua, no new code needed for persistence)

Root element `<Items>` (node elem name given by Build.lua; ItemsTab.Save writes into it):
- attrs: `activeItemSet`, `useSecondWeaponSet` (of active set; legacy fallback only when no `<ItemSet>` exists, IT:1130-1134), `showStatDifferences`.
- children in order:
  1. `<Item id=N variant= variantAlt= variantAlt2..5=>RAW TEXT</Item>` for each id in `itemOrderList` (IT:1148-1195). `item:BuildAndParseRaw()` is called on Save (so Save mutates items!) and `item.raw` is the text child. `<ModRange id= range=>` children are LEGACY (only emitted for enchant/scourge/implicit/explicit/crucible lines that have `.range`; id counting starts at `#buffModLines+1` and continues through each list) and are read back on Load in the same list order (IT:1062-1076). Since RAW already contains range info in current builds, they are redundant but still written.
  2. `<ItemSet id title useSecondWeaponSet>` for each id in `itemSetOrderList`, with child `<Slot name= itemId= itemPbURL= active="true"|nil/>` for EVERY non-socket slot (including swap and abyssal names; `itemId` is `tostring(selItemId)`, 0 for empty) and `<SocketIdURL name= nodeId= itemPbURL=>` for jewel sockets whose node is allocated in the CURRENT spec only (IT:1200-1208). Slot enumeration uses `pairs(self.slots)`: order is non-deterministic, do not diff XML byte-for-byte. NB: before saving, the active set's `selItemId` must be current: `activeItemSet[slot].selItemId` is updated by `SetSelItemId`, so it is (only the `active` flag for flasks is copied at set-switch time; it is also written directly by the checkbox).
  3. `<TradeSearchWeights><Stat label stat weightMult="%.2f"/></TradeSearchWeights>` from `tradeQuery.statSortSelectionList`, entries with `weightMult>0`.
- Jewels: equipped jewel sockets are NOT stored in ItemSets; they are saved in the Tree spec (`spec.jewels`, `<Sockets><Socket nodeId itemId>`), and are restored on `PopulateSlots` (ISC:76-78). Load order matters: Build.lua loads Tree before Items? (check Build.lua load sequence when touching; `PopulateSlots` is called at the end of `SetActiveItemSet` in Load, IT:1135).
- Load (IT:1029): resets `activeItemSetId=0; itemSets={}; itemSetOrderList={}; statSortSelectionList={}` (but NOT `items`/`itemOrderList`; ctor initial state is empty and build load creates a fresh ItemsTab). Items parsed via `new("Item","")`, `ParseRaw(child)`, `BuildModList()` only if `item.base`; items with missing bases are silently DROPPED (their ids then dangle in ItemSets: `Populate` resets to 0). Legacy `<Slot>` at root (pre-ItemSet) still read (IT:1084-1092). `ItemSet` ids from XML; `NewItemSet(id)`; Slot entries only where `itemSet[slotName]` exists (unknown slot names ignored). Finally `SetActiveItemSet(tonumber(attr.activeItemSet) or 1)` and `ResetUndo()`.
- Settings.xml shared items (Main.lua:670-712 load, 757-768 save): `<SharedItems><Item>raw</Item>...<ItemSet title><Item slotName=..>raw</Item></ItemSet></SharedItems>` (Item elem child is bare text; sets use `slotName` attr). Hosts loads this already via `main:LoadSettings`.
- No `<Items>` writes needed in the bridge as long as mutation goes through legacy methods and `build.modFlag`/`itemsTab.modFlag` is set: `AddUndoState` sets `itemsTab.modFlag=true`, and `Build.lua:1254` ORs `itemsTab.modFlag` into `self.unsaved`; Build.lua:1111 clears it after save. Edits that skip AddUndoState (display item edits) need no modFlag until Add/Save.

## Gotchas checklist (most likely to bite)
1. `pairs` order: `ItemSlotControl:Populate` item order, `pairs(self.slots)` in Save/NewItemSet, `pairs(it.sockets)` in `pob_getJewelSockets`. Always sort by `itemOrderList` / `orderedSlots` for QML.
2. `UpdateSockets()` is only invoked from Draw/AddItemTooltip; call it before reading socket `inactive`/`label` (else stale until first tooltip).
3. `IsKeyDown` reads (EquipItemInSet IT:1424, ILC/IDB OnSelClick, AddItemTooltip slotNum + granted skills). Pass explicit flags, or wrap with a temporary `IsKeyDown` override inside the bridge call (restore after) if you must call the legacy method as-is.
4. `main.popups[1]` is checked in most tooltipFuncs; keep nil in host. `itemsTab.selControl` nil in host (ControlHost never focuses anything); tooltipFuncs treat nil as "allow".
5. Undo state cost: copies all items; and `RestoreUndoState` replaces `items`. Refresh whole state after undo/redo. `state.itemSets` uses `copyTableSafe`, and `Undo()` restores `itemSets` object identity, so any cached set references die.
6. `CreateDisplayItemFromRaw` aliasing bug (see 6.4) and its side-effect on `displayItem`; `pob_addItemFromRaw` leaves a stale `displayItem` (PH:817-820): the editor bridge should `it:SetDisplayItem()` afterwards or use `new("Item",raw)` directly and `NormaliseQuality()` for DB items.
7. `DeleteItem` zeroes `spec.jewels` for every spec, deallocs dependent nodes (IT:1588-1608). Emit `tree` too; the socket-dependent tree state changed.
8. `AddItem(item)` autoequips a NEW item (id nil) into the first empty valid shown slot unless `noAutoEquip`; DB/drag paths pass `true`; "Add to build" (AddDisplayItem) with `noAutoEquip=nil` auto-equips.
9. `SetActiveItemSet` calls `SyncLoadouts` (touches `buildLoadouts` dropdown control), safe in host (PS also calls it under pcall, PS:313-315: copy that pcall wrapper).
10. Set add via `NewItemSet` without appending to `itemSetOrderList` leaves an orphan; ItemSetListControl's Cancel path removes it (ISL:65). In a bridge create and append atomically.
11. Undo of item sets alters `itemSetOrderList` by mutating in place (RestoreUndoState wipes + refills the same table since ILC/ISL hold it as `self.list`). A bridge keeping its own reference to `itemSetOrderList` is fine because identity is preserved, but `itemSets` is replaced.
12. Text: item names/labels contain PoB color codes (`^7`, `^x7F7F7F`, `colorCodes.*`). PS already handles them (labels raw, QML converts); do the same for `AddItemTooltip` lines (`center` flag per line).
13. Shared `main.uniqueDB.list` items must never be mutated (measuredPower is written onto them by IDB sorting; that is expected legacy behavior and harmless for QML since it is a numeric scratch field).
