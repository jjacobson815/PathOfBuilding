-- Path of Building (Qt6/QML Port)
-- Phase 3 long-tail Step A: Build shell bridge contracts
--   1. Loadouts (pob_loadouts*)
--   2. Spectre Library (pob_spectres*)
--   3. Save-As Folder Browser (pob_saveAs*)
--   4. Headless selftests (pob_selftestLoadouts, pob_selftestSpectreLibrary, pob_selftestSaveAsFolders)

local t_insert = table.insert
local t_remove = table.remove
local s_format = string.format
local m_floor = math.floor
local m_min = math.min
local m_max = math.max

local LOADOUT_EMIT = { "build", "tree", "items", "skills", "config", "calcs" }
local SPECTRE_EMIT = { "build", "skills", "calcs" }

local SPECTRE_CATEGORIES = {
    { key = "Beast",     label = "Beast",     icon = "Assets/monstercategory/categorybeasts.png" },
    { key = "Humanoid",  label = "Humanoid",  icon = "Assets/monstercategory/categoryhumanoid.png" },
    { key = "Eldritch",  label = "Eldritch",  icon = "Assets/monstercategory/categoryeldritch.png" },
    { key = "Construct", label = "Construct", icon = "Assets/monstercategory/categoryconstruct.png" },
    { key = "Demon",     label = "Demon",     icon = "Assets/monstercategory/categorydemon.png" },
    { key = "Undead",    label = "Undead",    icon = "Assets/monstercategory/categoryundead.png" },
}

local SPECTRE_SEARCH_MODES = { "Names", "Skills", "Both" }

local SPECTRE_SORT_MODES = {
    { index = 1,  label = "Sort by Names",                field = "name",              asc = true  },
    { index = 2,  label = "Sort by Life + ES",            field = "totalHitPoints",    asc = false },
    { index = 3,  label = "Sort by Life",                 field = "life",              asc = false },
    { index = 4,  label = "Sort by Energy Shield",        field = "energyShield",      asc = false },
    { index = 5,  label = "Sort by Attack Speed",         field = "attackTime",        asc = true  },
    { index = 6,  label = "Sort by Base Damage",          field = "damage",            asc = false },
    { index = 7,  label = "Sort by Fire Resistance",      field = "fireResist",        asc = false },
    { index = 8,  label = "Sort by Cold Resistance",      field = "coldResist",        asc = false },
    { index = 9,  label = "Sort by Lightning Resistance", field = "lightningResist",   asc = false },
    { index = 10, label = "Sort by Chaos Resistance",     field = "chaosResist",       asc = false },
    { index = 11, label = "Sort by Total Resistance",     field = "totalResist",       asc = false },
    { index = 12, label = "Sort by Movement Speed",       field = "baseMovementSpeed", asc = false },
}

local function stripColorCodes(s)
    return tostring(s or ""):gsub("%^x%x%x%x%x%x%x", ""):gsub("%^%d", "")
end

local function getBuildMode()
    if not main or main.mode ~= "BUILD" then return nil end
    return main.modes and main.modes.BUILD or nil
end

-- ============================================================================
-- 1. Loadouts (pob_loadouts*)
-- ============================================================================

local function getBuildSetService(bm)
    return new("BuildSetService"):BuildSetService(bm)
end

