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
