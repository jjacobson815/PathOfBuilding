-- Path of Building (Qt port)
--
-- Module: pob_skills.lua  —  Skills tab bridge
-- Phase 5 (Skills Tab).
--
-- WHAT THIS IS
--   The Skills tab (src/Classes/SkillsTab.lua, SkillListControl.lua,
--   SkillSetListControl.lua, GemSelectControl.lua) re-authored in QML over the
--   LIVE legacy objects. Almost every legacy callback is still reachable as a
--   plain field on its control (`changeFunc`, `selFunc`, `gemChangeFunc`,
--   `tooltipFunc`, `onClick`), and they all act on `skillsTab.displayGroup`, so
--   the pattern here is: `showGroup(i)` (SetDisplayGroup) then call the legacy
--   closure. Code is LIFTED (with a `-- File.lua:NNN` pointer) only where the
--   legacy logic depends on the cursor (GetCursorPos is always 0,0 in the host),
--   on SimpleGraphic drawing, or lives in a popup that Qt re-authors.
--
--   Every mutation ends like legacy's OnFrame would after `buildFlag`: one
--   pob_recalculate(), then `_emit` so LuaEngine::invoke raises the signals.
--
--   Group and gem tables are REPLACED on undo/redo (RestoreUndoState), and
--   socketGroupList is rebound on a set switch, so QML addresses everything
--   by 1-based index and re-reads the state after each call.

local t_insert = table.insert
local t_remove = table.remove

local EMIT = { "build", "skills", "calcs" }
local gemTooltip = LoadModule("Classes/GemTooltip")

local function ctx()
    local bm = main and main.modes and main.modes.BUILD
    return bm, bm and bm.skillsTab
end

local function done(extra)
    pob_recalculate()
    local r = extra or { }
    if r.ok == nil then r.ok = true end
    r._emit = EMIT
    return r
end

local function fail(msg)
    return { ok = false, error = msg }
end