local function safeGetLoadoutByName(bm, name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local ok, res = pcall(bm.GetLoadoutByName, bm, name)
    if not ok then
        return nil
    end
    return res
end

local function buildAvailableSetList(sets, orderList)
    local out = {
        { id = -1, label = "New", rawLabel = "^7New" },
    }
    if sets and orderList then
        for _, setId in ipairs(orderList) do
            local set = sets[setId]
            if set then
                local title = set.title or "Default"
                t_insert(out, {
                    id = setId,
                    label = stripColorCodes(title),
                    rawLabel = title,
                })
            end
        end
    end
    return out
end

local function buildLoadoutStatePayload(bm)
    local svc = getBuildSetService(bm)
    local rawList = (bm.controls and bm.controls.buildLoadouts and bm.controls.buildLoadouts.list) or {}
    local selIndex = (bm.controls and bm.controls.buildLoadouts and bm.controls.buildLoadouts.selIndex) or 1
    local activeLoadout = bm.activeLoadout or 1

    local dropdown = {}
    local activeLoadoutName = ""
    for i, entry in ipairs(rawList) do
        local kind = "loadout"
        if entry == "^7^7Loadouts:" then
            kind = "header"
        elseif entry == "^7^7-----" then
            kind = "separator"
        elseif entry == "^7^7Manage" then
            kind = "manage"
        elseif entry == "^7^7Sync" then
            kind = "sync"
        elseif entry == "^7^7Help >>" then
            kind = "help"
        end
        local isCurrent = (i == selIndex and kind == "loadout")
        if isCurrent then
            activeLoadoutName = entry
        end
        t_insert(dropdown, {
            index = i,
            index0 = i - 1,
            value = entry,
            label = stripColorCodes(entry),
            kind = kind,
            isCurrent = isCurrent,
        })
    end

    -- Port BuildSetListControl:GetRowValue (BuildSetListControl.lua:172-183)
    local rows = {}
    local loadoutsList = bm.loadoutsList or {}
    for index, spec in ipairs(loadoutsList) do
        local used = spec:CountAllocNodes()
        local title = spec.title or "Default"
        local versionPrefix = (spec.treeVersion ~= latestTreeVersion and treeVersions[spec.treeVersion])
            and ("[" .. treeVersions[spec.treeVersion].display .. "] ") or ""
        local className = (spec.curAscendClassName and spec.curAscendClassName ~= "None")
            and spec.curAscendClassName or (spec.curClassName or "")
        local isCurrent = (index == activeLoadout)
        local display = versionPrefix .. title .. " (" .. className .. ", " .. used .. " points)"
            .. (isCurrent and "  ^9(Current)" or "")
        local loadoutIds = safeGetLoadoutByName(bm, versionPrefix .. title) or safeGetLoadoutByName(bm, title) or {}
        t_insert(rows, {
            index = index,
            index0 = index - 1,
            title = title,
            fullName = versionPrefix .. title,
            display = display,
            displayPlain = stripColorCodes(display),
            className = className,
            pointsUsed = used,
            treeVersion = spec.treeVersion,
            isCurrent = isCurrent,
            specId = loadoutIds.specId,
            itemSetId = loadoutIds.itemSetId,
            skillSetId = loadoutIds.skillSetId,
            configSetId = loadoutIds.configSetId,
        })
    end

    -- Port BuildSetListControl:CustomLoadout available lists (BuildSetListControl.lua:80-159)
    local treeList = {
        { id = -1, label = "New", rawLabel = "^7New" },
    }
    if bm.treeTab then
        for idx, specTitle in ipairs(bm.treeTab:GetSpecList()) do
            t_insert(treeList, {
                id = idx,
                label = stripColorCodes(specTitle),
                rawLabel = specTitle,
            })
        end
    end

    local availableSets = {
        trees = treeList,
        skills = bm.skillsTab and buildAvailableSetList(bm.skillsTab.skillSets, bm.skillsTab.skillSetOrderList) or {},
        items = bm.itemsTab and buildAvailableSetList(bm.itemsTab.itemSets, bm.itemsTab.itemSetOrderList) or {},
        configs = bm.configTab and buildAvailableSetList(bm.configTab.configSets, bm.configTab.configSetOrderList) or {},
    }

    local activeSets = {
        specId = bm.treeTab and bm.treeTab.activeSpec or nil,
        itemSetId = bm.itemsTab and bm.itemsTab.activeItemSetId or nil,
        skillSetId = bm.skillsTab and bm.skillsTab.activeSkillSetId or nil,
        configSetId = bm.configTab and bm.configTab.activeConfigSetId or nil,
    }

    return {
        ok = true,
        dropdown = dropdown,
        activeDropdownIndex = selIndex,
        activeDropdownIndex0 = selIndex - 1,
        activeLoadoutIndex = activeLoadout,
        activeLoadoutIndex0 = activeLoadout - 1,
        activeLoadoutName = activeLoadoutName,
        rows = rows,
        canDelete = #loadoutsList > 1,
        availableSets = availableSets,
        activeSets = activeSets,
        specNameLookup = svc:SpecNameLookup(),
    }
end

function pob_loadoutsGetState()
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end
    bm:SyncLoadouts()
    return buildLoadoutStatePayload(bm)
end

function pob_loadoutsSync()
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end
    bm:SyncLoadouts()
    pob_recalculate()
    local state = buildLoadoutStatePayload(bm)
    state._emit = LOADOUT_EMIT
    return state
end

function pob_loadoutsSelect(nameOrIndex)
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end
    bm:SyncLoadouts()

    local value = nameOrIndex
    if type(nameOrIndex) == "number" then
        local list = bm.controls and bm.controls.buildLoadouts and bm.controls.buildLoadouts.list or {}
        value = list[nameOrIndex]
    end
    if type(value) ~= "string" or value == "" then
        return { ok = false, error = "invalid loadout selection" }
    end

    if value == "^7^7Loadouts:" or value == "^7^7-----" then
        bm.controls.buildLoadouts:SetSel(1)
        return { ok = false, error = "not a selectable loadout" }
    end
    if value == "^7^7Sync" then
        bm:SyncLoadouts()
        bm.controls.buildLoadouts:SetSel(1)
        pob_recalculate()
        return { ok = true, action = "sync", _emit = LOADOUT_EMIT }
    end
    if value == "^7^7Help >>" then
        bm.controls.buildLoadouts:SetSel(1)
        return { ok = true, action = "help" }
    end
    if value == "^7^7Manage" then
        return { ok = true, action = "manage" }
    end

    local loadout = safeGetLoadoutByName(bm, value)
    if not loadout or not loadout.specId then
        return { ok = false, error = "loadout not found: " .. tostring(value) }
    end

    bm:SetActiveLoadout(loadout)
    bm.controls.buildLoadouts:SelByValue(value)
    pob_recalculate()

    return {
        ok = true,
        name = value,
        specId = bm.treeTab.activeSpec,
        itemSetId = bm.itemsTab.activeItemSetId,
        skillSetId = bm.skillsTab.activeSkillSetId,
        configSetId = bm.configTab.activeConfigSetId,
        _emit = LOADOUT_EMIT,
    }
end

function pob_loadoutsNew(name)
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end
    if type(name) ~= "string" or not name:match("%S") then
        return { ok = false, error = "loadout name cannot be empty" }
    end
    local svc = getBuildSetService(bm)
    local lookup = svc:SpecNameLookup()
    if lookup[name] then
        return { ok = false, error = "loadout name already exists: " .. name }
    end

    svc:NewLoadout(name)
    pob_recalculate()
    return {
        ok = true,
        name = name,
        _emit = LOADOUT_EMIT,
    }
end

function pob_loadoutsCopy(sourceName, newName)
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end
    if type(sourceName) ~= "string" or sourceName == "" then
        return { ok = false, error = "source loadout name required" }
    end
    if type(newName) ~= "string" or not newName:match("%S") then
        return { ok = false, error = "new loadout name cannot be empty" }
    end
    bm:SyncLoadouts()
    local svc = getBuildSetService(bm)
    local lookup = svc:SpecNameLookup()
    if lookup[newName] then
        return { ok = false, error = "loadout name already exists: " .. newName }
    end
    if not safeGetLoadoutByName(bm, sourceName) then
        return { ok = false, error = "source loadout not found: " .. sourceName }
    end

    svc:CopyLoadout(sourceName, newName)
    pob_recalculate()
    return {
        ok = true,
        sourceName = sourceName,
        name = newName,
        _emit = LOADOUT_EMIT,
    }
end

function pob_loadoutsCustom(specId, itemSetId, skillSetId, configSetId, name)
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end
    if type(name) ~= "string" or not name:match("%S") then
        return { ok = false, error = "loadout name cannot be empty" }
    end
    bm:SyncLoadouts()
    local svc = getBuildSetService(bm)
    local lookup = svc:SpecNameLookup()
    if lookup[name] then
        return { ok = false, error = "loadout name already exists: " .. name }
    end

    local sId = tonumber(specId) or -1
    local iId = tonumber(itemSetId) or -1
    local skId = tonumber(skillSetId) or -1
    local cId = tonumber(configSetId) or -1

    svc:CustomLoadout(sId, iId, skId, cId, name)
    pob_recalculate()
    return {
        ok = true,
        name = name,
        _emit = LOADOUT_EMIT,
    }
end

function pob_loadoutsRename(oldName, newName)
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end
    if type(oldName) ~= "string" or oldName == "" then
        return { ok = false, error = "old loadout name required" }
    end
    if type(newName) ~= "string" or not newName:match("%S") then
        return { ok = false, error = "new loadout name cannot be empty" }
    end
    bm:SyncLoadouts()
    local svc = getBuildSetService(bm)
    local lookup = svc:SpecNameLookup()
    if lookup[newName] then
        return { ok = false, error = "loadout name already exists: " .. newName }
    end
    if not safeGetLoadoutByName(bm, oldName) then
        return { ok = false, error = "loadout not found: " .. oldName }
    end

    svc:RenameLoadout(oldName, newName)
    pob_recalculate()
    return {
        ok = true,
        oldName = oldName,
        name = newName,
        _emit = LOADOUT_EMIT,
    }
end

function pob_loadoutsDelete(indexOrName)
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end
    bm:SyncLoadouts()

    local list = bm.loadoutsList or {}
    if #list <= 1 then
        return { ok = false, error = "cannot delete the only loadout" }
    end

    local index = nil
    if type(indexOrName) == "number" then
        index = indexOrName
    elseif type(indexOrName) == "string" then
        for i, spec in ipairs(list) do
            if (spec.title or "Default") == indexOrName then
                index = i
                break
            end
        end
    end

    if not index or not list[index] then
        return { ok = false, error = "loadout not found: " .. tostring(indexOrName) }
    end

    local spec = list[index]
    local deletedTitle = spec.title or "Default"
    local svc = getBuildSetService(bm)

    -- Guard activeLoadout range so BuildSetService:DeleteLoadout always resolves a valid nextLoadout
    if not bm.activeLoadout or bm.activeLoadout < 1 or bm.activeLoadout > #list then
        bm.activeLoadout = index
    end
    svc:DeleteLoadout(index, list, spec)
    pob_recalculate()
    return {
        ok = true,
        deleted = deletedTitle,
        _emit = LOADOUT_EMIT,
    }
end

function pob_loadoutsReorder(oldIndex, newIndex)
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end
    bm:SyncLoadouts()

    local list = bm.loadoutsList or {}
    oldIndex = tonumber(oldIndex)
    newIndex = tonumber(newIndex)
    if not oldIndex or not newIndex or oldIndex < 1 or newIndex < 1 or oldIndex > #list or newIndex > #list then
        return { ok = false, error = "invalid reorder indices" }
    end
    if oldIndex == newIndex then
        return { ok = true, moved = false, oldIndex = oldIndex, newIndex = newIndex }
    end

    -- Legacy ListControl mutates buildMode.loadoutsList before OnOrderChange;
    -- Build.lua:1059-1075 relies on loadoutsList already reflecting the new order
    -- when #specList ~= #loadoutsList.
    if #bm.treeTab.specList ~= #list then
        local moved = t_remove(list, oldIndex)
        t_insert(list, newIndex, moved)
    end

    local svc = getBuildSetService(bm)
    svc:ReorderLoadout(oldIndex, newIndex)
    pob_recalculate()
    return {
        ok = true,
        moved = true,
        oldIndex = oldIndex,
        newIndex = newIndex,
        _emit = LOADOUT_EMIT,
    }
end

-- ============================================================================
-- 2. Spectre Library (pob_spectres*)
-- ============================================================================

local function spectreMatchesSearch(bm, searchStr, minionId, searchMode)
    local minion = bm.data.minions[minionId]
    if not minion then return false end
    if searchMode == 1 or searchMode == 3 then
        local err, match = PCall(string.matchOrPattern, (minion.name or ""):lower(), searchStr)
        if not err and match then
            return true
        end
    end
    if searchMode == 2 or searchMode == 3 then
        for _, skillId in ipairs(minion.skillList or {}) do
            local skill = bm.data.skills[skillId]
            if skill and skill.name then
                local err, match = PCall(string.matchOrPattern, skill.name:lower(), searchStr)
                if not err and match then
                    return true
                end
            end
        end
    end
    return false
end

local function computeSpectreSortValue(bm, minion, field)
    local esRatio = (bm.data.gameConstants and bm.data.gameConstants["EnergyShieldRatioOfLife"]) or 100
    if field == "name" then
        return minion.name or ""
    elseif field == "life" then
        return minion.life or 0
    elseif field == "totalHitPoints" then
        local life = minion.life or 0
        return life + (((minion.energyShield or 0) * esRatio / 100) * life)
    elseif field == "energyShield" then
        local life = minion.life or 0
        return ((minion.energyShield or 0) * esRatio / 100) * life
    elseif field == "totalResist" then
        return (minion.fireResist or 0) + (minion.coldResist or 0)
            + (minion.lightningResist or 0) + (minion.chaosResist or 0)
    else
        return minion[field] or 0
    end
end

local function makeSpectreEntry(bm, id)
    local minion = bm.data.minions[id]
    if not minion then return nil end
    return {
        id = id,
        name = minion.name or id,
        category = minion.monsterCategory or "",
        itemisedCorpse = not not minion.itemisedCorpse,
        recommended = not not (minion.extraFlags and minion.extraFlags.recommendedSpectre),
    }
end

function pob_spectresQuery(opts)
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end
    opts = type(opts) == "table" and opts or {}

    local showAll = not not opts.showAll
    local corpseOnly = not not opts.corpseOnly
    local searchRaw = tostring(opts.search or "")
    local searchMode = tonumber(opts.searchMode) or 1
    if searchMode < 1 or searchMode > 3 then searchMode = 1 end
    local sortMode = tonumber(opts.sortMode) or 1
    if sortMode < 1 or sortMode > #SPECTRE_SORT_MODES then sortMode = 1 end

    local enabledCats = {}
    if type(opts.categories) == "table" then
        for _, cat in ipairs(SPECTRE_CATEGORIES) do
            enabledCats[cat.key] = (opts.categories[cat.key] == true)
        end
    else
        for _, cat in ipairs(SPECTRE_CATEGORIES) do
            enabledCats[cat.key] = true
        end
    end

    local filteredIds = {}
    local totalSpectres = 0
    for id in pairs(bm.data.spectres or {}) do
        totalSpectres = totalSpectres + 1
        local minion = bm.data.minions[id]
        if minion then
            local catOk = enabledCats[minion.monsterCategory] == true
            local recOk = showAll or (minion.extraFlags and minion.extraFlags.recommendedSpectre)
            local corpseOk = (not corpseOnly) or minion.itemisedCorpse
            if catOk and recOk and corpseOk then
                t_insert(filteredIds, id)
            end
        end
    end

    local searchStr = searchRaw:lower():gsub("[%-%.%+%[%]%$%^%%%?%*]", "%%%0")
    if searchStr:match("%S") then
        local matched = {}
        for _, id in ipairs(filteredIds) do
            if spectreMatchesSearch(bm, searchStr, id, searchMode) then
                t_insert(matched, id)
            end
        end
        filteredIds = matched
    end

    local sortOption = SPECTRE_SORT_MODES[sortMode]
    table.sort(filteredIds, function(a, b)
        local minionA = bm.data.minions[a]
        local minionB = bm.data.minions[b]
        local valueA = computeSpectreSortValue(bm, minionA, sortOption.field)
        local valueB = computeSpectreSortValue(bm, minionB, sortOption.field)
        if valueA == valueB then
            local nameA = minionA.name or ""
            local nameB = minionB.name or ""
            if nameA == nameB then
                return a < b
            end
            return nameA < nameB
        end
        if sortOption.asc then
            return valueA < valueB
        else
            return valueA > valueB
        end
    end)

    local available = {}
    for _, id in ipairs(filteredIds) do
        local entry = makeSpectreEntry(bm, id)
        if entry then
            t_insert(available, entry)
        end
    end

    local spectreList = {}
    for _, id in ipairs(bm.spectreList or {}) do
        local entry = makeSpectreEntry(bm, id)
        if entry then
            t_insert(spectreList, entry)
        else
            t_insert(spectreList, { id = id, name = id, category = "", itemisedCorpse = false, recommended = false })
        end
    end

    local sortLabels = {}
    for _, s in ipairs(SPECTRE_SORT_MODES) do
        t_insert(sortLabels, s.label)
    end

    return {
        ok = true,
        spectreList = spectreList,
        available = available,
        categories = SPECTRE_CATEGORIES,
        searchModes = SPECTRE_SEARCH_MODES,
        sortModes = sortLabels,
        totalSpectres = totalSpectres,
        filteredCount = #available,
        defaultGemLevel = 20,
    }
end

function pob_spectresGetState(opts)
    return pob_spectresQuery(opts)
end

-- Port of UpdateMinionDisplay (Build.lua:1788-1841)
function pob_spectresGetMinionStats(minionId, gemLevel)
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end
    local minion = bm.data.minions and bm.data.minions[minionId]
    if not minion then
        return { ok = false, error = "unknown minion: " .. tostring(minionId) }
    end

    local clampedGemLevel = m_min(m_max(m_floor(tonumber(gemLevel) or 20), 1), 40)
    local raiseSpectre = bm.data.skills and bm.data.skills["RaiseSpectre"]
    local minionLevel = (raiseSpectre and raiseSpectre.levels and raiseSpectre.levels[clampedGemLevel]
        and raiseSpectre.levels[clampedGemLevel][2]) or 70
    local levelIdx = m_min(minionLevel, 100)

    local baseLife = bm.data.monsterLifeTable[levelIdx]
    local totalLife = baseLife * minion.life
    local totalES = 0
    if minion.energyShield then
        totalES = totalLife * (minion.energyShield * (bm.data.gameConstants["EnergyShieldRatioOfLife"] / 100))
    end

    local totalArmour = bm.data.monsterArmourTable[levelIdx]
    local totalEvasion = bm.data.monsterEvasionTable[levelIdx]
    if minion.armour then
        totalArmour = minion.armour * totalArmour
    end
    if minion.evasion then
        totalEvasion = minion.evasion * totalEvasion
    end

    local blockChance = 0
    local spellBlockChance = 0
    if minion.modList then
        for _, mod in ipairs(minion.modList) do
            if mod.name == "BlockChance" then
                blockChance = mod.value
            elseif mod.name == "SpellBlockChance" then
                spellBlockChance = mod.value
            end
        end
    end

    local spawnLocations = {}
    if minion.spawnLocation then
        for _, spawn in ipairs(minion.spawnLocation) do
            t_insert(spawnLocations, spawn)
        end
    end

    local moveSpeed = (minion.baseMovementSpeed or 0) / 10
    local resistsText = colorCodes.FIRE .. minion.fireResist .. "^7 / "
        .. colorCodes.COLD .. minion.coldResist .. "^7 / "
        .. colorCodes.LIGHTNING .. minion.lightningResist .. "^7 / "
        .. colorCodes.CHAOS .. minion.chaosResist

    return {
        ok = true,
        id = minionId,
        name = minion.name,
        gemLevel = clampedGemLevel,
        minionLevel = minionLevel,
        life = m_floor(totalLife),
        energyShield = m_floor(totalES),
        armour = round(totalArmour),
        evasion = round(totalEvasion),
        blockChance = blockChance,
        spellBlockChance = spellBlockChance,
        blockText = blockChance .. "% / " .. spellBlockChance .. "%",
        fireResist = minion.fireResist,
        coldResist = minion.coldResist,
        lightningResist = minion.lightningResist,
        chaosResist = minion.chaosResist,
        resistsText = resistsText,
        movementSpeed = moveSpeed,
        movementSpeedText = moveSpeed .. " m/s",
        spawnLocations = spawnLocations,
    }
end

-- Port of MinionListControl:AddValueTooltip (MinionListControl.lua:52-103)
function pob_spectresGetMinionTooltip(minionId)
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end
    local minion = bm.data.minions and bm.data.minions[minionId]
    if not minion then
        return { ok = false, error = "unknown minion: " .. tostring(minionId) }
    end

    local lines = {}
    t_insert(lines, { size = 20, text = "^7" .. minion.name, font = "FONTIN SC", center = true })
    t_insert(lines, { separator = true, size = 2 })
    t_insert(lines, { size = 14, text = s_format("^7Life Multiplier: x%.2f", minion.life) })
    if minion.energyShield then
        t_insert(lines, { size = 14, text = s_format("^7Energy Shield: %d%% of base Life", minion.energyShield * 100) })
    end
    if minion.armour then
        t_insert(lines, { size = 14, text = s_format("^7Armour Multiplier: x%.2f", 1 + minion.armour) })
    end
    if minion.evasion then
        t_insert(lines, { size = 14, text = s_format("^7Evasion Multiplier: x%.2f", 1 + minion.evasion) })
    end
    t_insert(lines, {
        size = 14,
        text = s_format("^7Resistances: %s%d ^7/ %s%d ^7/ %s%d ^7/ %s%d",
            colorCodes.FIRE, minion.fireResist,
            colorCodes.COLD, minion.coldResist,
            colorCodes.LIGHTNING, minion.lightningResist,
            colorCodes.CHAOS, minion.chaosResist
        ),
    })
    t_insert(lines, { size = 14, text = s_format("^7Base Damage: x%.2f", minion.damage) })
    t_insert(lines, { size = 14, text = s_format("^7Base Attack Speed: %.2f", 1 / minion.attackTime) })
    t_insert(lines, { size = 14, text = s_format("^7Base Movement Speed: %.2f", minion.baseMovementSpeed / 10) })

    if minion.skillList and #minion.skillList > 0 then
        t_insert(lines, { separator = true, size = 10 })
        for _, skillId in ipairs(minion.skillList) do
            local skill = bm.data.skills[skillId]
            if skill then
                local color = (data.skillColorMap and data.skillColorMap[skill.color]) or colorCodes.NORMAL
                t_insert(lines, { size = 14, text = "^7Skill: " .. color .. skill.name })
            end
        end
    end

    t_insert(lines, { separator = true, size = 10 })
    if minion.spawnLocation and #minion.spawnLocation > 0 then
        local coloredLocations = {}
        for _, location in ipairs(minion.spawnLocation) do
            local mainText, bracket = location:match("^(.-)%s*(%b())%s*$")
            t_insert(coloredLocations, bracket and (colorCodes.RELIC .. mainText .. " " .. "^7" .. bracket) or (colorCodes.RELIC .. location))
        end
        for i, spawn in ipairs(coloredLocations) do
            if i == 1 then
                t_insert(lines, { size = 14, text = s_format("^7Spawn: %s", spawn) })
            else
                t_insert(lines, { size = 14, text = s_format("^7%s%s", "            ", spawn) })
            end
        end
    end

    return {
        ok = true,
        id = minionId,
        lines = lines,
    }
end

-- Port of SpawnListControl:AddValueTooltip (MinionListControl.lua:145-175), without ConPrintf("YES")
function pob_spectresGetSpawnTooltip(areaName)
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end
    local worldAreas = (bm.data and bm.data.worldAreas) or (data and data.worldAreas) or {}

    local foundArea = nil
    for _, area in pairs(worldAreas) do
        if area.name == areaName then
            foundArea = area
            break
        end
    end

    local lines = {}
    if foundArea then
        t_insert(lines, { size = 18, text = foundArea.name })
        if foundArea.description then
            for _, line in ipairs(foundArea.description) do
                t_insert(lines, { size = 14, text = colorCodes.CURRENCY .. '"' .. line .. '"' })
            end
        end
        if foundArea.bossVarieties and #foundArea.bossVarieties > 0 then
            t_insert(lines, { size = 14, text = colorCodes.UNIQUE .. "Bosses: ^7" .. table.concat(foundArea.bossVarieties, ", ") })
        end
        t_insert(lines, { size = 14, text = "^7Area Level: " .. tostring(foundArea.level) })
        t_insert(lines, { separator = true, size = 10 })
        t_insert(lines, { size = 14, text = "^7Spectres:" })
        for _, monsterName in ipairs(foundArea.monsterVarieties or {}) do
            t_insert(lines, { size = 14, text = " - " .. monsterName })
        end
    else
        t_insert(lines, { size = 14, text = "^7World area not found: " .. tostring(areaName) })
    end

    return {
        ok = true,
        found = foundArea ~= nil,
        areaName = tostring(areaName or ""),
        lines = lines,
    }
end

function pob_spectresSave(minionIds)
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end
    if type(minionIds) ~= "table" then
        return { ok = false, error = "minionIds must be a list" }
    end

    local seen = {}
    local cleanList = {}
    for _, id in ipairs(minionIds) do
        if type(id) == "string" and not seen[id] and bm.data.spectres[id] and bm.data.minions[id] then
            seen[id] = true
            t_insert(cleanList, id)
        end
    end

    bm.spectreList = cleanList
    bm.modFlag = true
    bm.buildFlag = true
    pob_recalculate()

    return {
        ok = true,
        count = #cleanList,
        spectreList = cleanList,
        _emit = SPECTRE_EMIT,
    }
end

-- ============================================================================
-- 3. Save-As Folder Browser (pob_saveAs*)
-- ============================================================================

local function normalizeBasePath()
    local base = (main and main.buildPath or ""):gsub("\\", "/")
    if #base > 0 and base:sub(-1) ~= "/" then
        base = base .. "/"
    end
    return base
end

local function normalizeSubPath(subPath)
    if type(subPath) ~= "string" or subPath == "" then
        return ""
    end
    local norm = subPath:gsub("\\", "/"):gsub("/+", "/"):gsub("^/", "")
    local parts = {}
    for seg in norm:gmatch("[^/]+") do
        if seg ~= "." and seg ~= ".." then
            t_insert(parts, seg)
        end
    end
    if #parts == 0 then
        return ""
    end
    return table.concat(parts, "/") .. "/"
end

local function isValidFolderName(folderName)
    if type(folderName) ~= "string" or not folderName:match("%S") then
        return false
    end
    if folderName == "." or folderName == ".." then
        return false
    end
    if folderName:find('[\\/:%*%?"<>|%c]') then
        return false
    end
    return true
end

function pob_saveAsGetState(subPath, sortMode)
    if not main then return { ok = false, error = "no main" } end
    local bm = getBuildMode()

    local basePath = normalizeBasePath()
    local sub = normalizeSubPath(subPath ~= nil and subPath or (bm and bm.dbFileSubPath or ""))

    local mode
    if sortMode == "NAME" or sortMode == "EDITED" then
        mode = sortMode
        if bm then bm.saveAsSortMode = mode end
    else
        mode = (bm and (bm.saveAsSortMode == "EDITED" and "EDITED" or "NAME")) or "NAME"
    end

    local folders = {}
    local handle = NewFileSearch(basePath .. sub .. "*", true)
    while handle do
        local fileName = handle:GetFileName()
        t_insert(folders, {
            name = fileName,
            fullFileName = basePath .. sub .. fileName,
            subPath = sub .. fileName .. "/",
            modified = handle:GetFileModifiedTime() or 0,
        })
        if not handle:NextFile() then
            break
        end
    end
    if handle and handle.Close then handle:Close() end

    table.sort(folders, function(a, b)
        if mode == "EDITED" then
            local modA = a.modified or 0
            local modB = b.modified or 0
            if modA ~= modB then
                return modA > modB
            end
            return naturalSortCompare(a.name, b.name)
        else
            return naturalSortCompare(a.name, b.name)
        end
    end)

    local defaultBuildName = ""
    if bm then
        defaultBuildName = not bm.dbFileName and (main.predefinedBuildName or "")
            or ((bm.buildName or bm.dbFileName or ""):gsub('[\\/:%*%?"<>|%c]', "-"))
    end

    return {
        ok = true,
        basePath = basePath,
        subPath = sub,
        sortMode = mode,
        folders = folders,
        defaultBuildName = defaultBuildName,
    }
end

function pob_saveAsCreateFolder(subPath, folderName)
    if not main then return { ok = false, error = "no main" } end
    if not isValidFolderName(folderName) then
        return { ok = false, error = "Invalid folder name." }
    end

    local basePath = normalizeBasePath()
    local sub = normalizeSubPath(subPath)
    local fullPath = basePath .. sub .. folderName

    local res, msg = MakeDir(fullPath)
    if not res then
        return { ok = false, error = tostring(msg or "Couldn't create folder.") }
    end
    if main.modes and main.modes.LIST then
        main.modes.LIST:BuildList()
    end

    return {
        ok = true,
        folderName = folderName,
        subPath = sub .. folderName .. "/",
        fullPath = fullPath,
    }
end

function pob_saveAsDeleteFolder(subPath, folderName)
    if not main then return { ok = false, error = "no main" } end
    if not isValidFolderName(folderName) then
        return { ok = false, error = "Invalid folder name." }
    end

    local basePath = normalizeBasePath()
    local sub = normalizeSubPath(subPath)
    local fullPath = basePath .. sub .. folderName

    local fHandle = NewFileSearch(fullPath .. "/*")
    local dHandle = NewFileSearch(fullPath .. "/*", true)
    local hasFiles = fHandle ~= nil
    local hasDirs = dHandle ~= nil
    if fHandle and fHandle.Close then fHandle:Close() end
    if dHandle and dHandle.Close then dHandle:Close() end

    if hasFiles or hasDirs then
        return { ok = false, error = "The folder is not empty." }
    end

    local res, msg = RemoveDir(fullPath)
    if not res then
        return { ok = false, error = "Couldn't delete '" .. fullPath .. "': " .. tostring(msg) }
    end
    if main.modes and main.modes.LIST then
        main.modes.LIST:BuildList()
    end

    return {
        ok = true,
        folderName = folderName,
        fullPath = fullPath,
    }
end

-- ============================================================================
-- 4. Headless Selftests
-- ============================================================================

function pob_selftestLoadouts()
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end

    local origXml = bm:SaveDB("selftest-loadouts-orig")
    local origName = bm.buildName or "Default"

    local function restore()
        pob_loadBuildXML(origXml, origName)
        pob_recalculate()
    end

    local function fail(msg)
        restore()
        return { ok = false, error = msg }
    end

    local st0 = pob_loadoutsGetState()
    if not st0.ok or type(st0.dropdown) ~= "table" or type(st0.rows) ~= "table" or type(st0.availableSets) ~= "table" then
        return fail("initial pob_loadoutsGetState invalid")
    end

    -- Exact-title NewLoadout
    local rNew = pob_loadoutsNew("ST_Exact")
    if not rNew.ok then return fail("NewLoadout failed: " .. tostring(rNew.error)) end
    local st1 = pob_loadoutsGetState()
    if not st1.specNameLookup["ST_Exact"] then return fail("ST_Exact missing from specNameLookup") end
    if st1.activeLoadoutName ~= "ST_Exact" then return fail("ST_Exact not active after New: " .. tostring(st1.activeLoadoutName)) end

    -- CopyLoadout
    local rCopy = pob_loadoutsCopy("ST_Exact", "ST_Copy")
    if not rCopy.ok then return fail("CopyLoadout failed: " .. tostring(rCopy.error)) end
    local st2 = pob_loadoutsGetState()
    if st2.activeLoadoutName ~= "ST_Copy" then return fail("ST_Copy not active after Copy") end

    -- CustomLoadout
    local rCustom = pob_loadoutsCustom(-1, -1, -1, -1, "ST_Custom")
    if not rCustom.ok then return fail("CustomLoadout failed: " .. tostring(rCustom.error)) end
    local st3 = pob_loadoutsGetState()
    if st3.activeLoadoutName ~= "ST_Custom" then return fail("ST_Custom not active after Custom") end

    -- RenameLoadout
    local rRename = pob_loadoutsRename("ST_Copy", "ST_Renamed")
    if not rRename.ok then return fail("RenameLoadout failed: " .. tostring(rRename.error)) end
    local st4 = pob_loadoutsGetState()
    if st4.specNameLookup["ST_Copy"] or not st4.specNameLookup["ST_Renamed"] then
        return fail("RenameLoadout did not update specNameLookup")
    end

    -- 4-tab active set switching
    local rSelA = pob_loadoutsSelect("ST_Exact")
    if not rSelA.ok then return fail("Select ST_Exact failed: " .. tostring(rSelA.error)) end
    local rSelB = pob_loadoutsSelect("ST_Renamed")
    if not rSelB.ok then return fail("Select ST_Renamed failed: " .. tostring(rSelB.error)) end
    if rSelA.specId == rSelB.specId
        or rSelA.itemSetId == rSelB.itemSetId
        or rSelA.skillSetId == rSelB.skillSetId
        or rSelA.configSetId == rSelB.configSetId then
        return fail("Select did not switch all 4 active sets")
    end

    -- ReorderLoadout
    local idxExact, idxRenamed
    for _, row in ipairs(st4.rows) do
        if row.title == "ST_Exact" then idxExact = row.index end
        if row.title == "ST_Renamed" then idxRenamed = row.index end
    end
    if not idxExact or not idxRenamed then return fail("could not find rows for reorder") end
    local rReorder = pob_loadoutsReorder(idxRenamed, idxExact)
    if not rReorder.ok or not rReorder.moved then return fail("ReorderLoadout failed") end
    local st5 = pob_loadoutsGetState()
    if st5.rows[idxExact].title ~= "ST_Renamed" then
        return fail("ReorderLoadout did not move ST_Renamed to target index")
    end

    -- {linkId} brace-tag match across 4 distinct titles
    local customIds = safeGetLoadoutByName(bm, "ST_Custom")
    if not customIds or not customIds.specId then return fail("ST_Custom ids missing") end
    bm.treeTab.specList[customIds.specId].title = "ST_TagTree {st1}"
    bm.itemsTab.itemSets[customIds.itemSetId].title = "ST_TagItems {st1}"
    bm.skillsTab.skillSets[customIds.skillSetId].title = "ST_TagSkills {st1}"
    bm.configTab.configSets[customIds.configSetId].title = "ST_TagConfig {st1}"

    local stTag = pob_loadoutsSync()
    local foundTagDropdown = false
    for _, item in ipairs(stTag.dropdown) do
        if item.value == "ST_TagTree {st1}" then
            foundTagDropdown = true
            break
        end
    end
    if not foundTagDropdown then return fail("brace-tag loadout missing from dropdown") end

    local rSelTag = pob_loadoutsSelect("ST_TagTree {st1}")
    if not rSelTag.ok then return fail("Select brace-tag loadout failed: " .. tostring(rSelTag.error)) end
    if bm.treeTab.activeSpec ~= customIds.specId
        or bm.itemsTab.activeItemSetId ~= customIds.itemSetId
        or bm.skillsTab.activeSkillSetId ~= customIds.skillSetId
        or bm.configTab.activeConfigSetId ~= customIds.configSetId then
        return fail("brace-tag loadout did not activate all 4 tagged sets")
    end

    -- DeleteLoadout
    local beforeCount = #pob_loadoutsGetState().rows
    local rDel = pob_loadoutsDelete("ST_Renamed")
    if not rDel.ok then return fail("DeleteLoadout failed: " .. tostring(rDel.error)) end
    local afterCount = #pob_loadoutsGetState().rows
    if afterCount ~= beforeCount - 1 then
        return fail("DeleteLoadout did not reduce row count")
    end

    restore()
    return {
        ok = true,
        exactMatch = true,
        braceTagMatch = true,
        rowCountBeforeDelete = beforeCount,
        rowCountAfterDelete = afterCount,
    }
end

function pob_selftestSpectreLibrary()
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end

    local origXml = bm:SaveDB("selftest-spectres-orig")
    local origName = bm.buildName or "Default"

    local function restore()
        pob_loadBuildXML(origXml, origName)
        pob_recalculate()
    end

    local function fail(msg)
        restore()
        return { ok = false, error = msg }
    end

    -- Default recommended vs showAll
    local defQ = pob_spectresQuery({})
    local allQ = pob_spectresQuery({ showAll = true })
    if not defQ.ok or not allQ.ok then return fail("spectresQuery failed") end
    if #defQ.available == 0 or #allQ.available <= #defQ.available then
        return fail("expected showAll > recommended > 0")
    end

    -- corpseOnly filter
    local corpseQ = pob_spectresQuery({ showAll = true, corpseOnly = true })
    if #corpseQ.available == 0 then return fail("corpseOnly returned 0 results") end
    for _, entry in ipairs(corpseQ.available) do
        if not entry.itemisedCorpse then return fail("corpseOnly returned non-corpse spectre") end
    end

    -- Category filter
    local undeadQ = pob_spectresQuery({
        showAll = true,
        categories = { Beast = false, Humanoid = false, Eldritch = false, Construct = false, Demon = false, Undead = true },
    })
    if #undeadQ.available == 0 then return fail("Undead category filter returned 0 results") end
    for _, entry in ipairs(undeadQ.available) do
        if entry.category ~= "Undead" then return fail("Undead category filter leaked: " .. tostring(entry.category)) end
    end

    -- Search + sort modes
    local first = defQ.available[1]
    local searchQ = pob_spectresQuery({ search = first.name, searchMode = 1 })
    local foundFirst = false
    for _, entry in ipairs(searchQ.available) do
        if entry.id == first.id then foundFirst = true break end
    end
    if not foundFirst then return fail("name search did not match first recommended spectre") end

    local lifeSortQ = pob_spectresQuery({ showAll = true, sortMode = 3 })
    if #lifeSortQ.available < 2 then return fail("life sort returned < 2 entries") end
    local lifeFirst = bm.data.minions[lifeSortQ.available[1].id].life or 0
    local lifeLast = bm.data.minions[lifeSortQ.available[#lifeSortQ.available].id].life or 0
    if lifeFirst < lifeLast then return fail("life sort order invalid") end

    -- Minion stats + clamping + tooltips
    local stats20 = pob_spectresGetMinionStats(first.id, 20)
    if not stats20.ok or stats20.gemLevel ~= 20 or stats20.life <= 0 then
        return fail("pob_spectresGetMinionStats(20) invalid")
    end
    local stats99 = pob_spectresGetMinionStats(first.id, 99)
    if not stats99.ok or stats99.gemLevel ~= 40 then
        return fail("gemLevel clamping failed")
    end
    local mTip = pob_spectresGetMinionTooltip(first.id)
    if not mTip.ok or #mTip.lines < 5 then
        return fail("pob_spectresGetMinionTooltip invalid")
    end
    if stats20.spawnLocations and #stats20.spawnLocations > 0 then
        local sTip = pob_spectresGetSpawnTooltip(stats20.spawnLocations[1])
        if not sTip.ok or #sTip.lines < 1 then
            return fail("pob_spectresGetSpawnTooltip invalid")
        end
    end

    -- Save spectres (with duplicate to verify dedupe) + Raise Spectre XML round-trip
    local saveRes = pob_spectresSave({ first.id, first.id })
    if not saveRes.ok or saveRes.count ~= 1 or bm.spectreList[1] ~= first.id then
        return fail("pob_spectresSave failed or did not deduplicate")
    end

    -- Add an active Raise Spectre socket group so calcsTab.mainEnv.minion is populated
    local rsGemData = bm.data.gems["Metadata/Items/Gems/SkillGemRaiseSpectre"]
    if not rsGemData then
        for _, g in pairs(bm.data.gems) do
            if g.name == "Raise Spectre" then rsGemData = g break end
        end
    end
    if not rsGemData then return fail("Raise Spectre gem data not found") end

    local sg = {
        label = "Selftest Spectre",
        enabled = true,
        includeInFullDPS = false,
        gemList = {
            {
                nameSpec = rsGemData.name,
                gemId = rsGemData.id,
                variantId = rsGemData.variantId,
                skillId = rsGemData.grantedEffectId,
                gemData = rsGemData,
                level = 20,
                quality = 0,
                qualityId = "Default",
                enabled = true,
                enableGlobal1 = true,
                enableGlobal2 = true,
                count = 1,
            },
        },
        mainActiveSkill = 1,
        mainActiveSkillCalcs = 1,
    }
    t_insert(bm.skillsTab.socketGroupList, sg)
    bm.skillsTab:ProcessSocketGroup(sg)
    bm.mainSocketGroup = #bm.skillsTab.socketGroupList
    bm.modFlag = true
    bm.buildFlag = true
    pob_recalculate()

    local savedXml = bm:SaveDB("selftest-spectre-rt")
    if not savedXml then return fail("SaveDB returned nil") end
    local hasSpectre = savedXml:find("<Spectre ", 1, true) ~= nil
    local hasMinionStat = savedXml:find("<MinionStat ", 1, true) ~= nil
    if not hasSpectre or not hasMinionStat then
        return fail("saved XML missing <Spectre or <MinionStat (hasSpectre="
            .. tostring(hasSpectre) .. ", hasMinionStat=" .. tostring(hasMinionStat) .. ")")
    end

    pob_loadBuildXML(savedXml, "selftest-spectre-rt")
    local bmAfter = getBuildMode()
    if not bmAfter or not bmAfter.spectreList or bmAfter.spectreList[1] ~= first.id then
        return fail("spectreList did not survive XML round-trip")
    end

    restore()
    return {
        ok = true,
        recommendedCount = #defQ.available,
        allCount = #allQ.available,
        corpseCount = #corpseQ.available,
        hasSpectre = hasSpectre,
        hasMinionStat = hasMinionStat,
    }
end

function pob_selftestSaveAsFolders()
    local bm = getBuildMode()
    if not bm then return { ok = false, error = "no build" } end

    local origDbFileName = bm.dbFileName
    local origBuildName = bm.buildName
    local origSubPath = bm.dbFileSubPath
    local origSortMode = bm.saveAsSortMode

    local rootFolder = "__pob_selftest_saveas__"
    local rootSub = rootFolder .. "/"
    local savedFilePath = nil

    local function cleanup()
        if savedFilePath then
            os.remove(savedFilePath)
        end
        pob_saveAsDeleteFolder(rootSub, "a_folder")
        pob_saveAsDeleteFolder(rootSub, "b_folder")
        pob_saveAsDeleteFolder("", rootFolder)
        bm.dbFileName = origDbFileName
        bm.buildName = origBuildName
        bm.dbFileSubPath = origSubPath
        bm.saveAsSortMode = origSortMode
        bm:ResetModFlags()
    end

    local function fail(msg)
        cleanup()
        return { ok = false, error = msg }
    end

    -- Ensure clean slate
    pob_saveAsDeleteFolder(rootSub, "a_folder")
    pob_saveAsDeleteFolder(rootSub, "b_folder")
    pob_saveAsDeleteFolder("", rootFolder)

    -- Invalid folder name rejected
    local rBad = pob_saveAsCreateFolder("", "bad/folder")
    if rBad.ok then return fail("invalid folder name was accepted") end

    -- Create root + two subfolders
    local rRoot = pob_saveAsCreateFolder("", rootFolder)
    if not rRoot.ok then return fail("create root folder failed: " .. tostring(rRoot.error)) end
    local rB = pob_saveAsCreateFolder(rootSub, "b_folder")
    if not rB.ok then return fail("create b_folder failed: " .. tostring(rB.error)) end
    local rA = pob_saveAsCreateFolder(rootSub, "a_folder")
    if not rA.ok then return fail("create a_folder failed: " .. tostring(rA.error)) end

    -- Sort by NAME
    local stName = pob_saveAsGetState(rootSub, "NAME")
    if not stName.ok or stName.sortMode ~= "NAME" or #stName.folders ~= 2 then
        return fail("saveAsGetState NAME failed")
    end
    if stName.folders[1].name ~= "a_folder" or stName.folders[2].name ~= "b_folder" then
        return fail("NAME sort order mismatch: " .. tostring(stName.folders[1].name) .. ", " .. tostring(stName.folders[2].name))
    end

    -- Sort by EDITED
    local stEdited = pob_saveAsGetState(rootSub, "EDITED")
    if not stEdited.ok or stEdited.sortMode ~= "EDITED" or bm.saveAsSortMode ~= "EDITED" or #stEdited.folders ~= 2 then
        return fail("saveAsGetState EDITED failed")
    end

    -- Save build file into a_folder via pob_saveDBFile
    savedFilePath = stName.basePath .. rootSub .. "a_folder/selftest_save.xml"
    local rSave = pob_saveDBFile(savedFilePath)
    if not rSave or not rSave.ok then
        return fail("pob_saveDBFile into temp subfolder failed: " .. tostring(rSave and rSave.error))
    end

    -- Non-empty delete refusal
    local rDelNonEmpty = pob_saveAsDeleteFolder(rootSub, "a_folder")
    if rDelNonEmpty.ok or rDelNonEmpty.error ~= "The folder is not empty." then
        return fail("non-empty delete was not refused with expected message: " .. tostring(rDelNonEmpty.error))
    end

    -- Remove temp file + delete empty folders
    os.remove(savedFilePath)
    savedFilePath = nil

    local rDelA = pob_saveAsDeleteFolder(rootSub, "a_folder")
    if not rDelA.ok then return fail("delete empty a_folder failed: " .. tostring(rDelA.error)) end
    local rDelB = pob_saveAsDeleteFolder(rootSub, "b_folder")
    if not rDelB.ok then return fail("delete empty b_folder failed: " .. tostring(rDelB.error)) end
    local rDelRoot = pob_saveAsDeleteFolder("", rootFolder)
    if not rDelRoot.ok then return fail("delete empty root folder failed: " .. tostring(rDelRoot.error)) end

    bm.dbFileName = origDbFileName
    bm.buildName = origBuildName
    bm.dbFileSubPath = origSubPath
    bm.saveAsSortMode = origSortMode
    bm:ResetModFlags()

    return {
        ok = true,
        nameSortOk = true,
        editedSortOk = true,
        nonEmptyRefused = true,
        cleanupOk = true,
    }
end
