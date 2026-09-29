-- Path of Building (Qt port)
--
-- Module: pob_items.lua  —  Items tab bridge
-- Phase 6 (Items Tab).
--
-- WHAT THIS IS
--   The Items tab (src/Classes/ItemsTab.lua, ItemSlotControl.lua, ...)
--   re-authored in QML over the LIVE legacy objects, same recipe as
--   pob_skills.lua: legacy callbacks stay reachable as plain closures/methods,
--   code is LIFTED (with a `-- File.lua:NNN` pointer) only where legacy reads
--   the cursor / keyboard (IsKeyDown, GetCursorPos are stubs in the host) or
--   draws, or lives in a popup that Qt re-authors.
--
--   Every mutation ends like legacy's OnFrame would after `buildFlag`: one
--   pob_recalculate(), then `_emit` so LuaEngine::invoke raises the signals.
--
--   NEVER marshal an Item / slot control / Tooltip raw: they reference the
--   calc env and `luaToVariant` runs to gigabytes. Everything returned here is
--   a plain table of primitives. Item and set tables are REPLACED on undo, so
--   QML addresses everything by slot name / 1-based index / item id and
--   re-reads the state after each call.

local t_insert = table.insert
local t_remove = table.remove

local EMIT = { "build", "items", "calcs" }
local EMIT_TREE = { "build", "items", "tree", "calcs" }

local function ctx()
    local bm = main and main.modes and main.modes.BUILD
    return bm, bm and bm.itemsTab
end

local function done(extra, emit)
    pob_recalculate()
    local r = extra or { }
    if r.ok == nil then r.ok = true end
    r._emit = emit or EMIT
    return r
end

local function fail(msg)
    return { ok = false, error = msg }
end

local function syncLoadouts(bm)
    pcall(function() bm:SyncLoadouts() end)
end