-- Select group `i` as the detail group (SkillListControl:OnSelect) so the
-- legacy closures below act on it. Also (re)creates gemSlots[1..#gemList+1].
local function showGroup(st, i)
    local sg = st.socketGroupList[tonumber(i) or -1]
    if not sg then return nil end
    st:SetDisplayGroup(sg)
    st.controls.groupList.selIndex = tonumber(i)
    st.controls.groupList.selValue = sg
    return sg
end

-- A real Tooltip filled by `fn`, marshalled as {size,text,center}|{sep,size}.
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

local function labelsOf(list)
    local out = { }
    for i, v in ipairs(list or { }) do out[i] = type(v) == "table" and (v.label or "") or tostring(v) end
    return out
end

local function indexWhere(list, key, value)
    for i, v in ipairs(list or { }) do
        if type(v) == "table" and v[key] == value then return i end
    end
    return 0
end

-- Gem name colour by granted effect colour (GemSelectControl.lua:462-470).
local function gemColor(ge)
    local c = ge and ge.color
    return c == 1 and colorCodes.STRENGTH or c == 2 and colorCodes.DEXTERITY
        or c == 3 and colorCodes.INTELLIGENCE or "^7"
end

---------------------------------------------------------------------------
-- Slot icons (SkillListControl.lua:9-27 slot_map + GetRowIcon 234-260).
---------------------------------------------------------------------------
local SLOT_ICON = {
    ["Weapon 1"] = "icon_weapon.png", ["Weapon 2"] = "icon_weapon_2.png",
    ["Weapon 1 Swap"] = "icon_weapon_swap.png", ["Weapon 2 Swap"] = "icon_weapon_2_swap.png",
    ["Bow"] = "icon_bow.png", ["Quiver"] = "icon_quiver.png",
    ["Shield"] = "icon_shield.png", ["Shield Swap"] = "icon_shield_swap.png",
    ["Helmet"] = "icon_helmet.png", ["Body Armour"] = "icon_body_armour.png",
    ["Gloves"] = "icon_gloves.png", ["Boots"] = "icon_boots.png", ["Amulet"] = "icon_amulet.png",
    ["Ring 1"] = "icon_ring_left.png", ["Ring 2"] = "icon_ring_right.png",
    ["Ring 3"] = "icon_ring_right.png", ["Belt"] = "icon_belt.png",
}

local function slotIcon(bm, slot)
    if not slot then return "" end
    local it = bm.itemsTab
    local function baseType(name)
        local s = it and it.activeItemSet and it.activeItemSet[name]
        local item = s and it.items[s.selItemId or 0]
        return item and item.base and item.base.type or "None"
    end
    if slot == "Weapon 1" and baseType("Weapon 1") == "Bow" then slot = "Bow" end
    if slot == "Weapon 1 Swap" and baseType("Weapon 1 Swap") == "Bow" then slot = "Bow Swap" end
    local w2 = baseType("Weapon 2")
    if slot == "Weapon 2" and (w2 == "Quiver" or w2 == "Shield") then slot = w2 end
    local w2s = baseType("Weapon 2 Swap")
    if slot == "Weapon 2 Swap" and (w2s == "Quiver" or w2s == "Shield") then slot = w2s .. " Swap" end
    local f = SLOT_ICON[slot]
    return f and (_SRC_DIR .. "/Assets/" .. f) or ""
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

-- The "Count" edit is shown only for gems that produce an active skill
-- (SkillsTab.lua:897-908).
local function countShown(gi)
    local list = gi.gemData and gi.gemData.grantedEffectList or { gi.grantedEffect }
    for idx, ge in ipairs(list) do
        if not ge.support and not ge.unsupported and (not ge.hasGlobalEffect or gi["enableGlobal" .. idx]) then
            return true
        end
    end
    return false
end

local function gemRows(st, sg)
    local rows = { }
    local sel = st.gemSlots and st.gemSlots[1] and st.gemSlots[1].nameSpec
    for i, gi in ipairs(sg.gemList) do
        local gd = gi.gemData
        local de = gi.displayEffect
        local row = {
            nameSpec = gi.nameSpec or "",
            color = gi.color or "^7",
            resolved = gd ~= nil,
            level = gi.level or 1,
            quality = gi.quality or 0,
            plusLevel = de and de.level and (de.level - (gi.level or 0)) or 0,
            plusQuality = de and de.quality and (de.quality - (gi.quality or 0)) or 0,
            enabled = gi.enabled ~= false,
            count = gi.count or 1,
            countShown = countShown(gi),
            errMsg = gi.errMsg or "",
            links = { },
        }
        -- Vaal gems: per-effect enable checkboxes (SkillsTab.lua:929-964).
        for n = 1, 2 do
            local ge = gd and gd.vaalGem and gd.grantedEffectList[n]
            row["global" .. n .. "Shown"] = (ge and not ge.support) and true or false
            row["global" .. n .. "Label"] = (ge and not ge.support) and ("Enable " .. ge.name .. ":") or ""
            row["global" .. n] = gi["enableGlobal" .. n] and true or false
        end
        rows[i] = row
    end
    -- Supporting cross-highlight (GemSelectControl.lua:516-531 + CheckSupporting).
    if sel then
        for i, a in ipairs(sg.gemList) do
            for j, b in ipairs(sg.gemList) do
                if i ~= j and a.enabled and b.enabled and a.gemData and b.gemData
                    and (sel:CheckSupporting(a, b) or sel:CheckSupporting(b, a)) then
                    t_insert(rows[i].links, j)
                end
            end
        end
    end
    return rows
end

local function groupDetail(bm, st, sg)
    local slotCtl = st.controls.groupSlot
    local d = {
        label = sg.label or "",
        slotIndex = math.max(1, indexWhere(slotCtl.list, "slotName", sg.slot)),
        hasSlot = sg.slot ~= nil,
        enabled = sg.enabled and true or false,
        -- The checkbox shows `includeInFullDPS and enabled` (SetDisplayGroup).
        includeInFullDPS = (sg.includeInFullDPS and sg.enabled) and true or false,
        source = sg.source ~= nil,
        groupCount = sg.groupCount or 1,
        sourceNote = "",
        gems = { },
    }
    if sg.source then
        local ok, text = pcall(st.controls.sourceNote.label)
        -- Legacy indents each source with "\t"; Qt text drops tabs.
        d.sourceNote = ok and (tostring(text):gsub("\t", "    ")) or ""
    else
        d.gems = gemRows(st, sg)
    end
    -- Imbued support (SkillsTab.lua:214-267; isImbuedEnabled 250-252).
    local bySlot = st.imbuedSupportBySlot or { }
    d.imbuedShown = not sg.source
    d.imbuedEnabled = (sg.slot and ((bySlot[sg.slot] and sg.imbuedSupport) or not bySlot[sg.slot])) and true or false
    d.imbuedName = sg.imbuedSupport or ""
    local igId = sg.imbuedSupport and bm.data.gemForBaseName[sg.imbuedSupport:lower() .. " support"]
    local ig = igId and bm.data.gems[igId]
    d.imbuedId = igId or ""
    d.imbuedColor = ig and gemColor(ig.grantedEffect) or "^7"
    return d
end

function pob_skillsGetState()
    local bm, st = ctx()
    if not st then return nil end
    pob_recalculate()
    local sets, activeSet = { }, 0
    for i, id in ipairs(st.skillSetOrderList) do
        local s = st.skillSets[id]
        sets[i] = s and (s.title or "Default") or "?"
        if id == st.activeSkillSetId then activeSet = i end
    end
    local groups = { }
    local listCtl = st.controls.groupList
    for i, sg in ipairs(st.socketGroupList) do
        local ok, label = pcall(listCtl.GetRowValue, listCtl, 1, i, sg)
        groups[i] = {
            label = ok and label or (sg.displayLabel or "?"),
            displayLabel = sg.displayLabel or sg.label or "",
            icon = slotIcon(bm, sg.slot),
            source = sg.source ~= nil,
            enabled = sg.enabled and true or false,
            isMain = bm.mainSocketGroup == i,
            hasGems = sg.gemList[1] ~= nil,
            hasTooltip = sg.displaySkillList ~= nil,
        }
    end
    local displayIndex = st.displayGroup and isValueInArray(st.socketGroupList, st.displayGroup) or 0
    local c = st.controls
    return {
        sets = sets,
        activeSet = activeSet,
        groups = groups,
        displayIndex = displayIndex,
        detail = displayIndex > 0 and groupDetail(bm, st, st.displayGroup) or nil,
        options = {
            sortGemsByDPS = st.sortGemsByDPS and true or false,
            sortField = math.max(1, indexWhere(c.sortGemsByDPSFieldControl.list, "type", st.sortGemsByDPSField)),
            defaultGemLevel = math.max(1, indexWhere(c.defaultLevel.list, "gemLevel", st.defaultGemLevel)),
            defaultGemQuality = tostring(st.defaultGemQuality or 0),
            showSupportGemTypes = math.max(1, indexWhere(c.showSupportGemTypes.list, "show", st.showSupportGemTypes)),
            showLegacyGems = st.showLegacyGems and true or false,
        },
        canUndo = st.undo and st.undo[2] ~= nil or false,
        canRedo = st.redo and st.redo[1] ~= nil or false,
    }
end

-- Static option lists (read from the live controls, so they stay in step).
function pob_skillsGetLists()
    local bm, st = ctx()
    if not st then return nil end
    local c = st.controls
    local levelDesc = { }
    for i, v in ipairs(c.defaultLevel.list) do levelDesc[i] = v.description or "" end
    return {
        slots = labelsOf(c.groupSlot.list),
        sortFields = labelsOf(c.sortGemsByDPSFieldControl.list),
        defaultLevels = labelsOf(c.defaultLevel.list),
        defaultLevelDescriptions = levelDesc,
        supportTypes = labelsOf(c.showSupportGemTypes.list),
    }
end

---------------------------------------------------------------------------
-- 5.1 Skill sets (SkillsTab setSelect + SkillSetListControl)
---------------------------------------------------------------------------

function pob_skillsGetSetList()
    local bm, st = ctx()
    if not st then return nil end
    local sets = { }
    for i, id in ipairs(st.skillSetOrderList) do
        local s = st.skillSets[id]
        -- SkillSetListControl.lua:81-86
        sets[i] = {
            title = s.title or "Default",
            rawTitle = s.title or "",
            listLabel = (s.title or "Default") .. (id == st.activeSkillSetId and "  ^9(Current)" or ""),
            isActive = id == st.activeSkillSetId,
        }
    end
    return { sets = sets }
end

-- SkillsTab.lua:95-98 (setSelect selFunc) / SkillSetListControl.lua:92-97.
function pob_skillsSetActiveSet(index)
    local bm, st = ctx()
    local id = st and st.skillSetOrderList[tonumber(index) or -1]
    if not id then return fail("no such set") end
    if id ~= st.activeSkillSetId then
        st:SetActiveSkillSet(id)
        st:AddUndoState()
    end
    return done()
end

local function syncLoadouts(bm)
    pcall(function() bm:SyncLoadouts() end)
end

-- SkillSetListControl.lua:48-79 (New -> RenameSet(..., true) -> Save).
function pob_skillsNewSet(title)
    local bm, st = ctx()
    if not st then return fail("no build") end
    local set = st:NewSkillSet()
    set.title = title
    st.modFlag = true
    t_insert(st.skillSetOrderList, set.id)
    st:AddUndoState()
    syncLoadouts(bm)
    return done({ index = #st.skillSetOrderList })
end

-- SkillSetListControl.lua:14-32 (Copy; lifted, there is no CopySkillSet).
function pob_skillsCopySet(index, title)
    local bm, st = ctx()
    local srcId = st and st.skillSetOrderList[tonumber(index) or -1]
    if not srcId then return fail("no such set") end
    local skillSet = st.skillSets[srcId]
    local newSkillSet = copyTable(skillSet, true)
    newSkillSet.socketGroupList = { }
    for _, socketGroup in pairs(skillSet.socketGroupList) do
        local newGroup = copyTable(socketGroup, true)
        newGroup.gemList = { }
        for gemIndex, gem in pairs(socketGroup.gemList) do
            newGroup.gemList[gemIndex] = copyTable(gem, true)
        end
        t_insert(newSkillSet.socketGroupList, newGroup)
    end
    newSkillSet.id = 1
    while st.skillSets[newSkillSet.id] do newSkillSet.id = newSkillSet.id + 1 end
    st.skillSets[newSkillSet.id] = newSkillSet
    newSkillSet.title = title
    st.modFlag = true
    t_insert(st.skillSetOrderList, newSkillSet.id)
    st:AddUndoState()
    syncLoadouts(bm)
    return done({ index = #st.skillSetOrderList })
end

-- SkillSetListControl.lua:53-79 (RenameSet Save, addOnName = false).
function pob_skillsRenameSet(index, title)
    local bm, st = ctx()
    local id = st and st.skillSetOrderList[tonumber(index) or -1]
    if not id or not tostring(title or ""):match("%S") then return fail("bad rename") end
    st.skillSets[id].title = title
    st.modFlag = true
    st:AddUndoState()
    syncLoadouts(bm)
    return done()
end

-- SkillSetListControl.lua:99-114 (OnSelDelete confirm body).
function pob_skillsDeleteSet(index)
    local bm, st = ctx()
    index = tonumber(index) or -1
    local id = st and st.skillSetOrderList[index]
    if not id or #st.skillSetOrderList <= 1 then return fail("cannot delete") end
    t_remove(st.skillSetOrderList, index)
    st.skillSets[id] = nil
    if id == st.activeSkillSetId then
        st:SetActiveSkillSet(st.skillSetOrderList[math.max(1, index - 1)])
    end
    st:AddUndoState()
    syncLoadouts(bm)
    return done()
end

-- ListControl drag reorder (ListControl.lua:423-434) + OnOrderChange (88-90):
-- modFlag only, no undo state. `to` is the row's final 1-based index.
function pob_skillsMoveSet(from, to)
    local bm, st = ctx()
    local list = st and st.skillSetOrderList
    from, to = tonumber(from) or -1, tonumber(to) or -1
    if not list or not list[from] or to < 1 or to > #list then return fail("bad move") end
    if from ~= to then
        t_insert(list, to, t_remove(list, from))
        st.modFlag = true
    end
    return done()
end

---------------------------------------------------------------------------
-- 5.1 Socket-group list (SkillListControl + SkillsTab New/Delete buttons)
---------------------------------------------------------------------------

-- ListControl select -> SkillListControl:OnSelect (144-146). UI only.
function pob_skillsSelectGroup(index)
    local bm, st = ctx()
    if not st then return fail("no build") end
    if not showGroup(st, index) then return fail("no such group") end
    return { ok = true, _emit = { "skills" } }
end

-- SkillsTab.lua:53-66 (New button).
function pob_skillsNewGroup()
    local bm, st = ctx()
    if not st then return fail("no build") end
    local newGroup = { label = "", enabled = true, gemList = { } }
    t_insert(st.socketGroupList, newGroup)
    showGroup(st, #st.socketGroupList)
    st:AddUndoState()
    bm.buildFlag = true
    return done({ index = #st.socketGroupList })
end

-- SkillListControl:OnSelDelete (154-190), index-based. QML asks the
-- confirmation question first when the group has gems.
function pob_skillsDeleteGroup(index)
    local bm, st = ctx()
    index = tonumber(index) or -1
    local sg = st and st.socketGroupList[index]
    if not sg then return fail("no such group") end
    if sg.source then
        return fail("This socket group cannot be deleted as it is created by an equipped item.")
    end
    t_remove(st.socketGroupList, index)
    st:RebuildImbuedSupportBySlot()
    if st.displayGroup == sg then
        if sg.gemList[1] then st:SetDisplayGroup() else st.displayGroup = nil end
    end
    if bm.mainSocketGroup > index then bm.mainSocketGroup = bm.mainSocketGroup - 1 end
    local ci = bm.calcsTab.input
    if (ci.skill_number or 0) > index then ci.skill_number = ci.skill_number - 1 end
    st:AddUndoState()
    bm.buildFlag = true
    st.controls.groupList.selIndex = nil
    st.controls.groupList.selValue = nil
    return done()
end

-- SkillsTab.lua:39-52 (Delete All confirm body).
function pob_skillsDeleteAllGroups()
    local bm, st = ctx()
    if not st then return fail("no build") end
    wipeTable(st.socketGroupList)
    st:RebuildImbuedSupportBySlot()
    st:SetDisplayGroup()
    st:AddUndoState()
    bm.buildFlag = true
    st.controls.groupList.selIndex = nil
    st.controls.groupList.selValue = nil
    return done()
end

-- Drag reorder: move the row, then the live OnOrderChange fixes
-- mainSocketGroup + calcsTab skill_number and adds the undo state.
function pob_skillsMoveGroup(from, to)
    local bm, st = ctx()
    local list = st and st.socketGroupList
    from, to = tonumber(from) or -1, tonumber(to) or -1
    if not list or not list[from] or to < 1 or to > #list then return fail("bad move") end
    if from == to then return { ok = true } end
    t_insert(list, to, t_remove(list, from))
    st.controls.groupList:OnOrderChange(from, to)
    st.controls.groupList.selValue = nil
    return done()
end

-- SkillListControl:OnHoverKeyUp (203-225), index-based.
function pob_skillsToggleGroupEnabled(index)
    local bm, st = ctx()
    local sg = st and st.socketGroupList[tonumber(index) or -1]
    if not sg then return fail("no such group") end
    sg.enabled = not sg.enabled
    if sg == st.displayGroup then st:SetDisplayGroup(sg) end
    st:AddUndoState()
    bm.buildFlag = true
    return done()
end

function pob_skillsToggleGroupFullDPS(index)
    local bm, st = ctx()
    local sg = st and st.socketGroupList[tonumber(index) or -1]
    if not sg then return fail("no such group") end
    sg.includeInFullDPS = not sg.includeInFullDPS
    if sg == st.displayGroup then st:SetDisplayGroup(sg) end
    st:AddUndoState()
    bm.buildFlag = true
    return done()
end

function pob_skillsSetMainGroup(index)
    local bm, st = ctx()
    index = tonumber(index) or -1
    if not (st and st.socketGroupList[index]) then return fail("no such group") end
    bm.mainSocketGroup = index
    st:AddUndoState()
    bm.buildFlag = true
    return done()
end

-- SkillListControl:OnSelCopy (148-152) -> SkillsTab:CopySocketGroup. Returns
-- the text as well as placing it on the clipboard (`noClipboard` skips that:
-- selftests must not touch the user's clipboard, and Qt's offscreen platform
-- has none).
function pob_skillsCopyGroup(index, noClipboard)
    local bm, st = ctx()
    local sg = st and st.socketGroupList[tonumber(index) or -1]
    if not sg or sg.source then return fail("cannot copy") end
    local captured
    local realCopy = Copy
    Copy = function(text) captured = text; if not noClipboard then return realCopy(text) end end
    local ok, err = pcall(st.CopySocketGroup, st, sg)
    Copy = realCopy
    if not ok then return fail(tostring(err)) end
    return { ok = true, text = captured }
end

-- SkillsTab:PasteSocketGroup (605-637). `text` (optional) replaces the
-- clipboard for this call; legacy ignores testInput whenever Paste() answers.
function pob_skillsPasteGroup(text)
    local bm, st = ctx()
    if not st then return fail("no build") end
    local before = #st.socketGroupList
    local realPaste = Paste
    if text then Paste = function() return text end end
    local ok, err = pcall(st.PasteSocketGroup, st)
    Paste = realPaste
    if not ok then return fail(tostring(err)) end
    if #st.socketGroupList == before then return { ok = false, error = "nothing to paste" } end
    return done({ index = #st.socketGroupList })
end

-- Socket-group row tooltip (SkillListControl:AddValueTooltip 113-121).
function pob_skillsGroupTooltip(index)
    local bm, st = ctx()
    local sg = st and st.socketGroupList[tonumber(index) or -1]
    if not sg or not sg.displaySkillList then return { lines = { } } end
    pob_recalculate()
    return { lines = tipLines(function(tip) st:AddSocketGroupTooltip(tip, sg) end) }
end

-- Undo / Redo (SkillsTab:Draw 544-551, which the host never runs).
function pob_skillsUndo()
    local bm, st = ctx()
    if not (st and st.undo and st.undo[2]) then return fail("nothing to undo") end
    st:Undo()
    bm.buildFlag = true
    return done()
end

function pob_skillsRedo()
    local bm, st = ctx()
    if not (st and st.redo and st.redo[1]) then return fail("nothing to redo") end
    st:Redo()
    bm.buildFlag = true
    return done()
end

---------------------------------------------------------------------------
-- 5.2 Group detail panel (SkillsTab.lua:160-315) and gem options (121-150)
---------------------------------------------------------------------------

-- Label edit: changeFunc = label + ProcessSocketGroup + undo + buildFlag.
function pob_skillsSetGroupLabel(index, text)
    local bm, st = ctx()
    if not (st and showGroup(st, index)) then return fail("no such group") end
    st.controls.groupLabel.changeFunc(tostring(text or ""))
    return done()
end

-- "Socketed in" dropdown selFunc (with the imbued-support migration).
function pob_skillsSetGroupSlot(index, slotIndex)
    local bm, st = ctx()
    local sg = st and showGroup(st, index)
    if not sg then return fail("no such group") end
    if sg.source then return fail("item-provided group") end
    local ctl = st.controls.groupSlot
    local value = ctl.list[tonumber(slotIndex) or -1]
    if not value then return fail("bad slot") end
    ctl.selFunc(slotIndex, value)
    return done()
end

-- Slot dropdown row tooltip (tooltipFunc 185-199): the equipped item.
function pob_skillsSlotTooltip(slotIndex)
    local bm, st = ctx()
    if not st then return { lines = { } } end
    local ctl = st.controls.groupSlot
    local i = tonumber(slotIndex) or -1
    local mode = i < 1 and "OUT" or "HOVER"
    return { lines = tipLines(function(tip) ctl.tooltipFunc(tip, mode, i, ctl.list[i]) end) }
end

function pob_skillsSetGroupEnabled(index, state)
    local bm, st = ctx()
    if not (st and showGroup(st, index)) then return fail("no such group") end
    st.controls.groupEnabled.changeFunc(state and true or false)
    return done()
end

function pob_skillsSetGroupFullDPS(index, state)
    local bm, st = ctx()
    if not (st and showGroup(st, index)) then return fail("no such group") end
    st.controls.includeInFullDPS.changeFunc(state and true or false)
    return done()
end

-- Count edit, shown for item/node-provided groups only.
function pob_skillsSetGroupCount(index, text)
    local bm, st = ctx()
    local sg = st and showGroup(st, index)
    if not sg then return fail("no such group") end
    if not sg.source then return fail("not an item-provided group") end
    st.controls.groupCount.changeFunc(tostring(text or ""))
    return done()
end

-- Imbued support. Mutate, rebuild the slot map, THEN push undo (legacy's
-- gemChangeFunc pushes undo before mutating, which leaves a stale top state).
-- `gemId` is a data.gems key, or nil/"" to clear.
function pob_skillsSetImbued(index, gemId)
    local bm, st = ctx()
    local sg = st and showGroup(st, index)
    if not sg then return fail("no such group") end
    if sg.source or not sg.slot then return fail("imbued support needs a socketed-in item") end
    local by = st.imbuedSupportBySlot or { }
    if by[sg.slot] and not sg.imbuedSupport then return fail("slot already has an imbued support") end
    if gemId and gemId ~= "" then
        local gem = bm.data.gems[gemId]
        if not (gem and gem.grantedEffect.support) then return fail("not a support gem") end
        sg.imbuedSupport = gem.name
    else
        if not sg.imbuedSupport then return { ok = true } end
        sg.imbuedSupport = nil
    end
    st:RebuildImbuedSupportBySlot()
    st:SetDisplayGroup(sg)
    st:AddUndoState()
    bm.buildFlag = true
    return done()
end

-- Gem options: no undo, no modFlag, no recalc (legacy). The option only
-- changes what the gem lists hold and how they sort.
function pob_skillsSetOption(key, value)
    local bm, st = ctx()
    if not st then return fail("no build") end
    local c = st.controls
    if key == "sortGemsByDPS" then
        c.sortGemsByDPS.state = value and true or false
        c.sortGemsByDPS.changeFunc(value and true or false)
    elseif key == "showLegacyGems" then
        c.showLegacyGems.state = value and true or false
        c.showLegacyGems.changeFunc(value and true or false)
    elseif key == "defaultGemQuality" then
        local text = tostring(value or ""):gsub("%D", ""):sub(1, 2)
        c.defaultQuality:SetText(text)
        c.defaultQuality.changeFunc(text)
    else
        local ctl = ({ sortField = c.sortGemsByDPSFieldControl, defaultGemLevel = c.defaultLevel,
                       showSupportGemTypes = c.showSupportGemTypes })[key]
        local i = tonumber(value) or -1
        if not ctl or not ctl.list[i] then return fail("bad option") end
        ctl.selIndex = i
        ctl.selFunc(i, ctl.list[i])
    end
    return { ok = true, _emit = { "skills" } }
end

---------------------------------------------------------------------------
-- GemSelect (GemSelectControl.lua) — shared by the imbued selector (row 0)
-- and the gem rows (row = 1..#gemList+1). The live control's own
-- UpdateSortCache / BuildList do the matching, filtering and DPS sort; only
-- the row rendering (Draw 457-486) and the hover tooltip (Draw 489-513) are
-- lifted, because they are SimpleGraphic draw code.
---------------------------------------------------------------------------

local function gemSelectCtl(st, row)
    row = tonumber(row) or -1
    if row == 0 then return st.controls.imbuedSupport end
    local slot = st.gemSlots and st.gemSlots[row]
    return slot and slot.nameSpec
end

-- The dropdown list for `buf`. `filter` is the S/A overlay button state:
-- "support" | "grants_active_skill" | nil (gem rows only).
function pob_skillsGemCandidates(index, row, buf, filter)
    local bm, st = ctx()
    if not (st and showGroup(st, index)) then return nil end
    pob_recalculate()
    local ctl = gemSelectCtl(st, row)
    if not ctl then return nil end
    if not ctl.imbuedSelect then
        ctl.sortGemsBy = (filter == "support" or filter == "grants_active_skill") and filter or nil
    end
    local t0 = os.clock()
    ctl:UpdateSortCache()
    ctl:BuildList(tostring(buf or ""))
    local sc = ctl.sortCache or { canSupport = { }, dpsColor = { } }
    local rows = { }
    for _, key in ipairs(ctl.list) do
        local gd = ctl.gems[key]
        if gd then
            local ge = gd.grantedEffect
            local marker = ""
            if ge.support and sc.canSupport[key] then
                marker = "check"
            elseif ge.hasGlobalEffect then
                marker = "plus"
            end
            rows[#rows + 1] = {
                key = key,
                id = (key:gsub("^%w+:", "")),
                name = gd.name,
                color = gemColor(ge),
                marker = marker,
                markerColor = sc.dpsColor[key] or "^7",
            }
        end
    end
    return { rows = rows, noMatches = ctl.noMatches and true or false, seconds = os.clock() - t0 }
end

-- Hover tooltip for dropdown row `key` (GemSelectControl:Draw 489-513):
-- the gem tooltip, then "Selecting this gem will give you:".
function pob_skillsGemCandidateTooltip(index, row, key)
    local bm, st = ctx()
    if not (st and showGroup(st, index)) then return { lines = { } } end
    local ctl = gemSelectCtl(st, row)
    local gemData = ctl and ctl.gems and ctl.gems[key]
    if not gemData then return { lines = { } } end
    pob_recalculate()
    return { lines = tipLines(function(tip)
        local calcFunc, calcBase = bm.calcsTab:GetMiscCalculator(bm)
        if not calcFunc then return end
        local output = ctl:CalcOutputWithThisGem(calcFunc, gemData, st.sortGemsByDPSField == "FullDPS")
        local gemInstance = {
            level = st:ProcessGemLevel(gemData, ctl.imbuedSelect),
            quality = st.defaultGemQuality or 0,
            count = 1,
            enabled = true,
            enableGlobal1 = true,
            enableGlobal2 = true,
            gemId = gemData.id,
            nameSpec = gemData.name,
            skillId = gemData.grantedEffectId,
            displayEffect = nil,
            gemData = gemData,
        }
        gemTooltip.AddGemTooltip(tip, bm, gemInstance)
        tip:AddSeparator(10)
        bm:AddStatComparesToTooltip(tip, calcBase, output, "^7Selecting this gem will give you:")
    end) }
end

local TAG_HINT = "Prefix tag searches with a colon and exclude tags with a dash. e.g. :fire:lightning:-cold:area"
local IMBUED_HINT = "\"Socketed in\" item must be set in order to add an imbued support.\nOnly one imbued support is allowed per item."

-- Collapsed (not dropped) hover tooltip (GemSelectControl:Draw 532-553):
-- the gem's own tooltip (real instance, so Level/Quality "+N"), else a hint.
function pob_skillsGemTooltip(index, row)
    local bm, st = ctx()
    local sg = st and showGroup(st, index)
    if not sg then return { lines = { } } end
    pob_recalculate()
    row = tonumber(row) or -1
    return { lines = tipLines(function(tip)
        if row == 0 then
            local id = sg.imbuedSupport and bm.data.gemForBaseName[sg.imbuedSupport:lower() .. " support"]
            local gd = id and bm.data.gems[id]
            if gd then
                gemTooltip.AddGemTooltip(tip, bm, { gemData = gd, level = 1, quality = 0 })
            else
                for line in IMBUED_HINT:gmatch("[^\n]+") do tip:AddLine(16, line) end
            end
            return
        end
        local gi = sg.gemList[row]
        if gi and gi.gemData then
            gemTooltip.AddGemTooltip(tip, bm, gi)
        else
            tip:AddLine(16, TAG_HINT)
        end
    end) }
end

---------------------------------------------------------------------------
-- Selftests
---------------------------------------------------------------------------

-- Snapshot / restore the whole tab around a selftest (CreateUndoState copies
-- every set, group and gem, plus both main-group indices).
local function stSnapshot(bm, st)
    return {
        state = st:CreateUndoState(),
        undo = copyTable(st.undo, true), redo = copyTable(st.redo, true),
        modFlag = st.modFlag,
        options = {
            sortGemsByDPS = st.sortGemsByDPS, sortGemsByDPSField = st.sortGemsByDPSField,
            defaultGemLevel = st.defaultGemLevel, defaultGemQuality = st.defaultGemQuality,
            showSupportGemTypes = st.showSupportGemTypes, showLegacyGems = st.showLegacyGems,
        },
    }
end

local function stRestore(bm, st, snap)
    st:RestoreUndoState(snap.state)
    st.undo, st.redo, st.modFlag = snap.undo, snap.redo, snap.modFlag
    for k, v in pairs(snap.options) do st[k] = v end
    bm.buildFlag = true
    pob_recalculate()
end

local function gemSig(sg)
    local parts = { sg.label or "", sg.slot or "" }
    for _, gi in ipairs(sg.gemList) do
        parts[#parts + 1] = string.format("%s|%d|%d|%s|%d", gi.nameSpec, gi.level, gi.quality,
            tostring(gi.enabled), gi.count or 1)
    end
    return table.concat(parts, ";")
end

-- Part 5.1: skill sets + socket-group list operations.
function pob_selftestSkillsList()
    local bm, st = ctx()
    if not st then return { ok = false, error = "no skillsTab" } end
    local snap = stSnapshot(bm, st)
    local res = { }
    local ok, err = pcall(function()
        -- Start from one clean set with two plain groups.
        pob_skillsDeleteAllGroups()
        res.deleteAllOk = #st.socketGroupList == 0

        -- Paste (SkillsTab:PasteSocketGroup): label, slot, enabled + disabled gem.
        local text = "Label: ST Alpha\r\nSlot: Weapon 1\r\nFireball 20/20  1\r\nSpell Echo 20/0 DISABLED 1\r\n"
        local p = pob_skillsPasteGroup(text)
        local a = st.socketGroupList[1]
        res.pasteOk = p.ok and a ~= nil and a.label == "ST Alpha" and a.slot == "Weapon 1"
            and #a.gemList == 2 and a.gemList[1].gemData ~= nil and a.gemList[2].gemData ~= nil
            and a.gemList[1].enabled == true and a.gemList[2].enabled == false
        res.pasteShowsGroup = st.displayGroup == a

        -- Copy text is the legacy format; pasting it back gives the same group.
        local c = pob_skillsCopyGroup(1, true)
        res.copyText = c.ok and c.text == "Label: ST Alpha\r\nSlot: Weapon 1\r\nFireball 20/20  1\r\nSpell Echo 20/0 DISABLED 1\r\n"
        pob_skillsPasteGroup(c.text)
        res.copyRoundTrip = #st.socketGroupList == 2 and gemSig(st.socketGroupList[2]) == gemSig(st.socketGroupList[1])

        -- Row label: link colours of ENABLED gems only (Fireball = INT = blue).
        local s = pob_skillsGetState()
        res.linkColours = s.groups[1].label:find("^7" .. colorCodes.INTELLIGENCE .. "B", 1, true) ~= nil
            and not s.groups[1].label:find("-", 1, true)
        res.iconOk = s.groups[1].icon:match("icon_weapon%.png$") ~= nil

        -- Ctrl+click / Ctrl+right-click / right-click.
        pob_skillsToggleGroupEnabled(2)
        res.disableOk = st.socketGroupList[2].enabled == false
            and pob_skillsGetState().groups[2].label:find("(Disabled)", 1, true) ~= nil
        pob_skillsToggleGroupEnabled(2)
        pob_skillsToggleGroupFullDPS(2)
        res.fullDPSOk = st.socketGroupList[2].includeInFullDPS == true
            and pob_skillsGetState().groups[2].label:find("(FullDPS)", 1, true) ~= nil
        pob_skillsSetMainGroup(2)
        res.mainOk = bm.mainSocketGroup == 2 and pob_skillsGetState().groups[2].isMain

        -- Reorder: the main group index and the Calcs skill_number follow the row.
        pob_skillsNewGroup()                              -- group 3, empty
        bm.calcsTab.input.skill_number = 2
        pob_skillsMoveGroup(2, 3)
        res.moveMainFollows = bm.mainSocketGroup == 3 and bm.calcsTab.input.skill_number == 3
        pob_skillsMoveGroup(3, 1)
        res.moveBackFollows = bm.mainSocketGroup == 1 and bm.calcsTab.input.skill_number == 1

        -- Delete a group above the main one: the main index shifts down.
        local mainSg = st.socketGroupList[bm.mainSocketGroup]
        pob_skillsMoveGroup(1, 3)                         -- main -> row 3
        local before = #st.socketGroupList
        pob_skillsDeleteGroup(1)
        res.deleteShiftsMain = #st.socketGroupList == before - 1 and bm.mainSocketGroup == 2
            and st.socketGroupList[2] == mainSg

        -- Undo restores the deleted group; redo removes it again.
        pob_skillsUndo()
        res.undoOk = #st.socketGroupList == before and bm.mainSocketGroup == 3
        pob_skillsRedo()
        res.redoOk = #st.socketGroupList == before - 1 and bm.mainSocketGroup == 2

        -- Skill sets: new / select / copy / rename / move / delete.
        local nSets = #st.skillSetOrderList
        local groupsInFirst = #st.socketGroupList
        local n = pob_skillsNewSet("ST Set")
        res.newSetOk = n.ok and #st.skillSetOrderList == nSets + 1
            and st.skillSets[st.skillSetOrderList[n.index]].title == "ST Set"
        pob_skillsSetActiveSet(n.index)
        res.selectSetOk = st.activeSkillSetId == st.skillSetOrderList[n.index] and #st.socketGroupList == 0
        local cp = pob_skillsCopySet(1, "ST Copy")
        local cpSet = st.skillSets[st.skillSetOrderList[cp.index]]
        res.copySetOk = cp.ok and #cpSet.socketGroupList == groupsInFirst
            and cpSet.socketGroupList[1] ~= st.skillSets[st.skillSetOrderList[1]].socketGroupList[1]
            and gemSig(cpSet.socketGroupList[1]) == gemSig(st.skillSets[st.skillSetOrderList[1]].socketGroupList[1])
        pob_skillsRenameSet(cp.index, "ST Renamed")
        res.renameSetOk = cpSet.title == "ST Renamed" and not pob_skillsRenameSet(cp.index, "  ").ok
        local movedId = st.skillSetOrderList[cp.index]
        pob_skillsMoveSet(cp.index, 1)
        res.moveSetOk = st.skillSetOrderList[1] == movedId
        local activeId = st.activeSkillSetId
        local activePos = isValueInArray(st.skillSetOrderList, activeId)
        pob_skillsDeleteSet(activePos)
        res.deleteActiveSetOk = st.skillSets[activeId] == nil and st.skillSets[st.activeSkillSetId] ~= nil
            and #st.skillSetOrderList == nSets + 1
        local list = pob_skillsGetSetList()
        res.setListOk = #list.sets == #st.skillSetOrderList
    end)
    stRestore(bm, st, snap)
    res.ok = ok
    if not ok then res.error = tostring(err) end
    for k, v in pairs(res) do
        if type(v) == "boolean" and not v then res.ok = false end
    end
    res.restored = true
    return res
end

-- Part 5.2: group detail panel, gem options, imbued support, GemSelect list.
function pob_selftestSkillsDetail()
    local bm, st = ctx()
    if not st then return { ok = false, error = "no skillsTab" } end
    local snap = stSnapshot(bm, st)
    local res = { }
    local ok, err = pcall(function()
        pob_skillsDeleteAllGroups()
        pob_skillsPasteGroup("Slot: Body Armour\r\nFireball 20/0  1\r\n")
        pob_skillsPasteGroup("Slot: Body Armour\r\nArc 20/0  1\r\n")
        local a, b = st.socketGroupList[1], st.socketGroupList[2]

        -- Label (changeFunc): label + displayLabel after recalc + one undo state.
        local undoBefore = #st.undo
        pob_skillsSetGroupLabel(1, "ST Label")
        res.labelOk = a.label == "ST Label" and a.displayLabel == "ST Label" and #st.undo == undoBefore + 1
        pob_skillsSetGroupLabel(1, "")
        res.labelFallbackOk = a.displayLabel == "Fireball"

        -- Socketed in (selFunc).
        pob_skillsSetGroupSlot(1, indexWhere(st.controls.groupSlot.list, "slotName", "Helmet"))
        res.slotOk = a.slot == "Helmet" and pob_skillsGetState().detail.slotIndex == 6
        local none = pob_skillsSlotTooltip(1)
        res.slotTooltipNone = #none.lines == 2 and none.lines[1].text:find("Select the item", 1, true) ~= nil
        local hl = pob_skillsSlotTooltip(indexWhere(st.controls.groupSlot.list, "slotName", "Helmet"))
        res.slotTooltipItem = #hl.lines >= 1
        pob_skillsSetGroupSlot(1, indexWhere(st.controls.groupSlot.list, "slotName", "Body Armour"))

        -- Enabled / Include in FullDPS (display rule: includeInFullDPS AND enabled).
        pob_skillsSetGroupFullDPS(1, true)
        res.fullDPSOk = a.includeInFullDPS == true and pob_skillsGetState().detail.includeInFullDPS == true
        pob_skillsSetGroupEnabled(1, false)
        local d = pob_skillsGetState().detail
        res.enabledOk = a.enabled == false and d.enabled == false and d.includeInFullDPS == false
        pob_skillsSetGroupEnabled(1, true)
        res.countRefused = not pob_skillsSetGroupCount(1, "3").ok

        -- Imbued support: one per slot; the other group in the slot is locked out.
        local cold = bm.data.gemForBaseName["added cold damage support"]
        local r = pob_skillsSetImbued(1, cold)
        res.imbuedSet = r.ok and a.imbuedSupport == "Added Cold Damage" and st.imbuedSupportBySlot["Body Armour"] ~= nil
        pob_skillsSelectGroup(2)
        res.imbuedLocked = pob_skillsGetState().detail.imbuedEnabled == false and not pob_skillsSetImbued(2, cold).ok
        pob_skillsSetImbued(1, "")
        res.imbuedCleared = a.imbuedSupport == nil and st.imbuedSupportBySlot["Body Armour"] == nil
        pob_skillsSelectGroup(2)
        res.imbuedFreed = pob_skillsGetState().detail.imbuedEnabled == true

        -- Gem options (no undo, no modFlag change expected from legacy; just fields).
        pob_skillsSetOption("sortField", 3)
        pob_skillsSetOption("defaultGemLevel", 5)
        pob_skillsSetOption("defaultGemQuality", "25")
        pob_skillsSetOption("showSupportGemTypes", 2)
        pob_skillsSetOption("showLegacyGems", true)
        pob_skillsSetOption("sortGemsByDPS", false)
        local o = pob_skillsGetState().options
        res.optionsOk = st.sortGemsByDPSField == "TotalDPS" and st.defaultGemLevel == "levelOne"
            and st.defaultGemQuality == 23 and st.showSupportGemTypes == "NORMAL"
            and st.showLegacyGems == true and st.sortGemsByDPS == false
            and o.sortField == 3 and o.defaultGemLevel == 5 and o.showSupportGemTypes == 2
        for k, v in pairs(snap.options) do st[k] = v end

        -- GemSelect list on Fireball's group (row 2 = the blank "add gem" row).
        pob_skillsSelectGroup(1)
        local c = pob_skillsGemCandidates(1, 2, "ctf", nil)
        -- Initials tier: "ctf" matches exactly the two gems named C* t* F*.
        local names = { }
        for _, row in ipairs(c.rows) do names[row.name] = true end
        res.abbrevOk = #c.rows == 2 and names["Cold to Fire"] and names["Chance to Flee"] or false
        local sup = pob_skillsGemCandidates(1, 2, "", "support")
        local allSup = #sup.rows > 0
        for _, row in ipairs(sup.rows) do
            if not bm.data.gems[row.id].grantedEffect.support then allSup = false end
        end
        res.filterSupportOk = allSup
        local act = pob_skillsGemCandidates(1, 2, ":fire:-support", nil)
        local noSup = #act.rows > 0
        for _, row in ipairs(act.rows) do
            local g = bm.data.gems[row.id]
            if g.grantedEffect.support or not g.tags.fire then noSup = false end
        end
        res.tagFilterOk = noSup
        -- DPS order: check-marked supports first, by descending DPS.
        local all = pob_skillsGemCandidates(1, 2, "", nil)
        local ctl = st.gemSlots[2].nameSpec
        local sorted, seenPlain, prev = true, false, math.huge
        for _, row in ipairs(all.rows) do
            local can = ctl.sortCache.canSupport[row.key]
            if can then
                if seenPlain then sorted = false end
                local dps = ctl.sortCache.dps[row.key]
                if dps > prev + 1e-6 then sorted = false end
                prev = dps
            else
                seenPlain = true
            end
        end
        res.dpsSortOk = sorted and all.rows[1].marker == "check"
        local tt = pob_skillsGemCandidateTooltip(1, 2, all.rows[1].key)
        local sawHeader = false
        for _, l in ipairs(tt.lines) do
            if l.text and l.text:find("Selecting this gem will give you:", 1, true) then sawHeader = true end
        end
        res.candidateTooltipOk = sawHeader
        res.gemTooltipOk = #pob_skillsGemTooltip(1, 1).lines > 3
        res.hintTooltipOk = pob_skillsGemTooltip(1, 2).lines[1].text:find(":fire:lightning", 1, true) ~= nil
        res.previewRestored = #a.gemList == 1
    end)
    stRestore(bm, st, snap)
    res.ok = ok
    if not ok then res.error = tostring(err) end
    for k, v in pairs(res) do
        if type(v) == "boolean" and not v then res.ok = false end
    end
    res.restored = true
    return res
end