-- A real Tooltip filled by `fn`, marshalled as {size,text,center}|{sep,size}
-- (same shape as pob_skills.lua tipLines).
local function tipLines(fn)
    local tip = new("Tooltip")
    local ok, err = pcall(fn, tip)
    if not ok then return { { size = 16, text = "^1Tooltip error: " .. tostring(err) } } end
    local lines = { }
    for _, l in ipairs(tip.lines or { }) do
        if l.text == nil then
            lines[#lines + 1] = { sep = true, size = l.size or 10 }
        else
            lines[#lines + 1] = { size = l.size or 14, text = l.text, center = l.center and true or false }
        end
    end
    return lines
end

-- Run `fn` with IsKeyDown reporting `held[key]` (legacy click / equip code
-- reads SHIFT/CTRL through IsKeyDown; the host has no keyboard state).
local function withKeys(held, fn, ...)
    local saved = IsKeyDown
    IsKeyDown = function(key) return held[key] and true or false end
    local ok, a, b = pcall(fn, ...)
    IsKeyDown = saved
    if not ok then error(a, 0) end
    return a, b
end

---------------------------------------------------------------------------
-- Slots
---------------------------------------------------------------------------

local function slotKind(slot)
    if slot.nodeId then return "jewel" end
    if slot.parentSlot then return "abyssal" end
    if slot.slotName:match("^Flask") then return "flask" end
    if slot.slotName:match("^Graft") then return "graft" end
    return "base"
end

-- Legacy `slot.shown()` closures reach into calc state (Ring 3 reads
-- mainEnv.modDB) and can raise before a first calc; treat that as hidden.
local function slotShown(slot)
    local ok, shown = pcall(function() return slot:IsShown() end)
    return ok and shown and true or false
end

-- Candidate rows for one slot, in ALL-ITEMS-LIST order. ItemSlotControl:
-- Populate builds `items`/`list` from pairs(items), whose order is not stable.
local function slotOptions(it, slot)
    local out = { { id = 0, label = "None" } }
    for _, id in ipairs(it.itemOrderList) do
        local item = it.items[id]
        if item and it:IsItemValidForSlot(item, slot.slotName) then
            out[#out + 1] = { id = id, label = (colorCodes[item.rarity] or "^7") .. item.name }
        end
    end
    return out
end

local function slotRecord(it, slot)
    local item = it.items[slot.selItemId or 0]
    local rec = {
        slotName = slot.slotName,
        label = slot.label or slot.slotName,
        nodeId = slot.nodeId or 0,
        kind = slotKind(slot),
        selItemId = slot.selItemId or 0,
        itemName = item and item.name or "",
        itemLabel = item and ((colorCodes[item.rarity] or "^7") .. item.name) or "",
        rarity = item and item.rarity or "",
        weaponSet = slot.weaponSet or 0,
        parent = slot.parentSlot and slot.parentSlot.slotName or "",
        inactive = slot.inactive and true or false,
        shown = slotShown(slot),
        isFlask = slot.controls and slot.controls.activate ~= nil or false,
        flaskActive = slot.active and true or false,
        options = slotOptions(it, slot),
    }
    return rec
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local function setList(it)
    local sets = { }
    for i, id in ipairs(it.itemSetOrderList) do
        local s = it.itemSets[id]
        -- ItemSetListControl.lua:? row label / ItemsTab.lua:1331 dropdown label
        sets[i] = {
            title = s.title or "Default",
            rawTitle = s.title or "",
            listLabel = (s.title or "Default") .. (id == it.activeItemSetId and "  ^9(Current)" or ""),
            isActive = id == it.activeItemSetId,
        }
    end
    return sets
end

function pob_itemsGetState()
    local bm, it = ctx()
    if not it then return nil end
    -- ItemsTab:UpdateSockets is only run from Draw / AddItemTooltip, so call
    -- it here or socket `inactive` / "Socket #n" labels stay stale.
    it:UpdateSockets()
    local slots = { }
    for _, slot in ipairs(it.orderedSlots) do
        slots[#slots + 1] = slotRecord(it, slot)
    end
    local activeIdx = 1
    for i, id in ipairs(it.itemSetOrderList) do
        if id == it.activeItemSetId then activeIdx = i end
    end
    local specs = { }
    local tt = bm.treeTab
    for i, label in ipairs(tt:GetSpecList()) do specs[i] = label end
    return {
        sets = setList(it),
        activeSet = activeIdx,
        useSecondWeaponSet = it.activeItemSet and it.activeItemSet.useSecondWeaponSet and true or false,
        slots = slots,
        specs = specs,
        activeSpec = tt.activeSpec,
    }
end

---------------------------------------------------------------------------
-- 6.1 Item sets (ItemsTab setSelect + ItemSetListControl)
---------------------------------------------------------------------------

function pob_itemsGetSetList()
    local bm, it = ctx()
    if not it then return nil end
    return { sets = setList(it) }
end

-- ItemsTab.lua:97-110 (setSelect selFunc) / ItemSetListControl.lua:112-117.
function pob_itemsSetActiveSet(index)
    local bm, it = ctx()
    local id = it and it.itemSetOrderList[tonumber(index) or -1]
    if not id then return fail("no such set") end
    if id ~= it.activeItemSetId then
        it:SetActiveItemSet(id)
        it:AddUndoState()
    end
    return done()
end

-- ItemSetListControl.lua:37-41 + RenameSet(addOnName) Save 53-68.
function pob_itemsNewSet(title)
    local bm, it = ctx()
    if not it then return fail("no build") end
    local set = it:NewItemSet()
    set.title = title
    it.modFlag = true
    t_insert(it.itemSetOrderList, set.id)
    it:AddUndoState()
    syncLoadouts(bm)
    return done({ index = #it.itemSetOrderList })
end

-- ItemSetListControl.lua:14-22 (Copy; lifted, there is no CopyItemSet).
function pob_itemsCopySet(index, title)
    local bm, it = ctx()
    local srcId = it and it.itemSetOrderList[tonumber(index) or -1]
    if not srcId then return fail("no such set") end
    local newSet = copyTable(it.itemSets[srcId])
    newSet.id = 1
    while it.itemSets[newSet.id] do newSet.id = newSet.id + 1 end
    it.itemSets[newSet.id] = newSet
    newSet.title = title
    it.modFlag = true
    t_insert(it.itemSetOrderList, newSet.id)
    it:AddUndoState()
    syncLoadouts(bm)
    return done({ index = #it.itemSetOrderList })
end

-- ItemSetListControl.lua:53-68 (RenameSet Save, addOnName = false).
function pob_itemsRenameSet(index, title)
    local bm, it = ctx()
    local id = it and it.itemSetOrderList[tonumber(index) or -1]
    if not id or not tostring(title or ""):match("%S") then return fail("bad rename") end
    it.itemSets[id].title = title
    it.modFlag = true
    it:AddUndoState()
    syncLoadouts(bm)
    return done()
end

-- ItemSetListControl.lua:119-134 (OnSelDelete). Items are NOT deleted.
function pob_itemsDeleteSet(index)
    local bm, it = ctx()
    index = tonumber(index) or -1
    local id = it and it.itemSetOrderList[index]
    if not id or #it.itemSetOrderList <= 1 then return fail("cannot delete") end
    t_remove(it.itemSetOrderList, index)
    it.itemSets[id] = nil
    if id == it.activeItemSetId then
        it:SetActiveItemSet(it.itemSetOrderList[math.max(1, index - 1)])
    end
    it:AddUndoState()
    syncLoadouts(bm)
    return done()
end

-- ItemSetListControl OnOrderChange (:108) sets modFlag only.
function pob_itemsMoveSet(from, to)
    local bm, it = ctx()
    local list = it and it.itemSetOrderList
    from, to = tonumber(from) or -1, tonumber(to) or -1
    if not list or not list[from] or to < 1 or to > #list then return fail("bad move") end
    if from ~= to then
        t_insert(list, to, t_remove(list, from))
        it.modFlag = true
    end
    return done()
end

-- ItemsTab.lua:3753 AddItemSetTooltip (row tooltip of the set dropdown).
function pob_itemsSetTooltip(index)
    local bm, it = ctx()
    local id = it and it.itemSetOrderList[tonumber(index) or -1]
    if not id then return { lines = { } } end
    return { lines = tipLines(function(tip) it:AddItemSetTooltip(tip, it.itemSets[id]) end) }
end

-- ItemsTab.lua:222-262 (weaponSwap1 / weaponSwap2 onClick), lifted verbatim
-- for both directions. `n` is 1 (set I) or 2 (set II). The main socket group
-- follows the weapon set when it sat on the other one.
function pob_itemsSetWeaponSet(n)
    local bm, it = ctx()
    if not it then return fail("no build") end
    local second = tonumber(n) == 2
    if (it.activeItemSet.useSecondWeaponSet and true or false) == second then
        return done()                              -- locked (already this set)
    end
    it.activeItemSet.useSecondWeaponSet = second
    it:AddUndoState()
    bm.buildFlag = true
    local from, to = second and 1 or 2, second and 2 or 1
    local sgl = bm.skillsTab.socketGroupList
    local main = sgl[bm.mainSocketGroup]
    if main and main.slot and it.slots[main.slot] and it.slots[main.slot].weaponSet == from then
        for index, sg in ipairs(sgl) do
            if sg.slot and it.slots[sg.slot] and it.slots[sg.slot].weaponSet == to then
                bm.mainSocketGroup = index
                break
            end
        end
    end
    return done(nil, { "build", "items", "skills", "calcs" })
end

---------------------------------------------------------------------------
-- 6.1 Slot panel (ItemSlotControl)
---------------------------------------------------------------------------

-- ItemSlotControl selFunc (ItemSlotControl.lua:11-17). `itemId` 0 = None.
-- The item must be in the slot's own valid list (IsItemValidForSlot).
function pob_itemsEquip(slotName, itemId)
    local bm, it = ctx()
    local slot = it and it.slots[slotName]
    itemId = tonumber(itemId) or 0
    if not slot then return fail("no such slot") end
    if itemId ~= 0 then
        local item = it.items[itemId]
        if not item or not it:IsItemValidForSlot(item, slotName) then
            return fail("item not valid for slot")
        end
    end
    if itemId ~= slot.selItemId then
        slot:SetSelItemId(itemId)
        it:PopulateSlots()
        it:AddUndoState()
        bm.buildFlag = true
    end
    return done(nil, EMIT_TREE)
end

-- Flask activate checkbox (ItemSlotControl.lua:32-38).
function pob_itemsSetFlaskActive(slotName, state)
    local bm, it = ctx()
    local slot = it and it.slots[slotName]
    if not slot or not slot.controls.activate then return fail("not a flask slot") end
    slot.active = state and true or false
    it.activeItemSet[slotName].active = slot.active
    it:AddUndoState()
    bm.buildFlag = true
    return done()
end

-- ItemSlotControl tooltipFunc (ItemSlotControl.lua:47-56): the item tooltip
-- with its comparison against what the slot holds now. `itemId` is the row
-- hovered in the dropdown, or the slot's own item when 0/nil is passed with
-- `useSelected`.
function pob_itemsSlotTooltip(slotName, itemId)
    local bm, it = ctx()
    local slot = it and it.slots[slotName]
    local item = slot and it.items[tonumber(itemId) or 0]
    if not item then return { lines = { } } end
    return { lines = tipLines(function(tip) it:AddItemTooltip(tip, item, slot) end) }
end

-- EquipItemInSet (ItemsTab.lua:1412): used by the Build loadout dropdown.
-- Shift = redirect to the second slot when valid; legacy reads IsKeyDown.
function pob_itemsEquipInSet(itemId, setIndex, shift)
    local bm, it = ctx()
    local item = it and it.items[tonumber(itemId) or -1]
    local setId = it and it.itemSetOrderList[tonumber(setIndex) or -1]
    if not item or not setId then return fail("no such item or set") end
    withKeys({ SHIFT = shift and true or false }, function()
        it:EquipItemInSet(item, setId)
    end)
    return done(nil, EMIT_TREE)
end

---------------------------------------------------------------------------
-- Undo / redo (ItemsTab.lua:1285-1290)
---------------------------------------------------------------------------

function pob_itemsUndo()
    local bm, it = ctx()
    if not it then return fail("no build") end
    it:Undo()
    bm.buildFlag = true
    return done(nil, EMIT_TREE)
end

function pob_itemsRedo()
    local bm, it = ctx()
    if not it then return fail("no build") end
    it:Redo()
    bm.buildFlag = true
    return done(nil, EMIT_TREE)
end

---------------------------------------------------------------------------
-- 6.2 Lists: all items (ItemListControl), Uniques / Rare Templates DB
-- (ItemDBControl), shared items + shared item sets (SharedItemListControl,
-- SharedItemSetListControl). Drag-drop payloads are { kind, key }:
--   "item"   key = item id (itemsTab.items)
--   "unique" key = item name (main.uniqueDB.list is keyed by name)
--   "rare"   key = item name (main.rareDB.list)
--   "shared" key = 1-based index into main.sharedItemList
-- DB and shared items are never mutated: every path that adds one to the
-- build copies it with new("Item", raw) first, as legacy does.
---------------------------------------------------------------------------

local function resolve(it, kind, key)
    if kind == "item" then return it.items[tonumber(key) or -1] end
    if kind == "unique" then return main.uniqueDB.list[key] end
    if kind == "rare" then return main.rareDB.list[key] end
    if kind == "shared" then return main.sharedItemList[tonumber(key) or -1] end
end

-- All-items rows: ItemListControl:GetRowValue adds "(Unused)" / "(Used in ..)".
local function itemRows(it)
    local ilc = it.controls.itemList
    local rows = { }
    for i, id in ipairs(it.itemOrderList) do
        local item = it.items[id]
        if item then
            rows[#rows + 1] = { key = id, label = ilc:GetRowValue(1, i, id), name = item.name }
        end
    end
    return rows
end

local function sharedRows()
    local rows = { }
    for i, item in ipairs(main.sharedItemList) do
        -- SharedItemListControl.lua:24-28
        rows[i] = { key = i, label = (colorCodes[item.rarity] or "^7") .. item.name, name = item.name }
    end
    return rows
end

-- The display item's tooltip is the LIVE `displayItemTooltip`, which every
-- legacy edit path refreshes itself (UpdateDisplayItemTooltip). It is only
-- regenerated here when the display item changed identity or a recalc
-- happened since (legacy never refreshes it on recalc; that is a stale-compare
-- bug not worth copying). AddItemTooltip runs compare calcs per slot, so it
-- must not run on every view refresh.
local dispKey = { }

local function markDisplayFresh(it)
    dispKey.item, dispKey.rev = it.displayItem, it.build.outputRevision
end

local VARIANT_CONTROLS = { "displayItemVariant", "displayItemAltVariant", "displayItemAltVariant2",
    "displayItemAltVariant3", "displayItemAltVariant4", "displayItemAltVariant5" }

local function shownCtl(ctl)
    local ok, shown = pcall(ctl.IsShown, ctl)
    return ok and shown and true or false
end

local function dropLabels(list)
    local out = { }
    for i, v in ipairs(list or { }) do out[i] = type(v) == "table" and (v.label or "") or tostring(v) end
    return out
end

-- Editor sections read back from the LIVE controls SetDisplayItem synced
-- (ItemsTab.lua:1671-1747): variants (:351-421), sockets / links (:423-472).
local function editorRecord(it)
    local d, c = it.displayItem, it.controls
    local variants = { }
    for n, name in ipairs(VARIANT_CONTROLS) do
        local ctl = c[name]
        if shownCtl(ctl) then
            variants[#variants + 1] = { n = n, list = dropLabels(ctl.list), sel = ctl.selIndex or 1 }
        end
    end
    local sockets = { }
    for i = 1, 6 do
        local drop, link = c["displayItemSocket" .. i], c["displayItemLink" .. i]
        sockets[i] = {
            shown = shownCtl(drop),
            sel = drop.selIndex or 1,
            linkShown = link ~= nil and shownCtl(link),
            link = link ~= nil and link.state and true or false,
        }
    end
    return {
        variants = variants,
        sockets = sockets,
        socketList = dropLabels(c.displayItemSocket1.list),
        socketSection = d.selectableSocketCount > 0,
        -- the "+" sits right of the last colour socket (ItemsTab.lua:457)
        addSocketShown = shownCtl(c.displayItemAddSocket),
        addSocketAt = #d.sockets - d.abyssalSocketCount,
    }
end

-- The display item (the Part 6.3 editor).
local function displayRecord(it)
    local d = it.displayItem
    if not d then return { shown = false } end
    if dispKey.item ~= d or dispKey.rev ~= it.build.outputRevision then
        it:UpdateDisplayItemTooltip()
        markDisplayFresh(it)
    end
    local lines = { }
    for _, l in ipairs(it.displayItemTooltip.lines or { }) do
        if l.text == nil then
            lines[#lines + 1] = { sep = true, size = l.size or 10 }
        else
            lines[#lines + 1] = { size = l.size or 14, text = l.text, center = (l.center or it.displayItemTooltip.center) and true or false }
        end
    end
    return {
        shown = true,
        name = d.name or "",
        -- ItemsTab.lua:327-329 addDisplayItem label
        addLabel = (d.id and it.items[d.id]) and "Save" or "Add to build",
        lines = lines,
        editor = editorRecord(it),
    }
end

-- Shift = second slot: the redirect ItemListControl / ItemDBControl OnSelClick
-- apply before equipping (ItemListControl.lua:164-176).
local function primarySlotFor(it, item, shift)
    local slotName = item:GetPrimarySlot()
    if not (slotName and it.slots[slotName]) then return nil end
    if it.slots[slotName].weaponSet == 1 and it.activeItemSet.useSecondWeaponSet then
        slotName = slotName .. " Swap"
    end
    if shift then
        local altSlot = slotName:gsub("1", "2")
        if it:IsItemValidForSlot(item, altSlot) then slotName = altSlot end
    end
    return slotName
end

function pob_itemsGetLists()
    local bm, it = ctx()
    if not it then return nil end
    return {
        items = itemRows(it),
        shared = sharedRows(),
        display = displayRecord(it),
    }
end

-- Item tooltip for any list row. AddItemTooltip reads SHIFT (slot number of
-- the compare), so the caller passes it explicitly.
function pob_itemsTooltip(kind, key, shift)
    local bm, it = ctx()
    local item = it and resolve(it, kind, key)
    if not item then return { lines = { } } end
    local dbMode = (kind == "unique" or kind == "rare") or nil
    return { lines = withKeys({ SHIFT = shift and true or false }, tipLines, function(tip)
        it:AddItemTooltip(tip, item, nil, dbMode)
    end) }
end

-- Ctrl+click. All items: ItemListControl.lua:161-185 (toggle in the primary
-- slot). DB: ItemDBControl.lua:320-346 (copy into the build, then equip).
-- Lifted because legacy reads IsKeyDown("CTRL"/"SHIFT").
function pob_itemsCtrlClick(kind, key, shift)
    local bm, it = ctx()
    local item = it and resolve(it, kind, key)
    if not item then return fail("no such item") end
    if kind == "item" then
        local slotName = primarySlotFor(it, item, shift)
        if not slotName then return fail("item has no slot") end
        local slot = it.slots[slotName]
        slot:SetSelItemId(slot.selItemId == item.id and 0 or item.id)
        it:PopulateSlots()
        it:AddUndoState()
        bm.buildFlag = true
        return done({ slotName = slotName }, EMIT_TREE)
    elseif kind == "unique" or kind == "rare" then
        local newItem = new("Item", item.raw)
        newItem:NormaliseQuality()
        it:AddItem(newItem, true)
        local slotName = primarySlotFor(it, newItem, shift)
        if slotName then it.slots[slotName]:SetSelItemId(newItem.id) end
        it:PopulateSlots()
        it:AddUndoState()
        bm.buildFlag = true
        return done({ slotName = slotName or "", itemId = newItem.id }, EMIT_TREE)
    end
    return fail("ctrl+click does nothing on this list")   -- SharedItemListControl.lua:55
end

-- Double-click: open the item as the display item (the 6.3 editor).
-- All items: a COPY holding the same id, so Save replaces in place
-- (ItemListControl.lua:186-189). DB / shared: CreateDisplayItemFromRaw
-- with normalise (ItemDBControl.lua:348, SharedItemListControl.lua:57).
function pob_itemsOpenForEdit(kind, key)
    local bm, it = ctx()
    local item = it and resolve(it, kind, key)
    if not item then return fail("no such item") end
    if kind == "item" then
        local newItem = new("Item", item:BuildRaw())
        newItem.id = item.id
        it:SetDisplayItem(newItem)
    else
        it:CreateDisplayItemFromRaw(item.raw, true)
    end
    markDisplayFresh(it)                  -- SetDisplayItem built the tooltip
    return { ok = it.displayItem ~= nil, _emit = { "items" } }
end

function pob_itemsCloseDisplayItem()
    local bm, it = ctx()
    if not it then return fail("no build") end
    it:SetDisplayItem()
    return { ok = true, _emit = { "items" } }
end

-- Ctrl+C on a row (OnSelCopy): build / shared rows copy BuildRaw, DB rows
-- their raw text; CRLF like legacy.
function pob_itemsCopy(kind, key)
    local bm, it = ctx()
    local item = it and resolve(it, kind, key)
    if not item then return fail("no such item") end
    local raw = (kind == "unique" or kind == "rare") and item.raw or item:BuildRaw()
    Copy((raw:gsub("\n", "\r\n")))
    return { ok = true }
end

-- The confirm question ItemListControl:OnSelDelete asks (ItemListControl.lua:
-- 198-232); "" = delete without asking.
function pob_itemsDeleteQuery(itemId)
    local bm, it = ctx()
    local item = it and it.items[tonumber(itemId) or -1]
    if not item then return fail("no such item") end
    local ilc = it.controls.itemList
    local equipSlot, equipSet = it:GetEquippedSlotForItem(item)
    local msg = ""
    if equipSlot then
        local inSet = equipSet and (" in set '" .. (equipSet.title or "Default") .. "'") or ""
        msg = item.name .. " is currently equipped in " .. equipSlot.label .. inSet .. ".\nAre you sure you want to delete it?"
    else
        local abyssSet = ilc:FindEquippedAbyssJewel(item.id, true)
        if abyssSet then
            msg = item.name .. " is currently equipped in an Abyssal Socket in set '" .. abyssSet .. "'.\nAre you sure you want to delete it?"
        else
            local equipTree = ilc:FindSocketedJewel(item.id, true)
            if equipTree then
                msg = item.name .. " is currently equipped in passive tree '" .. equipTree .. "'.\nAre you sure you want to delete it?"
            end
        end
    end
    return { ok = true, message = msg }
end

-- ItemsTab:DeleteItem (clears it from every slot, set and spec, then
-- PopulateSlots + AddUndoState).
function pob_itemsDeleteItem(itemId)
    local bm, it = ctx()
    local item = it and it.items[tonumber(itemId) or -1]
    if not item then return fail("no such item") end
    it:DeleteItem(item)
    return done(nil, EMIT_TREE)
end

-- "Delete All" (ItemListControl.lua:22-39; the confirm is asked in QML).
function pob_itemsDeleteAll()
    local bm, it = ctx()
    if not it then return fail("no build") end
    for _, slot in pairs(it.slots) do
        slot:SetSelItemId(0)
    end
    for _, spec in pairs(bm.treeTab.specList) do
        for nodeId in pairs(spec.jewels) do
            spec.jewels[nodeId] = 0
        end
    end
    wipeTable(it.itemOrderList)
    wipeTable(it.items)
    it:PopulateSlots()
    it:AddUndoState()
    bm.buildFlag = true
    return done(nil, EMIT_TREE)
end

-- "Delete Unused" (ItemListControl.lua:43-61).
function pob_itemsDeleteUnused()
    local bm, it = ctx()
    if not it then return fail("no build") end
    local ilc = it.controls.itemList
    local delList = { }
    for _, itemId in pairs(it.itemOrderList) do
        if not it:GetEquippedSlotForItem(it.items[itemId]) and not ilc:FindEquippedAbyssJewel(itemId, false)
                and not ilc:FindSocketedJewel(itemId, false) then
            t_insert(delList, itemId)
        end
    end
    for i = #delList, 1, -1 do
        it:DeleteItem(it.items[delList[i]], true)
    end
    for _, spec in pairs(bm.treeTab.specList) do
        spec:BuildClusterJewelGraphs()
    end
    it:PopulateSlots()
    it:AddUndoState()
    bm.buildFlag = true
    return done({ deleted = #delList }, EMIT_TREE)
end

-- "Sort" (ItemsTab:SortItemList; adds its own undo state).
function pob_itemsSortList()
    local bm, it = ctx()
    if not it then return fail("no build") end
    it:SortItemList()
    return { ok = true, _emit = { "items" } }
end

-- Drag-reorder inside the all-items list: ListControl moves the entry, then
-- ItemListControl:OnOrderChange adds an undo state (ItemListControl.lua:157).
function pob_itemsMoveItem(from, to)
    local bm, it = ctx()
    local list = it and it.itemOrderList
    from, to = tonumber(from), tonumber(to)
    if not list or not list[from] or not to or to < 1 or to > #list then return fail("bad index") end
    t_insert(list, to, t_remove(list, from))
    it:AddUndoState()
    return { ok = true, _emit = { "items" } }
end

-- Drop from the DB / shared list onto the all-items list at `index`
-- (ItemListControl:ReceiveDrag, ItemListControl.lua:147-155).
function pob_itemsDropOnList(kind, key, index)
    local bm, it = ctx()
    local value = it and resolve(it, kind, key)
    if not value or kind == "item" then return fail("not a droppable item") end
    local newItem = new("Item", value.raw)
    newItem:NormaliseQuality()
    index = tonumber(index)
    if index and (index < 1 or index > #it.itemOrderList + 1) then index = nil end
    it:AddItem(newItem, true, index)
    it:PopulateSlots()
    it:AddUndoState()
    return { ok = true, itemId = newItem.id, _emit = { "items" } }
end

-- ItemSlotControl:CanReceiveDrag / ReceiveDrag (ItemSlotControl.lua:114-130).
function pob_itemsCanDropOnSlot(slotName, kind, key)
    local bm, it = ctx()
    local value = it and resolve(it, kind, key)
    return value ~= nil and it.slots[slotName] ~= nil and it:IsItemValidForSlot(value, slotName) and true or false
end

function pob_itemsDropOnSlot(slotName, kind, key)
    local bm, it = ctx()
    local value = it and resolve(it, kind, key)
    local slot = it and it.slots[slotName]
    if not value or not slot then return fail("no such item or slot") end
    if not it:IsItemValidForSlot(value, slotName) then return fail("item does not fit " .. slotName) end
    if value.id and it.items[value.id] == value then
        slot:SetSelItemId(value.id)
    else
        local newItem = new("Item", value.raw)
        newItem:NormaliseQuality()
        it:AddItem(newItem, true)
        slot:SetSelItemId(newItem.id)
    end
    it:PopulateSlots()
    it:AddUndoState()
    bm.buildFlag = true
    return done(nil, EMIT_TREE)
end

-- Sidebar minion dropdown (Animate Guardian's item sets) as a drop target
-- (Build.lua:548-557): accepts an item whose primary slot the minion uses,
-- then EquipItemInSet into the set the dropdown shows. EquipItemInSet copies
-- items that are not in the build (DB / shared) itself.
function pob_itemsCanDropOnMinion(kind, key)
    local bm, it = ctx()
    local value = it and resolve(it, kind, key)
    if not value then return false end
    local ok, uses = pcall(function()
        local sg = bm.skillsTab.socketGroupList[bm.mainSocketGroup]
        local minionUses = sg.displaySkillList[sg.mainActiveSkill].activeEffect.grantedEffect.minionUses
        return minionUses and minionUses[value:GetPrimarySlot()]
    end)
    return ok and uses and true or false
end

function pob_itemsDropOnMinion(kind, key, itemSetId, shift)
    local bm, it = ctx()
    local value = it and resolve(it, kind, key)
    itemSetId = tonumber(itemSetId)
    if not value or not (itemSetId and it.itemSets[itemSetId]) then return fail("no such item or set") end
    withKeys({ SHIFT = shift and true or false }, function()
        it:EquipItemInSet(value, itemSetId)
    end)
    return done(nil, EMIT_TREE)
end

-- Shared items (SharedItemListControl). Drop from the build / DB list:
-- ReceiveDrag (SharedItemListControl.lua:44-53) copies via BuildRaw and
-- normalises quality only for items that are not in a build. Legacy inserts
-- at `selDragIndex or #list` (BEFORE the last row when dropped below the
-- list); here a drop past the end appends.
function pob_itemsDropOnShared(kind, key, index)
    local bm, it = ctx()
    local value = it and resolve(it, kind, key)
    if not value or kind == "shared" then return fail("not a droppable item") end
    local newItem = new("Item", value:BuildRaw())
    if not value.id then newItem:NormaliseQuality() end
    local list = main.sharedItemList
    index = tonumber(index)
    if not index or index < 1 or index > #list + 1 then index = #list + 1 end
    t_insert(list, index, newItem)
    return { ok = true, index = index, _emit = { "items" } }
end

-- Drag-reorder inside the shared list (plain ListControl move).
function pob_itemsMoveShared(from, to)
    local list = main.sharedItemList
    from, to = tonumber(from), tonumber(to)
    if not list[from] or not to or to < 1 or to > #list then return fail("bad index") end
    t_insert(list, to, t_remove(list, from))
    return { ok = true, _emit = { "items" } }
end

function pob_itemsDeleteShared(index)
    local list = main.sharedItemList
    index = tonumber(index)
    if not list[index] then return fail("bad index") end
    t_remove(list, index)                   -- SharedItemListControl.lua:68
    return { ok = true, _emit = { "items" } }
end

-- Shared item sets (SharedItemSetListControl), shown in Manage Item Sets.
function pob_itemsGetSharedSets()
    local sets = { }
    for i, s in ipairs(main.sharedItemSetList) do
        sets[i] = { title = s.title or "Default", rawTitle = s.title or "", listLabel = s.title or "Default" }
    end
    return { sets = sets }
end

-- SharedItemSetListControl:AddValueTooltip (SharedItemSetListControl.lua:53-64).
function pob_itemsSharedSetTooltip(index)
    local bm, it = ctx()
    local s = main.sharedItemSetList[tonumber(index) or -1]
    if not (it and s) then return { lines = { } } end
    return { lines = tipLines(function(tip)
        for _, slot in ipairs(it.orderedSlots) do
            if not slot.nodeId then
                local item = s.slots[slot.slotName]
                if item then
                    tip:AddLine(16, string.format("^7%s: %s%s", it.slots[slot.slotName].label, colorCodes[item.rarity], item.name))
                end
            end
        end
    end) }
end

-- Drag a build set onto the shared list (SharedItemSetListControl.lua:74-95).
function pob_itemsShareSet(setIndex, at)
    local bm, it = ctx()
    local value = it and it.itemSets[it.itemSetOrderList[tonumber(setIndex) or -1] or -1]
    if not value then return fail("no such set") end
    local shared = { title = value.title, slots = { } }
    for slotName, slot in pairs(it.slots) do
        if not slot.nodeId then
            if value ~= it.activeItemSet then slot = value[slotName] end
            if slot.selItemId ~= 0 then
                local item = it.items[slot.selItemId]
                local newItem = new("Item", item:BuildRaw())
                if not value.id then newItem:NormaliseQuality() end
                shared.slots[slotName] = newItem
            end
        end
    end
    local list = main.sharedItemSetList
    at = tonumber(at)
    if not at or at < 1 or at > #list + 1 then at = #list + 1 end
    t_insert(list, at, shared)
    return { ok = true, index = at }
end

-- Drag a shared set onto the build's set list (ItemSetListControl.lua:93-106).
-- Legacy skips PopulateSlots / SyncLoadouts here; both are added.
function pob_itemsImportSharedSet(sharedIndex, at)
    local bm, it = ctx()
    local value = it and main.sharedItemSetList[tonumber(sharedIndex) or -1]
    if not value then return fail("no such shared set") end
    local itemSet = it:NewItemSet()
    itemSet.title = value.title
    for slotName, item in pairs(value.slots) do
        local newItem = new("Item", item.raw)
        newItem:NormaliseQuality()
        it:AddItem(newItem, true)
        itemSet[slotName].selItemId = newItem.id
    end
    local list = it.itemSetOrderList
    at = tonumber(at)
    if not at or at < 1 or at > #list + 1 then at = #list + 1 end
    t_insert(list, at, itemSet.id)
    it:PopulateSlots()
    it:AddUndoState()
    syncLoadouts(bm)
    return { ok = true, index = at, _emit = { "build", "items" } }
end

function pob_itemsRenameSharedSet(index, title)
    local bm, it = ctx()
    local s = main.sharedItemSetList[tonumber(index) or -1]
    if not s or not tostring(title or ""):match("%S") then return fail("bad index or empty title") end
    s.title = tostring(title)
    if it then it.modFlag = true end        -- SharedItemSetListControl.lua:36-37
    return { ok = true }
end

function pob_itemsDeleteSharedSet(index)
    index = tonumber(index)
    if not main.sharedItemSetList[index] then return fail("bad index") end
    t_remove(main.sharedItemSetList, index)
    return { ok = true }
end

-- Uniques / Rare Templates DB (ItemDBControl). Filters are the LIVE legacy
-- controls (selIndex / search.buf); the list is legacy's ListBuilder
-- coroutine, pumped by pob_itemsDBStep because its only driver,
-- ItemDBControl:Draw, never runs in the host.
local DB_FILTERS = { "slot", "type", "sort", "league", "requirement", "obtainable", "searchMode" }

local function dbCtl(which)
    local bm, it = ctx()
    if not it then return nil end
    return which == "rare" and it.controls.rareDB or it.controls.uniqueDB, it, bm
end

local function dbBuilding(db, it)
    return (db.listBuilder ~= nil or db.listBuildFlag or it.build.outputRevision ~= db.listOutputRevision) and true or false
end

function pob_itemsDBState(which)
    local db, it = dbCtl(which)
    if not db then return nil end
    local res = {
        which = which,
        selectDB = it.controls.selectDB.selIndex,
        loading = db.db.loading and true or false,
        search = db.controls.search.buf,
        filters = { },
        rows = { },
    }
    res.building = res.loading or dbBuilding(db, it)
    res.text = res.loading and "^7Loading..." or db.defaultText or ""
    for _, name in ipairs(DB_FILTERS) do
        local c = db.controls[name]
        if c then
            local labels = { }
            for i, v in ipairs(c.list) do labels[i] = type(v) == "table" and (v.label or "") or tostring(v) end
            res.filters[name] = { list = labels, sel = c.selIndex }
        end
    end
    if not res.building then
        for i, item in ipairs(db.list) do
            res.rows[i] = { key = item.name, label = db:GetRowValue(1, i, item), name = item.name }
        end
    end
    return res
end

-- Set one filter. `name` is a DB_FILTERS dropdown (1-based index), "search"
-- (text) or "selectDB" (the Uniques / Rare Templates switch, 1 or 2). Each
-- mirrors the control's own callback: listBuildFlag, or SetSortMode.
function pob_itemsDBSetFilter(which, name, value)
    local db, it = dbCtl(which)
    if not db then return fail("no build") end
    if name == "selectDB" then
        it.controls.selectDB.selIndex = (tonumber(value) == 2) and 2 or 1
        return { ok = true }
    elseif name == "search" then
        db.controls.search.buf = tostring(value or "")
        db.listBuildFlag = true
        return { ok = true }
    end
    local c = db.controls[name]
    local idx = tonumber(value)
    if not c or not isValueInArray(DB_FILTERS, name) or not idx or not c.list[idx] then
        return fail("bad filter " .. tostring(name))
    end
    c.selIndex = idx
    c.selFunc(idx, c.list[idx])
    return { ok = true }
end

-- One slice of work: the Main.lua LoadItems coroutine while the DB is
-- loading (pairsYield: ~20 ms), then ItemDBControl:Draw's list-build part
-- (ItemDBControl.lua:274-296): restart on outputRevision / listBuildFlag,
-- resume ListBuilder once (it yields every 50 ms on the stat-sort path with
-- defaultText "^7Sorting... (N%)"). Driven by a job-scoped QML Timer.
function pob_itemsDBStep(which)
    local db, it = dbCtl(which)
    if not db then return { running = false } end
    if db.db.loading then
        local loader = main.onFrameFuncs and main.onFrameFuncs.LoadItems
        if not loader then return { running = false, error = "item DB loader missing" } end
        local ok, err = pcall(loader)
        if not ok then return { running = false, error = tostring(err) } end
        return { running = true, loading = true, text = "^7Loading..." }
    end
    if not db.leaguesAndTypesLoaded then db:LoadLeaguesAndTypes() end
    if it.build.outputRevision ~= db.listOutputRevision then db.listBuildFlag = true end
    if db.listBuildFlag then
        db.listBuildFlag = false
        wipeTable(db.list)
        db.listBuilder = coroutine.create(db.ListBuilder)
        db.listOutputRevision = it.build.outputRevision
    end
    local finished = false
    if db.listBuilder then
        local ok, err = coroutine.resume(db.listBuilder, db)
        if not ok then
            db.listBuilder = nil
            return { running = false, error = tostring(err) }
        end
        if coroutine.status(db.listBuilder) == "dead" then
            db.listBuilder = nil
            finished = true
        end
    end
    return { running = db.listBuilder ~= nil, finished = finished, text = db.defaultText or "" }
end

---------------------------------------------------------------------------
-- 6.3 Display-item editor. The LIVE legacy controls stay the single source
-- of truth: set the control's state, then call its own closure (selFunc /
-- changeFunc / onClick), which edits itemsTab.displayItem, rebuilds it and
-- refreshes displayItemTooltip. Edits are not undo steps and do not recalc
-- (the display item is not in the build) until Save / Add to build.
---------------------------------------------------------------------------

local function displayEdited(it)
    markDisplayFresh(it)
    return { ok = true, _emit = { "items" } }
end

-- Variant dropdown `n` (1 = Variant, 2..6 = Alt variants; ItemsTab.lua:362-421).
function pob_itemsDisplaySetVariant(n, index)
    local bm, it = ctx()
    local ctl = it and it.displayItem and it.controls[VARIANT_CONTROLS[tonumber(n) or 0] or ""]
    index = tonumber(index)
    if not ctl or not index or not ctl.list[index] then return fail("bad variant") end
    ctl.selIndex = index
    ctl.selFunc(index, ctl.list[index])
    return displayEdited(it)
end

-- Socket colour dropdown i (ItemsTab.lua:423-431); colourIndex into socketDropList.
function pob_itemsDisplaySetSocket(i, colourIndex)
    local bm, it = ctx()
    local drop = it and it.displayItem and it.controls["displayItemSocket" .. (tonumber(i) or 0)]
    colourIndex = tonumber(colourIndex)
    if not drop or not shownCtl(drop) or not colourIndex or not drop.list[colourIndex] then return fail("bad socket") end
    drop.selIndex = colourIndex
    drop.selFunc(colourIndex, drop.list[colourIndex])
    return displayEdited(it)
end

-- Link checkbox between socket i and i+1 (ItemsTab.lua:436-452).
function pob_itemsDisplaySetLink(i, state)
    local bm, it = ctx()
    local link = it and it.displayItem and it.controls["displayItemLink" .. (tonumber(i) or 0)]
    if not link or not shownCtl(link) then return fail("bad link") end
    link.state = state and true or false
    link.changeFunc(link.state)
    return displayEdited(it)
end

-- "+" (ItemsTab.lua:457-472).
function pob_itemsDisplayAddSocket()
    local bm, it = ctx()
    local btn = it and it.displayItem and it.controls.displayItemAddSocket
    if not btn or not shownCtl(btn) then return fail("no socket to add") end
    btn.onClick()
    return displayEdited(it)
end

-- "Add to build" / "Save" (ItemsTab:AddDisplayItem, ItemsTab.lua:1519-1527):
-- a new item auto-equips into the first empty valid slot; an existing id
-- replaces the item in place.
function pob_itemsAddDisplayItem()
    local bm, it = ctx()
    if not (it and it.displayItem) then return fail("no display item") end
    it:AddDisplayItem()
    return done(nil, EMIT_TREE)
end

-- Edit-text popup (ItemsTab:EditDisplayItemText, ItemsTab.lua:2225-2273).
-- Mirrors ItemsTab.lua:20-26 `rarityDropList` (file-local in legacy).
local RARITIES = { "NORMAL", "MAGIC", "RARE", "UNIQUE", "RELIC" }

local function editTextRaw(text, rarityIndex)
    -- buildRaw (ItemsTab.lua:2227-2234)
    text = tostring(text or "")
    if text:match("^Item Class: .*\nRarity: ") or text:match("^Rarity: ") then return text end
    return "Rarity: " .. (RARITIES[tonumber(rarityIndex) or 3] or "RARE") .. "\n" .. text
end

function pob_itemsEditTextInit()
    local bm, it = ctx()
    if not it then return nil end
    local labels = { }
    for i, r in ipairs(RARITIES) do labels[i] = (colorCodes[r] or "^7") .. r:sub(1, 1) .. r:sub(2):lower() end
    local d = it.displayItem
    local sel = 3
    if d then sel = isValueInArray(RARITIES, d.rarity) or 3 end
    return {
        isEdit = d ~= nil,
        title = d and "Edit Item Text" or "Create Custom Item from Text",
        saveLabel = d and "Save" or "Create",
        text = d and (d:BuildRaw():gsub("Rarity: %w+\n", "")) or "",
        rarities = labels,
        raritySel = sel,
    }
end

-- Live validity + the Save button tooltip (ItemsTab.lua:2250-2267).
function pob_itemsEditTextCheck(text, rarityIndex)
    local bm, it = ctx()
    if not it then return { valid = false, lines = { } } end
    local item = new("Item", editTextRaw(text, rarityIndex))
    if item.base then
        return { valid = true, lines = tipLines(function(tip) it:AddItemTooltip(tip, item, nil, true) end) }
    end
    return { valid = false, lines = tipLines(function(tip)
        tip:AddLine(14, "The item is invalid.")
        tip:AddLine(14, "Check that the item's title and base name are in the correct format.")
        tip:AddLine(14, "For Rare and Unique items, the first 2 lines must be the title and base name. E.g.:")
        tip:AddLine(14, "Abberath's Horn")
        tip:AddLine(14, "Goat's Horn")
        tip:AddLine(14, "For Normal and Magic items, the base name must be somewhere in the first line. E.g.:")
        tip:AddLine(14, "Scholar's Platinum Kris of Joy")
    end) }
end

-- Save / Create (ItemsTab.lua:2244-2251): re-create the display item from the
-- text, keeping its id so Save still replaces in place.
function pob_itemsEditTextSave(text, rarityIndex, alsoAdd)
    local bm, it = ctx()
    if not it then return fail("no build") end
    local raw = editTextRaw(text, rarityIndex)
    if not new("Item", raw).base then return fail("The item is invalid.") end
    local id = it.displayItem and it.displayItem.id
    it:CreateDisplayItemFromRaw(raw, not it.displayItem)
    it.displayItem.id = id
    if alsoAdd then
        it:AddDisplayItem()
        return done(nil, EMIT_TREE)
    end
    return displayEdited(it)
end

---------------------------------------------------------------------------
-- Selftests
---------------------------------------------------------------------------

local function itSnapshot(bm, it)
    return {
        state = it:CreateUndoState(),
        undo = copyTable(it.undo, true), redo = copyTable(it.redo, true),
        modFlag = it.modFlag,
        useSecond = it.activeItemSet.useSecondWeaponSet,
        main = bm.mainSocketGroup,
        active = { },
    }
end

local function itRestore(bm, it, snap)
    it:RestoreUndoState(snap.state)
    it.undo, it.redo, it.modFlag = snap.undo, snap.redo, snap.modFlag
    it.activeItemSet.useSecondWeaponSet = snap.useSecond
    bm.mainSocketGroup = snap.main
    -- SetActiveItemSet writes live slot state back into the set it leaves.
    for slotName, slot in pairs(it.slots) do
        local e = it.activeItemSet[slotName]
        if not slot.nodeId and e then slot.active = e.active end
    end
    it:SetActiveItemSet(snap.state.activeItemSetId)
    bm.buildFlag = true
    pob_recalculate()
end

local function slotOf(s, name)
    for _, r in ipairs(s.slots) do
        if r.slotName == name then return r end
    end
end

local function finish(res, ok, err)
    res.ok = ok
    if not ok then res.error = tostring(err) end
    for k, v in pairs(res) do
        if type(v) == "boolean" and not v then res.ok = false end
    end
    res.restored = true
    return res
end

-- Part 6.1: item sets, weapon sets, slot panel state, equip rules, flasks.
function pob_selftestItemsSlots()
    local bm, it = ctx()
    if not it then return { ok = false, error = "no itemsTab" } end
    local snap = itSnapshot(bm, it)
    local res = { }
    local ok, err = pcall(function()
        -- Fixtures: a ring, a helmet, a one-hand sword, a flask.
        local function add(raw)
            local item = new("Item", raw)
            if not item.base then error("fixture base missing: " .. raw:match("\n(.-)\n")) end
            item:NormaliseQuality()
            it:AddItem(item, true)
            return item
        end
        local ring = add("Rarity: Rare\nST Ring\nGold Ring\n")
        local sword = add("Rarity: Rare\nST Sword\nRusted Sword\n")
        it:PopulateSlots()
        it:AddUndoState()           -- AddDisplayItem does this after AddItem

        local s = pob_itemsGetState()
        local r1, r2, r3 = slotOf(s, "Ring 1"), slotOf(s, "Ring 2"), slotOf(s, "Ring 3")
        res.slotsListed = #s.slots == #it.orderedSlots
        res.ring3Hidden = r3 ~= nil and r3.shown == (it.slots["Ring 3"]:IsShown() and true or false)
        res.flaskSlots = slotOf(s, "Flask 1") ~= nil and slotOf(s, "Flask 1").isFlask
            and slotOf(s, "Flask 5") ~= nil
        res.abyssalListed = slotOf(s, "Helmet Abyssal Socket 6") ~= nil
            and slotOf(s, "Weapon 1 Swap Abyssal Socket 1") ~= nil
        res.abyssalInactive = slotOf(s, "Helmet Abyssal Socket 1").inactive == true
            and slotOf(s, "Helmet Abyssal Socket 1").shown == false

        -- Options obey IsItemValidForSlot and follow the all-items order.
        local function hasOpt(rec, id)
            for _, o in ipairs(rec.options) do if o.id == id then return true end end
            return false
        end
        res.optionsValid = hasOpt(r1, ring.id) and not hasOpt(r1, sword.id)
            and hasOpt(slotOf(s, "Weapon 1"), sword.id) and r1.options[1].id == 0

        -- Equip: ring in Ring 1, rejected in Helmet, undo/redo round trip.
        local e = pob_itemsEquip("Ring 1", ring.id)
        res.equipOk = e.ok and it.activeItemSet["Ring 1"].selItemId == ring.id
            and slotOf(pob_itemsGetState(), "Ring 1").selItemId == ring.id
        res.equipInvalidRefused = not pob_itemsEquip("Helmet", ring.id).ok
            and it.activeItemSet["Helmet"].selItemId == 0
        pob_itemsUndo()
        res.undoUnequips = it.slots["Ring 1"].selItemId == 0 and it.items[ring.id] ~= nil
        pob_itemsRedo()
        res.redoEquips = it.slots["Ring 1"].selItemId == ring.id

        -- Same item cannot sit in both rings via EquipItemInSet + shift.
        pob_itemsEquip("Ring 1", 0)
        pob_itemsEquipInSet(ring.id, s.activeSet, true)
        res.shiftSecondSlot = it.slots["Ring 2"].selItemId == ring.id and it.slots["Ring 1"].selItemId == 0
        pob_itemsEquipInSet(ring.id, s.activeSet, false)
        res.noShiftFirstSlot = it.slots["Ring 1"].selItemId == ring.id
        res.keysRestored = IsKeyDown("SHIFT") == false

        -- Weapon sets: I / II flip useSecondWeaponSet; the weapon lives in the
        -- swap slot of set II only; main socket group follows.
        pob_itemsEquip("Weapon 1", sword.id)
        local sg = bm.skillsTab.socketGroupList
        local savedSlot = sg[1] and sg[1].slot
        if sg[1] then sg[1].slot = "Weapon 1" end
        bm.mainSocketGroup = 1
        pob_itemsSetWeaponSet(2)
        local s2 = pob_itemsGetState()
        res.setII = s2.useSecondWeaponSet == true
            and slotOf(s2, "Weapon 1").shown == false and slotOf(s2, "Weapon 1 Swap").shown == true
        res.setIILocked = pob_itemsSetWeaponSet(2).ok and it.activeItemSet.useSecondWeaponSet == true
        pob_itemsEquip("Weapon 1 Swap", sword.id)
        res.swapEquipOk = it.activeItemSet["Weapon 1 Swap"].selItemId == sword.id
        pob_itemsSetWeaponSet(1)
        res.setI = pob_itemsGetState().useSecondWeaponSet == false
        if sg[1] then sg[1].slot = savedSlot end

        -- Flask active checkbox persists into the set.
        local flask = add("Rarity: Magic\nLife Flask\nSmall Life Flask\n")
        it:PopulateSlots()
        pob_itemsEquip("Flask 1", flask.id)
        pob_itemsSetFlaskActive("Flask 1", true)
        res.flaskActive = it.activeItemSet["Flask 1"].active == true
            and slotOf(pob_itemsGetState(), "Flask 1").flaskActive == true
        res.flaskNotForRing = not pob_itemsSetFlaskActive("Ring 1", true).ok

        -- Item sets: new / select / copy / rename / move / delete.
        local nSets = #it.itemSetOrderList
        local firstId = it.itemSetOrderList[1]
        local n = pob_itemsNewSet("ST Set")
        res.newSetOk = n.ok and #it.itemSetOrderList == nSets + 1
            and it.itemSets[it.itemSetOrderList[n.index]].title == "ST Set"
        pob_itemsSetActiveSet(n.index)
        res.selectSetOk = it.activeItemSetId == it.itemSetOrderList[n.index]
            and it.slots["Ring 1"].selItemId == 0
        pob_itemsSetActiveSet(1)
        res.switchBackOk = it.slots["Ring 1"].selItemId == ring.id and it.slots["Flask 1"].active == true
        local cp = pob_itemsCopySet(1, "ST Copy")
        local cpSet = it.itemSets[it.itemSetOrderList[cp.index]]
        res.copySetOk = cp.ok and cpSet.id ~= firstId and cpSet["Ring 1"].selItemId == ring.id
            and cpSet["Ring 1"] ~= it.itemSets[firstId]["Ring 1"]
        pob_itemsRenameSet(cp.index, "ST Renamed")
        res.renameSetOk = cpSet.title == "ST Renamed" and not pob_itemsRenameSet(cp.index, "  ").ok
        local movedId = it.itemSetOrderList[cp.index]
        pob_itemsMoveSet(cp.index, 1)
        res.moveSetOk = it.itemSetOrderList[1] == movedId
        local tip = pob_itemsSetTooltip(1)
        local tipText = ""
        for _, l in ipairs(tip.lines) do tipText = tipText .. (l.text or "") end
        res.setTooltipOk = tipText:find("ST Ring", 1, true) ~= nil
        local activeId = it.activeItemSetId
        pob_itemsDeleteSet(isValueInArray(it.itemSetOrderList, activeId))
        res.deleteActiveSetOk = it.itemSets[activeId] == nil and it.itemSets[it.activeItemSetId] ~= nil
            and it.items[ring.id] ~= nil
        res.setListOk = #pob_itemsGetSetList().sets == #it.itemSetOrderList
        res.lastSetRefused = (function()
            while #it.itemSetOrderList > 1 do pob_itemsDeleteSet(1) end
            return not pob_itemsDeleteSet(1).ok
        end)()
    end)
    itRestore(bm, it, snap)
    -- restoring the undo state re-creates items; drop the fixtures we added.
    return finish(res, ok, err)
end

local function linesText(lines)
    local t = { }
    for _, l in ipairs(lines or { }) do t[#t + 1] = l.text or "" end
    return table.concat(t, "\n")
end

local function dbSnapshot(db)
    local s = { search = db.controls.search.buf, sortMode = db.sortMode }
    for _, name in ipairs(DB_FILTERS) do
        if db.controls[name] then s[name] = db.controls[name].selIndex end
    end
    return s
end

local function dbRestore(db, s)
    db.controls.search.buf = s.search
    for _, name in ipairs(DB_FILTERS) do
        if db.controls[name] and name ~= "sort" then db.controls[name].selIndex = s[name] end
    end
    db:SetSortMode(s.sortMode)      -- rebuilds sortOrder, re-selects the sort row
    db.listBuildFlag = true
end

local function dbRun(which, maxSteps)
    local r, steps = nil, 0
    repeat
        r = pob_itemsDBStep(which)
        steps = steps + 1
    until not r.running or steps >= maxSteps
    return r, steps
end

-- Part 6.2: all-items list, Uniques / Rare Templates DB (pumped loader +
-- list builder, filters, stat sort), shared items and shared item sets, and
-- the drop targets (list, slot, shared, minion dropdown).
function pob_selftestItemsLists()
    local bm, it = ctx()
    if not it then return { ok = false, error = "no itemsTab" } end
    local snap = itSnapshot(bm, it)
    local uniq, rare = it.controls.uniqueDB, it.controls.rareDB
    local uSnap, rSnap = dbSnapshot(uniq), dbSnapshot(rare)
    local selectDB = it.controls.selectDB.selIndex
    -- Shared lists persist through main:SaveSettings: restore both in place
    -- (the list controls hold these exact tables). Never call SaveSettings.
    local sharedItems = copyTable(main.sharedItemList, true)
    local sharedSets = copyTable(main.sharedItemSetList, true)
    local savedCopy = Copy
    local res = { }
    local ok, err = pcall(function()
        local copied
        Copy = function(text) copied = text end   -- the real Copy() crashes pob-qt --headless
        local function add(raw)
            local item = new("Item", raw)
            if not item.base then error("fixture base missing: " .. raw:match("\n(.-)\n")) end
            item:NormaliseQuality()
            it:AddItem(item, true)
            return item
        end
        local ring = add("Rarity: Rare\nLT Ring\nGold Ring\n")
        local ring2 = add("Rarity: Rare\nLT Other Ring\nIron Ring\n")
        it:PopulateSlots()
        it:AddUndoState()
        local function row(id)
            for _, r in ipairs(pob_itemsGetLists().items) do if r.key == id then return r end end
            return { label = "" }
        end
        local function pos(id) return isValueInArray(it.itemOrderList, id) or 0 end
        res.rowUnused = row(ring.id).label:find("(Unused)", 1, true) ~= nil
        res.rowsListed = #pob_itemsGetLists().items == #it.itemOrderList

        -- Ctrl+click toggles the primary slot; Shift targets the second slot.
        pob_itemsCtrlClick("item", ring.id, false)
        res.ctrlEquips = it.slots["Ring 1"].selItemId == ring.id
            and row(ring.id).label:find("(Unused)", 1, true) == nil
        pob_itemsCtrlClick("item", ring.id, false)
        res.ctrlToggles = it.slots["Ring 1"].selItemId == 0
        pob_itemsCtrlClick("item", ring.id, true)
        res.shiftSecondSlot = it.slots["Ring 2"].selItemId == ring.id and it.slots["Ring 1"].selItemId == 0

        -- Delete asks only for a used item (ItemListControl:OnSelDelete).
        res.deleteAsks = pob_itemsDeleteQuery(ring.id).message:find("equipped in Ring 2", 1, true) ~= nil
        res.deleteNoAsk = pob_itemsDeleteQuery(ring2.id).message == ""

        -- Tooltip with an explicit SHIFT, then IsKeyDown is back; Copy is CRLF.
        res.tooltipOk = linesText(pob_itemsTooltip("item", ring.id, true).lines):find("LT Ring", 1, true) ~= nil
        res.keysRestored = IsKeyDown("SHIFT") == false
        pob_itemsCopy("item", ring.id)
        res.copyCRLF = copied ~= nil and copied:find("LT Ring\r\n", 1, true) ~= nil

        -- Reorder (+ undo), then Sort puts the equipped ring first.
        local n = #it.itemOrderList
        pob_itemsMoveItem(pos(ring2.id), 1)
        res.moveOk = it.itemOrderList[1] == ring2.id
        pob_itemsUndo()
        res.moveUndo = it.itemOrderList[n] == ring2.id
        pob_itemsMoveItem(pos(ring2.id), 1)
        pob_itemsSortList()
        res.sortOk = #it.itemOrderList == n and pos(ring.id) < pos(ring2.id)

        -- Double-click opens an editable COPY with the same id.
        pob_itemsOpenForEdit("item", ring.id)
        res.editCopy = it.displayItem ~= nil and it.displayItem.id == ring.id and it.displayItem ~= it.items[ring.id]
        local d = pob_itemsGetLists().display
        res.displayShown = d.shown == true and d.addLabel == "Save" and #d.lines > 0
        pob_itemsCloseDisplayItem()
        res.editClosed = it.displayItem == nil and pob_itemsGetLists().display.shown == false

        -- Delete Unused keeps the equipped ring; Delete All; undo.
        pob_itemsDeleteUnused()
        res.deleteUnusedOk = it.items[ring2.id] == nil and it.items[ring.id] ~= nil
        pob_itemsDeleteAll()
        res.deleteAllOk = next(it.items) == nil and #it.itemOrderList == 0 and it.slots["Ring 2"].selItemId == 0
        pob_itemsUndo()
        res.deleteAllUndo = it.items[ring.id] ~= nil and it.itemSets[it.activeItemSetId]["Ring 2"].selItemId == ring.id

        -- Uniques DB: loader and list builder run only when pumped.
        local r = dbRun("unique", 20000)
        res.dbLoaded = not main.uniqueDB.loading and not r.running and r.error == nil
        res.leaguesLoaded = uniq.leaguesAndTypesLoaded == true and #uniq.typeList > 5
        local all = #pob_itemsDBState("unique").rows
        pob_itemsDBSetFilter("unique", "slot", isValueInArray(uniq.slotList, "Belt"))
        dbRun("unique", 100)
        local belts = pob_itemsDBState("unique").rows
        local allBelts = #belts > 1
        for _, b in ipairs(belts) do
            if main.uniqueDB.list[b.key]:GetPrimarySlot() ~= "Belt" then allBelts = false end
        end
        res.dbSlotFilter = allBelts and #belts < all
        res.dbCounts = all .. "/" .. #belts
        pob_itemsDBSetFilter("unique", "searchMode", 2)
        pob_itemsDBSetFilter("unique", "search", "headhunter")
        dbRun("unique", 100)
        local hh = pob_itemsDBState("unique").rows
        res.dbSearch = #hh >= 1 and hh[1].name:find("Headhunter", 1, true) ~= nil
        pob_itemsDBSetFilter("unique", "search", "")

        -- Stat sort over the belt subset: calcFunc per item x slot, sliced.
        local sortIdx
        for i, v in ipairs(uniq.controls.sort.list) do if v.stat == "Life" then sortIdx = i end end
        res.sortSet = pob_itemsDBSetFilter("unique", "sort", sortIdx).ok and uniq.sortDetail.stat == "Life"
        local sr, steps = dbRun("unique", 20000)
        local sorted = pob_itemsDBState("unique").rows
        local desc = #sorted == #belts
        for i = 2, #sorted do
            local a = main.uniqueDB.list[sorted[i - 1].key].measuredPower
            local b = main.uniqueDB.list[sorted[i].key].measuredPower
            if not (type(a) == "number" and type(b) == "number" and a >= b) then desc = false end
        end
        res.statSortDone = sr.error == nil and not sr.running
        res.statSortOrdered = desc
        res.statSortSteps = steps

        -- Ctrl+click a DB row copies it into the build and equips it.
        local beltName = sorted[1].key
        local dbItem = main.uniqueDB.list[beltName]
        local before = #it.itemOrderList
        local c = pob_itemsCtrlClick("unique", beltName, false)
        res.dbCtrlEquips = c.ok and #it.itemOrderList == before + 1 and it.slots["Belt"].selItemId == c.itemId
            and it.items[c.itemId] ~= dbItem and dbItem.id == nil

        -- Drop targets: the list (at an index), a slot (valid only).
        local d1 = pob_itemsDropOnList("unique", beltName, 1)
        res.dropOnListOk = d1.ok and it.itemOrderList[1] == d1.itemId and dbItem.id == nil
        res.canDropSlot = pob_itemsCanDropOnSlot("Belt", "unique", beltName)
            and not pob_itemsCanDropOnSlot("Helmet", "unique", beltName)
        res.dropOnSlotOk = pob_itemsDropOnSlot("Belt", "item", d1.itemId).ok and it.slots["Belt"].selItemId == d1.itemId
            and not pob_itemsDropOnSlot("Helmet", "item", d1.itemId).ok

        -- Rare Templates DB (no league / sort filters).
        local rr = dbRun("rare", 20000)
        local rst = pob_itemsDBState("rare")
        res.rareDBOk = rr.error == nil and not rst.loading and #rst.rows > 0 and rst.filters.league == nil

        -- Minion dropdown drop: a DB item is copied into the given set.
        local ns = pob_itemsNewSet("LT Minion")
        local setId = it.itemSetOrderList[ns.index]
        pob_itemsDropOnMinion("unique", beltName, setId, false)
        local mId = it.itemSets[setId]["Belt"].selItemId
        res.minionDropOk = mId ~= 0 and it.items[mId] ~= nil and it.items[mId] ~= dbItem
        res.minionCanDropBool = type(pob_itemsCanDropOnMinion("unique", beltName)) == "boolean"

        -- Shared items: drop appends / inserts, copy back to the build, delete.
        local ringName = it.items[ring.id].name       -- rares: "LT Ring, Gold Ring"
        local nShared = #main.sharedItemList
        local s1 = pob_itemsDropOnShared("item", ring.id, nil)
        res.shareAppends = s1.ok and s1.index == nShared + 1 and main.sharedItemList[s1.index].name == ringName
        pob_itemsDropOnShared("unique", beltName, s1.index)
        res.shareInsertAt = main.sharedItemList[s1.index].name == dbItem.name
            and main.sharedItemList[s1.index + 1].name == ringName
        local fromShared = pob_itemsDropOnList("shared", s1.index + 1, nil)
        res.sharedToList = fromShared.ok and it.items[fromShared.itemId].name == ringName
            and it.items[fromShared.itemId] ~= main.sharedItemList[s1.index + 1]
        res.sharedRows = #pob_itemsGetLists().shared == #main.sharedItemList
        pob_itemsDeleteShared(s1.index)
        res.sharedDelete = #main.sharedItemList == nShared + 1 and main.sharedItemList[s1.index].name == ringName
        res.sharedNoCtrl = not pob_itemsCtrlClick("shared", s1.index, false).ok

        -- Shared item sets: share the active set, rename, import, delete.
        local nSets = #main.sharedItemSetList
        local sh = pob_itemsShareSet(isValueInArray(it.itemSetOrderList, it.activeItemSetId), nil)
        local shared = main.sharedItemSetList[sh.index]
        res.shareSetOk = sh.ok and #main.sharedItemSetList == nSets + 1
            and shared.slots["Ring 2"] ~= nil and shared.slots["Ring 2"].name == ringName
        pob_itemsRenameSharedSet(sh.index, "LT Shared")
        res.sharedSetRename = shared.title == "LT Shared" and not pob_itemsRenameSharedSet(sh.index, " ").ok
        res.sharedSetTooltip = linesText(pob_itemsSharedSetTooltip(sh.index).lines):find("LT Ring", 1, true) ~= nil
        local nOrder = #it.itemSetOrderList
        local imp = pob_itemsImportSharedSet(sh.index, 1)
        local newSet = it.itemSets[it.itemSetOrderList[1]]
        res.importSetOk = imp.ok and #it.itemSetOrderList == nOrder + 1 and newSet.title == "LT Shared"
            and newSet["Ring 2"].selItemId ~= 0 and it.items[newSet["Ring 2"].selItemId].name == ringName
        pob_itemsDeleteSharedSet(sh.index)
        res.sharedSetDelete = #main.sharedItemSetList == nSets
    end)
    Copy = savedCopy
    pcall(function()
        wipeTable(main.sharedItemList)
        for i, v in ipairs(sharedItems) do main.sharedItemList[i] = v end
        wipeTable(main.sharedItemSetList)
        for i, v in ipairs(sharedSets) do main.sharedItemSetList[i] = v end
    end)
    pcall(dbRestore, uniq, uSnap)
    pcall(dbRestore, rare, rSnap)
    it.controls.selectDB.selIndex = selectDB
    pcall(function() it:SetDisplayItem() end)
    itRestore(bm, it, snap)
    return finish(res, ok, err)
end

-- Part 6.3: display-item editor (panel buttons, variants, sockets / links,
-- edit-text popup) and the pob_addItemFromRaw invalid-text fix.
function pob_selftestItemsEditor()
    local bm, it = ctx()
    if not it then return { ok = false, error = "no itemsTab" } end
    local snap = itSnapshot(bm, it)
    local res = { }
    local ok, err = pcall(function()
        -- Create from text with no display item: the rarity is prepended.
        it:SetDisplayItem()
        local init = pob_itemsEditTextInit()
        res.createInit = init.isEdit == false and init.saveLabel == "Create" and init.raritySel == 3 and #init.rarities == 5
        local vText = "ET Variant\nLeather Belt\nVariant: One\nVariant: Two\nSelected Variant: 1\n"
            .. "{variant:1}+10 to maximum Life\n{variant:2}+20 to maximum Life\n"
        res.checkValid = pob_itemsEditTextCheck(vText, 4).valid == true
        local bad = pob_itemsEditTextCheck("Nothing Here\nNot A Base\n", 3)
        res.checkInvalid = bad.valid == false and linesText(bad.lines):find("The item is invalid.", 1, true) ~= nil
        res.saveInvalidRefused = not pob_itemsEditTextSave("Nothing Here\nNot A Base\n", 3, false).ok and it.displayItem == nil
        pob_itemsEditTextSave(vText, 4, false)
        res.createdUnique = it.displayItem ~= nil and it.displayItem.rarity == "UNIQUE" and it.displayItem.id == nil

        -- Variants: the live dropdown's selFunc rebuilds the item + tooltip.
        local ed = pob_itemsGetLists().display
        res.variantsListed = ed.shown == true and #ed.editor.variants == 1
            and #ed.editor.variants[1].list == 2 and ed.editor.variants[1].sel == 1
        pob_itemsDisplaySetVariant(1, 2)
        res.variantSet = it.displayItem.variant == 2
            and linesText(pob_itemsGetLists().display.lines):find("+20 to maximum Life", 1, true) ~= nil
        res.badVariantRefused = not pob_itemsDisplaySetVariant(1, 9).ok
        res.noSocketsOnBelt = pob_itemsGetLists().display.editor.socketSection == false

        -- Add to build: a new item auto-equips into an empty valid slot.
        local beltWasEmpty = it.slots["Belt"].selItemId == 0
        local n = #it.itemOrderList
        pob_itemsAddDisplayItem()
        local beltId = it.itemOrderList[#it.itemOrderList]
        res.added = #it.itemOrderList == n + 1 and it.displayItem == nil and it.items[beltId].variant == 2
        res.addAutoEquips = not beltWasEmpty or it.slots["Belt"].selItemId == beltId

        -- Sockets and links (text starting "Rarity:" is used as-is).
        pob_itemsEditTextSave("Rarity: Rare\nET Chest\nPlate Vest\nSockets: R-R G\n", 1, false)
        local e = pob_itemsGetLists().display.editor
        res.socketsListed = e.socketSection == true and e.sockets[1].shown and e.sockets[3].shown
            and not e.sockets[4].shown and e.sockets[1].link == true and e.sockets[2].link == false
            and e.addSocketShown == true and e.addSocketAt == 3 and #e.socketList == 4
        pob_itemsDisplaySetSocket(3, 3)
        res.socketColour = it.displayItem.sockets[3].color == "B"
        pob_itemsDisplaySetLink(2, true)
        res.linkOn = it.displayItem.sockets[3].group == it.displayItem.sockets[2].group
            and pob_itemsGetLists().display.editor.sockets[2].link == true
        pob_itemsDisplayAddSocket()
        res.socketAdded = #it.displayItem.sockets == 4 and pob_itemsGetLists().display.editor.sockets[4].shown == true
        res.rawSockets = it.displayItem:BuildRaw():find("Sockets: R-R-B ", 1, true) ~= nil
        res.hiddenSocketRefused = not pob_itemsDisplaySetSocket(6, 1).ok
        pob_itemsAddDisplayItem()
        local chestId = it.itemOrderList[#it.itemOrderList]

        -- Edit in place: a same-id copy; Save replaces, the list keeps its size.
        pob_itemsOpenForEdit("item", chestId)
        res.saveLabel = pob_itemsGetLists().display.addLabel == "Save"
        local nItems = #it.itemOrderList
        pob_itemsDisplaySetSocket(1, 2)
        res.editIsCopy = it.items[chestId].sockets[1].color == "R"
        pob_itemsAddDisplayItem()
        res.saveReplaces = #it.itemOrderList == nItems and it.items[chestId].sockets[1].color == "G"

        -- Edit text on an existing item keeps its id; "and add" saves it.
        pob_itemsOpenForEdit("item", chestId)
        local ti = pob_itemsEditTextInit()
        res.editInit = ti.isEdit == true and ti.saveLabel == "Save" and ti.raritySel == 3
            and ti.text:find("^Rarity:") == nil and ti.text:find("ET Chest", 1, true) ~= nil
        pob_itemsEditTextSave((ti.text:gsub("ET Chest", "ET Chest Two")), 3, true)
        res.editTextKeepsId = it.items[chestId] ~= nil and it.items[chestId].title == "ET Chest Two"
            and #it.itemOrderList == nItems and it.displayItem == nil

        pob_itemsOpenForEdit("item", chestId)
        pob_itemsCloseDisplayItem()
        res.cancelOk = it.displayItem == nil

        -- pob_addItemFromRaw: text with no base used to re-add the stale
        -- display item and report success.
        pob_itemsOpenForEdit("item", chestId)
        local stale = it.displayItem
        local n2 = #it.itemOrderList
        res.rawInvalidRefused = pob_addItemFromRaw("Nothing Here\nNot A Base\n") == nil and #it.itemOrderList == n2
        local rid = pob_addItemFromRaw("Rarity: Rare\nET Raw Ring\nGold Ring\n")
        res.rawValidAdds = rid ~= nil and it.items[rid] ~= nil and it.items[rid] ~= stale and it.displayItem == stale
        pob_itemsCloseDisplayItem()
    end)
    pcall(function() it:SetDisplayItem() end)
    itRestore(bm, it, snap)
    return finish(res, ok, err)
end
