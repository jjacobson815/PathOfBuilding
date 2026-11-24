-- Path of Building (Qt port)
--
-- Module: pob_config.lua  —  Config tab bridge
-- Phase 7 (Config Tab).
--
-- Ports src/Classes/ConfigTab.lua + ConfigOptions.lua + ConfigVisibility.lua
-- + ConfigSetListControl.lua over the live build.configTab object.
--
-- Invariants:
--   - Never marshal ConfigTab controls, ModList, or Tooltip objects raw.
--   - Always return plain tables of primitives with `_emit` signals.
--   - Maintain the `varControls` host shim so ConfigOptions apply() closures
--     (enemyIsBoss, enemyRadius, presetBossSkills, multiplierMapModTier, ...)
--     can read `.selIndex`/`.list`/`.placeholder` and call `:SetPlaceholder()`.
--   - Construct engine objects strictly as `new("X"):X(args)` (bcbca9b60).
--   - Respect PR #9647 set split: NewConfigSet vs CreateConfigSet.

local t_insert = table.insert
local t_remove = table.remove
local m_max = math.max

local EMIT_CONFIG = { "build", "config", "calcs" }
local EMIT_CONFIG_TREE = { "build", "config", "calcs", "tree" }
local EMIT_UI_ONLY = { "config" }

local _varListCache = nil
local _varMapCache = nil
local _configVisCache = nil

local function getVarList()
    if _varListCache then return _varListCache end
    local ok, vl = pcall(require, "Modules.ConfigOptions")
    if ok and vl then
        _varListCache = vl
        return vl
    end
    local ok2, vl2 = pcall(LoadModule, "Modules/ConfigOptions")
    if ok2 and vl2 then
        _varListCache = vl2
        return vl2
    end
    return nil
end

local function getVarMap()
    if _varMapCache then return _varMapCache end
    local vl = getVarList()
    if not vl then return nil end
    local map = { }
    for _, vd in ipairs(vl) do
        if vd.var then
            map[vd.var] = vd
        end
    end
    _varMapCache = map
    return map
end

local function getConfigVisibility()
    if _configVisCache then return _configVisCache end
    local ok, cv = pcall(require, "Modules.ConfigVisibility")
    if ok and cv then
        _configVisCache = cv
        return cv
    end
    return nil
end

local function ctx()
    local bm = main and main.modes and main.modes.BUILD
    local ct = bm and bm.configTab
    if not ct then return bm, nil, nil end
    local setId = ct.activeConfigSetId or 1
    local activeSet = ct.configSets and ct.configSets[setId]
    return bm, ct, activeSet
end

local function done(extra, emit)
    pob_recalculate()
    local r = extra or { }
    if r.ok == nil then r.ok = true end
    r._emit = emit or EMIT_CONFIG
    return r
end

local function fail(msg)
    return { ok = false, error = msg }
end

local function syncLoadouts(bm)
    if bm and bm.SyncLoadouts then
        pcall(function() bm:SyncLoadouts() end)
    end
end

-- ============================================================================
-- Part 7.1: varControls host shim
-- ============================================================================
-- ConfigOptions.lua apply() closures reach into `build.configTab.varControls[k]`:
--   - `:SetPlaceholder(val, notify)` (enemyIsBoss, enemyRadius, presetBossSkills)
--   - `.selIndex` and `.list[selIndex].val` (multiplierMapModTier, enemyIsBoss)
--   - `.placeholder` (enemyDamageRollRange)
-- Legacy ConfigTab creates real EditControl/CheckBoxControl/DropDownControl
-- instances in `ct.varControls`, but they are never drawn in Qt so we must:
--   1. Guarantee every var in ConfigOptions has a compatible entry (creating a
--      lightweight shim if missing, e.g. in stripped/test environments).
--   2. Keep `.selIndex`, `.state`, `.buf`, and `.placeholder` synchronized with
--      `activeSet.input` / `activeSet.placeholder` before `BuildModList()`.
local function makeVarControlShim(ct, vd)
    local t = vd.type
    if t == "check" then
        return {
            _className = "CheckBoxControl",
            state = vd.defaultState or false,
        }
    elseif t == "list" then
        local shim = {
            _className = "DropDownControl",
            list = vd.list or { },
            selIndex = vd.defaultIndex or 1,
        }
        function shim:SelByValue(val, key)
            key = key or "val"
            for i, entry in ipairs(self.list) do
                if type(entry) == "table" and entry[key] == val then
                    self.selIndex = i
                    return
                elseif entry == val then
                    self.selIndex = i
                    return
                end
            end
        end
        return shim
    else
        local isNum = (t == "count" or t == "integer" or t == "countAllowZero" or t == "float")
        local shim = {
            _className = "EditControl",
            buf = "",
            placeholder = vd.defaultPlaceholderState ~= nil and tostring(vd.defaultPlaceholderState) or "",
        }
        function shim:SetText(txt)
            self.buf = tostring(txt or "")
        end
        function shim:SetPlaceholder(txt, notify)
            self.placeholder = tostring(txt or "")
            if notify then
                local activeSet = ct.configSets and ct.configSets[ct.activeConfigSetId]
                if activeSet and activeSet.placeholder then
                    if isNum then
                        activeSet.placeholder[vd.var] = tonumber(self.placeholder)
                    else
                        activeSet.placeholder[vd.var] = self.placeholder
                    end
                end
                if ct.build then ct.build.buildFlag = true end
            end
        end
        return shim
    end
end

function pob_ensureConfigVarControls(ct)
    if not ct then return end
    if not ct.varControls then ct.varControls = { } end
    local vl = getVarList()
    if not vl then return end
    for _, vd in ipairs(vl) do
        if vd.var and not ct.varControls[vd.var] then
            ct.varControls[vd.var] = makeVarControlShim(ct, vd)
        end
    end
end

-- Sync a single varControl (or all) from activeSet.input so apply() sees live values.
local function syncSingleVarControl(ct, activeSet, vd)
    if not ct or not activeSet or not vd or not vd.var then return end
    pob_ensureConfigVarControls(ct)
    local ctrl = ct.varControls[vd.var]
    if not ctrl then return end
    local val = activeSet.input[vd.var]
    if ctrl._className == "CheckBoxControl" then
        ctrl.state = val
    elseif ctrl._className == "DropDownControl" and ctrl.SelByValue then
        local target = val
        if target == nil then
            target = ct:GetDefaultState(vd.var)
        end
        ctrl:SelByValue(target, "val")
    elseif (ctrl._className == "EditControl" or ctrl._className == "ResizableEditControl") then
        if ctrl.SetText then
            ctrl:SetText(val ~= nil and tostring(val) or "")
        end
        if activeSet.placeholder and activeSet.placeholder[vd.var] ~= nil and ctrl.SetPlaceholder then
            ctrl:SetPlaceholder(tostring(activeSet.placeholder[vd.var]), false)
        end
    end
end

-- ============================================================================
-- Part 7.2: Conditional visibility engine (against Phase 2 pob_getConfigUsageSets)
-- ============================================================================
local function anyIfValue(ifOption, predicate)
    if type(ifOption) == "table" then
        for _, opt in ipairs(ifOption) do
            if predicate(opt) then return true end
        end
        return false
    end
    return predicate(ifOption) and true or false
end

local function implyCondActive(vd, activeInput, usage)
    if not activeInput or not activeInput[vd.var] or not usage then return false end
    if vd.implyCondList then
        for _, c in ipairs(vd.implyCondList) do
            if c and usage.conditionsUsed[c] then return true end
        end
    end
    return (vd.implyCond and usage.conditionsUsed[vd.implyCond])
        or (vd.implyMinionCond and usage.minionConditionsUsed[vd.implyMinionCond])
        or (vd.implyEnemyCond and usage.enemyConditionsUsed[vd.implyEnemyCond])
        or false
end

local SIMPLE_PREDICATES = {
    { key = "ifCond",       env = "conditionsUsed",       canImply = true },
    { key = "ifMinionCond", env = "minionConditionsUsed", canImply = true },
    { key = "ifEnemyCond",  env = "enemyConditionsUsed",  canImply = true },
    { key = "ifMult",       env = "multipliersUsed",      canImply = true },
    { key = "ifEnemyMult",  env = "enemyMultipliersUsed", canImply = true },
    { key = "ifEnemyStat",  env = "enemyPerStatsUsed",    canImply = true },
    { key = "ifTagType",    env = "tagTypesUsed",         canImply = true },
    { key = "ifMod",        env = "modsUsed",             canImply = true },
}

-- Evaluate all visibility predicates for `vd` using Phase 2 usage sets + live build.
local function isRelevantForBuild(vd, bm, usage, activeInput)
    if not bm or not usage then return false end
    local mainEnv = bm.calcsTab and bm.calcsTab.mainEnv
    local player = mainEnv and mainEnv.player
    local mainSkill = player and player.mainSkill
    local spec = bm.spec

    local impliedCache
    local function implied()
        if impliedCache == nil then
            impliedCache = implyCondActive(vd, activeInput, usage) and true or false
        end
        return impliedCache
    end

    for _, p in ipairs(SIMPLE_PREDICATES) do
        local ifVal = vd[p.key]
        if ifVal then
            local setTbl = usage[p.env] or { }
            if not anyIfValue(ifVal, function(opt)
                return setTbl[opt] or (p.canImply and implied())
            end) then
                return false
            end
        end
    end

    if vd.ifNode and spec then
        if not anyIfValue(vd.ifNode, function(opt)
            if spec.allocNodes and spec.allocNodes[opt] then return true end
            local node = spec.nodes and spec.nodes[opt]
            if node and node.type == "Keystone" then
                return usage.keystonesAdded and usage.keystonesAdded[node.dn]
            end
            return false
        end) then
            return false
        end
    end

    if vd.ifOption then
        if not anyIfValue(vd.ifOption, function(opt) return activeInput and activeInput[opt] end) then
            return false
        end
    end

    if vd.ifCondTrue then
        if not anyIfValue(vd.ifCondTrue, function(opt)
            return player and player.modDB and player.modDB.conditions and player.modDB.conditions[opt]
        end) then
            return false
        end
    end

    if vd.ifStat then
        if not anyIfValue(vd.ifStat, function(opt)
            return (usage.perStatsUsed and usage.perStatsUsed[opt])
                or (usage.enemyMultipliersUsed and usage.enemyMultipliersUsed[opt])
                or implied()
        end) then
            return false
        end
    end

    if vd.ifFlag then
        if not mainSkill then return false end
        local skillFlags = mainSkill.skillFlags or { }
        local skillModList = mainSkill.skillModList
        if not anyIfValue(vd.ifFlag, function(opt)
            return skillFlags[opt] or (skillModList and skillModList:Flag(nil, opt))
        end) then
            return false
        end
    end

    if vd.ifSkill then
        local skillsUsed = usage.skillsUsed or { }
        if vd.includeTransfigured and calcLib then
            if not anyIfValue(vd.ifSkill, function(opt)
                if not calcLib.getGameIdFromGemName(opt, true) then return false end
                for skill, _ in pairs(skillsUsed) do
                    if calcLib.isGemIdSame(skill, opt, true) then return true end
                end
                return false
            end) then
                return false
            end
        else
            if not anyIfValue(vd.ifSkill, function(opt) return skillsUsed[opt] end) then
                return false
            end
        end
    end

    if vd.ifSkillFlag or vd.ifSkillData then
        local skillList = (player and player.activeSkillList) or { }
        local function anySkillHas(field, opt)
            for _, s in ipairs(skillList) do
                if s[field] and s[field][opt] then return true end
            end
            return false
        end
        if vd.ifSkillFlag and not anyIfValue(vd.ifSkillFlag, function(opt) return anySkillHas("skillFlags", opt) end) then
            return false
        end
        if vd.ifSkillData and not anyIfValue(vd.ifSkillData, function(opt) return anySkillHas("skillData", opt) end) then
            return false
        end
    end

    return true
end

-- Lua-pattern-tolerant search matching (ConfigTab.lua:195-206).
local function searchMatch(vd, searchText)
    if not searchText or not searchText:match("%S") then
        return true
    end
    local label = StripEscapes(vd.label or ""):lower()
    local lowerSearch = searchText:lower()
    local escaped = lowerSearch:gsub("[%-%.%+%[%]%$%^%%%?%*%(%)]", "%%%0")
    if string.matchOrPattern then
        local err, m = PCall(string.matchOrPattern, label, escaped)
        if not err and m then return true end
    end
    -- Also try user's raw Lua pattern safely via pcall (if valid pattern).
    local okPat, patMatch = pcall(string.match, label, lowerSearch)
    if okPat and patMatch then return true end
    -- Plain substring fallback so unclosed parens / brackets never error.
    return label:find(lowerSearch, 1, true) ~= nil
end

local function isShowAllConfig(ct, vd)
    if not ct or not ct.toggleConfigs then return false end
    local cv = getConfigVisibility()
    if cv and cv.isShowAllExcluded then
        return not cv.isShowAllExcluded(vd)
    end
    return true
end

local function evalOptionState(bm, ct, activeSet, usage, vd, searchText)
    local cur = activeSet.input[vd.var]
    local def = ct:GetDefaultState(vd.var, type(cur))
    local isNonDefault = (cur ~= nil and cur ~= def)

    local relevant = isRelevantForBuild(vd, bm, usage, activeSet.input)
    local innerShown = relevant or isShowAllConfig(ct, vd)
    local isInvalid = (not innerShown) and isNonDefault and (not vd.hideIfInvalid)

    local visible = false
    if searchMatch(vd, searchText) then
        if vd.hideIfInvalid then
            visible = innerShown
        else
            visible = innerShown or isInvalid
        end
    end

    local borderState = "normal"
    if not vd.doNotHighlight and isNonDefault then
        borderState = (not innerShown) and "invalid" or "modified"
    end

    return visible, isInvalid, isNonDefault, borderState, cur, def
end

-- ============================================================================
-- Tooltip marshalling (plain tables only)
-- ============================================================================
local function marshalTooltip(tip)
    local lines = { }
    for _, l in ipairs(tip.lines or { }) do
        if l.text == nil then
            lines[#lines + 1] = { sep = true, size = l.size or 10 }
        else
            local centered
            if l.center ~= nil then
                centered = l.center and true or false
            else
                centered = tip.center and true or false
            end
            lines[#lines + 1] = { size = l.size or 14, text = tostring(l.text), center = centered }
        end
    end
    return { lines = lines }
end

-- ============================================================================
-- Config Set Management (SetManagePopup.qml contract + PR #9647 set split)
-- ============================================================================
local function buildSetsList(ct)
    local sets = { }
    local activeIdx = 1
    for i, setId in ipairs(ct.configSetOrderList or { }) do
        local s = ct.configSets and ct.configSets[setId]
        if s then
            local raw = s.title or ""
            local title = (raw ~= "") and raw or "Default"
            local isActive = (setId == ct.activeConfigSetId)
            if isActive then activeIdx = i end
            sets[#sets + 1] = {
                id = setId,
                title = title,
                rawTitle = raw,
                listLabel = title .. (isActive and "  ^9(Current)" or ""),
                isActive = isActive,
            }
        end
    end
    return sets, activeIdx
end

function pob_configListSets()
    local _, ct = ctx()
    if not ct then return { sets = { }, activeIndex = 1 } end
    local sets, activeIdx = buildSetsList(ct)
    return { sets = sets, activeIndex = activeIdx }
end

function pob_configSetActiveSet(orderIndex)
    local bm, ct = ctx()
    if not ct then return fail("no configTab") end
    local idx = tonumber(orderIndex)
    local setId = idx and ct.configSetOrderList and ct.configSetOrderList[idx]
    if not setId or not ct.configSets[setId] then
        return fail("invalid config set index")
    end
    pob_ensureConfigVarControls(ct)
    ct:SetActiveConfigSet(setId)
    -- Mirror bandit/pantheon to build object
    local activeSet = ct.configSets[ct.activeConfigSetId]
    if activeSet and activeSet.input then
        if activeSet.input.bandit then bm.bandit = activeSet.input.bandit end
        if activeSet.input.pantheonMajorGod then bm.pantheonMajorGod = activeSet.input.pantheonMajorGod end
        if activeSet.input.pantheonMinorGod then bm.pantheonMinorGod = activeSet.input.pantheonMinorGod end
    end
    ct:AddUndoState()
    return done({ activeSetId = setId }, EMIT_CONFIG_TREE)
end

function pob_configCreateSet(title)
    local bm, ct = ctx()
    if not ct then return fail("no configTab") end
    local name = (type(title) == "string" and title:match("%S")) and title or "New Config Set"
    -- Find first unused id so deleted holes never collide
    local nextId = 1
    while ct.configSets[nextId] do
        nextId = nextId + 1
    end
    -- Respect PR #9647: NewConfigSet creates + appends to configSetOrderList + sets modFlag
    local newSet = ct:NewConfigSet(nextId, name)
    pob_ensureConfigVarControls(ct)
    ct:SetActiveConfigSet(newSet.id, false, true)
    ct:AddUndoState()
    syncLoadouts(bm)
    return done({ index = #ct.configSetOrderList, id = newSet.id }, EMIT_CONFIG_TREE)
end

function pob_configCopySet(orderIndex, title)
    local bm, ct = ctx()
    if not ct then return fail("no configTab") end
    local idx = tonumber(orderIndex)
    local srcId = idx and ct.configSetOrderList and ct.configSetOrderList[idx]
    if not srcId or not ct.configSets[srcId] then
        return fail("invalid config set index")
    end
    local srcTitle = ct.configSets[srcId].title or "Default"
    local name = (type(title) == "string" and title:match("%S")) and title or (srcTitle .. " (Copy)")
    local newSet = ct:CopyConfigSet(srcId, name)
    pob_ensureConfigVarControls(ct)
    ct:SetActiveConfigSet(newSet.id, false, true)
    ct:AddUndoState()
    syncLoadouts(bm)
    return done({ index = #ct.configSetOrderList, id = newSet.id }, EMIT_CONFIG_TREE)
end

function pob_configRenameSet(orderIndex, title)
    local bm, ct = ctx()
    if not ct then return fail("no configTab") end
    local idx = tonumber(orderIndex)
    local setId = idx and ct.configSetOrderList and ct.configSetOrderList[idx]
    if not setId or not ct.configSets[setId] then
        return fail("invalid config set index")
    end
    if type(title) ~= "string" or not title:match("%S") then
        return fail("empty title")
    end
    ct:RenameConfigSet(setId, title)
    ct:AddUndoState()
    syncLoadouts(bm)
    return { ok = true, _emit = { "build", "config" } }
end

function pob_configDeleteSet(orderIndex)
    local bm, ct = ctx()
    if not ct then return fail("no configTab") end
    if #ct.configSetOrderList <= 1 then
        return fail("cannot delete last config set")
    end
    local idx = tonumber(orderIndex)
    local setId = idx and ct.configSetOrderList[idx]
    if not setId or not ct.configSets[setId] then
        return fail("invalid config set index")
    end
    ct:DeleteConfigSet(setId, idx)
    if setId == ct.activeConfigSetId then
        local fallbackId = ct.configSetOrderList[m_max(1, idx - 1)]
        pob_ensureConfigVarControls(ct)
        ct:SetActiveConfigSet(fallbackId, false, true)
    end
    ct:AddUndoState()
    syncLoadouts(bm)
    return done(nil, EMIT_CONFIG_TREE)
end

function pob_configMoveSet(fromIndex, toIndex)
    local bm, ct = ctx()
    if not ct then return fail("no configTab") end
    local from = tonumber(fromIndex)
    local to = tonumber(toIndex)
    local n = #ct.configSetOrderList
    if not from or not to or from < 1 or from > n or to < 1 or to > n then
        return fail("invalid move indices")
    end
    if from ~= to then
        local id = t_remove(ct.configSetOrderList, from)
        t_insert(ct.configSetOrderList, to, id)
        ct.modFlag = true
        syncLoadouts(bm)
    end
    return { ok = true, _emit = { "build", "config" } }
end

-- ============================================================================
-- Main State Snapshot (pob_configGetState)
-- ============================================================================
function pob_configGetState(searchText)
    local bm, ct, activeSet = ctx()
    if not bm or not ct or not activeSet then return nil end

    pob_ensureConfigVarControls(ct)

    -- Ensure mainEnv / usage sets exist (run a recalc if never computed yet)
    local usage = pob_getConfigUsageSets()
    if not usage then
        bm.buildFlag = true
        pob_recalculate()
        usage = pob_getConfigUsageSets() or {
            conditionsUsed = { }, enemyConditionsUsed = { }, minionConditionsUsed = { },
            multipliersUsed = { }, enemyMultipliersUsed = { }, perStatsUsed = { },
            enemyPerStatsUsed = { }, tagTypesUsed = { }, modsUsed = { },
            skillsUsed = { }, keystonesAdded = { },
        }
    end

    local search = (type(searchText) == "string") and searchText or ""
    local searchActive = search:match("%S") ~= nil

    -- Build collapsed lookup from live ct.sectionList
    local collapsedMap = { }
    for _, sec in ipairs(ct.sectionList or { }) do
        if sec.title then
            collapsedMap[sec.title] = sec.collapsed and true or false
        end
    end

    local vl = getVarList() or { }
    local sections = { }
    local curSection = nil

    for _, vd in ipairs(vl) do
        if vd.section then
            local isCustom = (vd.section == "Custom Modifiers")
            local collapsed = (collapsedMap[vd.section] == true) and (not searchActive)
            curSection = {
                name = vd.section,
                col = vd.col or 1,
                collapsed = collapsed,
                rawCollapsed = collapsedMap[vd.section] == true,
                isCustomMods = isCustom,
                items = { },
            }
            sections[#sections + 1] = curSection
        elseif vd.var and curSection then
            local visible, isInvalid, isNonDefault, borderState, cur = evalOptionState(bm, ct, activeSet, usage, vd, search)
            if visible then
                local rawLabel = vd.label or vd.var
                local displayLabel
                if isInvalid then
                    displayLabel = (colorCodes and colorCodes.NEGATIVE or "^xDD0022") .. StripEscapes(rawLabel)
                else
                    displayLabel = "^7" .. rawLabel
                end

                local placeholder = ""
                if activeSet.placeholder and activeSet.placeholder[vd.var] ~= nil then
                    placeholder = tostring(activeSet.placeholder[vd.var])
                elseif ct.varControls and ct.varControls[vd.var] and ct.varControls[vd.var].placeholder ~= nil then
                    placeholder = tostring(ct.varControls[vd.var].placeholder)
                end

                local t = vd.type or "text"
                local textValue = ""
                local selIndex = 1
                local options = nil
                local value = cur

                if t == "check" then
                    value = (cur == true)
                elseif t == "list" and vd.list then
                    options = { }
                    local effective = cur
                    if effective == nil then
                        effective = ct:GetDefaultState(vd.var)
                    end
                    for i, o in ipairs(vd.list) do
                        local oval = type(o) == "table" and o.val or o
                        local olabel = type(o) == "table" and (o.label or tostring(oval)) or tostring(o)
                        options[#options + 1] = { val = oval, label = olabel }
                        if oval == effective then
                            selIndex = i
                        end
                    end
                    value = effective
                else
                    textValue = (cur ~= nil) and tostring(cur) or ""
                end

                local item = {
                    var = vd.var,
                    label = rawLabel,
                    displayLabel = displayLabel,
                    type = t,
                    value = value,
                    textValue = textValue,
                    placeholder = placeholder,
                    selIndex = selIndex,
                    isInvalid = isInvalid,
                    isNonDefault = isNonDefault,
                    borderState = borderState,
                    hasTooltip = (vd.tooltip ~= nil or vd.tooltipFunc ~= nil or vd.ifNode ~= nil or isInvalid or t == "check" or t == "list"),
                }
                if options then
                    item.options = options
                end
                curSection.items[#curSection.items + 1] = item
            end
        end
    end

    -- Filter out empty non-custom sections (mirrors ConfigTab:Draw `section.shown = doShow`)
    local visibleSections = { }
    for _, sec in ipairs(sections) do
        if sec.isCustomMods or #sec.items > 0 then
            visibleSections[#visibleSections + 1] = sec
        end
    end

    -- Custom modifier blocks
    local customMods = { }
    local cml = activeSet.customModsList
    if not cml or #cml == 0 then
        cml = { { title = "Default", enabled = true, text = "" } }
        activeSet.customModsList = cml
    end
    for i, blk in ipairs(cml) do
        customMods[#customMods + 1] = {
            index = i,
            title = blk.title or "Default",
            enabled = (blk.enabled ~= false),
            text = blk.text or "",
        }
    end

    local sets, activeIdx = buildSetsList(ct)
    return {
        activeSetIndex = activeIdx,
        activeSetId = ct.activeConfigSetId or 1,
        sets = sets,
        toggleConfigs = ct.toggleConfigs and true or false,
        searchText = search,
        enemyLevel = ct.enemyLevel or 1,
        canUndo = (ct.undo and ct.undo[2] ~= nil) and true or false,
        canRedo = (ct.redo and ct.redo[1] ~= nil) and true or false,
        sections = visibleSections,
        customMods = customMods,
    }
end

-- ============================================================================
-- Part 7.3: Edits, Plumbing, Undo/Redo, Custom Mods, Tooltips
-- ============================================================================
local BUILD_MIRRORED_VARS = {
    bandit = true,
    pantheonMajorGod = true,
    pantheonMinorGod = true,
}

function pob_configSetOption(varName, value)
    local bm, ct, activeSet = ctx()
    if not bm or not ct or not activeSet then return fail("no configTab") end
    if type(varName) ~= "string" or varName == "" then return fail("invalid varName") end

    local varMap = getVarMap()
    local vd = varMap and varMap[varName]
    local coerced = value

    if vd then
        local t = vd.type
        if t == "check" then
            coerced = (value == true)
        elseif t == "count" or t == "integer" or t == "countAllowZero" or t == "float" then
            if value == nil or value == "" then
                coerced = nil
            else
                coerced = tonumber(value)
            end
        elseif t == "text" then
            coerced = (value ~= nil) and tostring(value) or ""
        end
    end

    activeSet.input[varName] = coerced
    if BUILD_MIRRORED_VARS[varName] then
        bm[varName] = coerced
    end

    -- Keep varControls in sync BEFORE BuildModList() so apply() closures
    -- reading varControls[k].selIndex / .placeholder see the new value.
    pob_ensureConfigVarControls(ct)
    if vd then
        syncSingleVarControl(ct, activeSet, vd)
    end

    ct:AddUndoState()
    ct:BuildModList()
    bm.buildFlag = true

    local emit = BUILD_MIRRORED_VARS[varName] and EMIT_CONFIG_TREE or EMIT_CONFIG
    return done({ var = varName, enemyLevel = ct.enemyLevel }, emit)
end

function pob_configSetToggleAll(enabled)
    local _, ct = ctx()
    if not ct then return fail("no configTab") end
    ct.toggleConfigs = (enabled == true)
    return { ok = true, toggleConfigs = ct.toggleConfigs, _emit = EMIT_UI_ONLY }
end

function pob_configToggleSection(sectionName)
    local _, ct = ctx()
    if not ct then return fail("no configTab") end
    for _, sec in ipairs(ct.sectionList or { }) do
        if sec.title == sectionName then
            sec.collapsed = not sec.collapsed
            return { ok = true, collapsed = sec.collapsed, _emit = EMIT_UI_ONLY }
        end
    end
    return fail("section not found")
end

function pob_configUndo()
    local bm, ct = ctx()
    if not ct then return fail("no configTab") end
    if ct.undo and ct.undo[2] ~= nil then
        pob_ensureConfigVarControls(ct)
        ct:Undo()
        local activeSet = ct.configSets and ct.configSets[ct.activeConfigSetId]
        if activeSet and activeSet.input then
            for k in pairs(BUILD_MIRRORED_VARS) do
                if activeSet.input[k] ~= nil then bm[k] = activeSet.input[k] end
            end
        end
        bm.buildFlag = true
        return done(nil, EMIT_CONFIG_TREE)
    end
    return { ok = true, noop = true, _emit = EMIT_UI_ONLY }
end

function pob_configRedo()
    local bm, ct = ctx()
    if not ct then return fail("no configTab") end
    if ct.redo and ct.redo[1] ~= nil then
        pob_ensureConfigVarControls(ct)
        ct:Redo()
        local activeSet = ct.configSets and ct.configSets[ct.activeConfigSetId]
        if activeSet and activeSet.input then
            for k in pairs(BUILD_MIRRORED_VARS) do
                if activeSet.input[k] ~= nil then bm[k] = activeSet.input[k] end
            end
        end
        bm.buildFlag = true
        return done(nil, EMIT_CONFIG_TREE)
    end
    return { ok = true, noop = true, _emit = EMIT_UI_ONLY }
end

-- Custom modifier blocks
function pob_configAddCustomMod()
    local bm, ct, activeSet = ctx()
    if not ct or not activeSet then return fail("no configTab") end
    if not activeSet.customModsList then activeSet.customModsList = { } end
    local idx = #activeSet.customModsList + 1
    t_insert(activeSet.customModsList, { title = "Group " .. idx, enabled = true, text = "" })
    ct:AddUndoState()
    ct:BuildModList()
    bm.buildFlag = true
    return done({ index = idx })
end

function pob_configRemoveCustomMod(index)
    local bm, ct, activeSet = ctx()
    if not ct or not activeSet then return fail("no configTab") end
    local cml = activeSet.customModsList
    local idx = tonumber(index)
    if not cml or not idx or idx < 1 or idx > #cml then return fail("invalid block index") end
    t_remove(cml, idx)
    if #cml == 0 then
        t_insert(cml, { title = "Default", enabled = true, text = "" })
    end
    ct:AddUndoState()
    ct:BuildModList()
    bm.buildFlag = true
    return done()
end

function pob_configUpdateCustomMod(index, title, enabled, text)
    local bm, ct, activeSet = ctx()
    if not ct or not activeSet then return fail("no configTab") end
    local cml = activeSet.customModsList
    local idx = tonumber(index)
    if not cml or not idx or idx < 1 or idx > #cml then return fail("invalid block index") end
    local blk = cml[idx]
    if title ~= nil then blk.title = tostring(title) end
    if enabled ~= nil then blk.enabled = (enabled == true) end
    if text ~= nil then blk.text = tostring(text) end
    ct:AddUndoState()
    ct:BuildModList()
    bm.buildFlag = true
    return done()
end

-- Dynamic tooltip (tooltip / tooltipFunc / ifNode / invalid / stat compare diff)
function pob_configTooltip(varName, hoverVal)
    local bm, ct, activeSet = ctx()
    if not bm or not ct or not activeSet then return { lines = { } } end
    local varMap = getVarMap()
    local vd = varMap and varMap[varName]
    if not vd then return { lines = { } } end

    local tip = new("Tooltip"):Tooltip()
    local usage = pob_getConfigUsageSets() or {
        conditionsUsed = { }, enemyConditionsUsed = { }, minionConditionsUsed = { },
        multipliersUsed = { }, enemyMultipliersUsed = { }, perStatsUsed = { },
        enemyPerStatsUsed = { }, tagTypesUsed = { }, modsUsed = { },
        skillsUsed = { }, keystonesAdded = { },
    }
    local _, isInvalid, _, _, cur = evalOptionState(bm, ct, activeSet, usage, vd, "")

    -- 1. Option's own tooltipFunc or static tooltip
    if vd.tooltipFunc then
        local mode = "OUT"
        local idx = 1
        local valArg = nil
        if vd.type == "list" and vd.list then
            local targetVal = (hoverVal ~= nil) and hoverVal or (cur ~= nil and cur or ct:GetDefaultState(vd.var))
            for i, entry in ipairs(vd.list) do
                local ev = type(entry) == "table" and entry.val or entry
                if ev == targetVal then
                    idx = i
                    valArg = entry
                    break
                end
            end
            mode = (hoverVal ~= nil) and "HOVER" or "OUT"
        else
            valArg = cur
        end
        pcall(vd.tooltipFunc, tip, mode, idx, valArg)
    else
        if type(vd.tooltip) == "string" and vd.tooltip ~= "" then
            tip:AddLine(14, vd.tooltip)
        elseif type(vd.tooltip) == "function" then
            local ok, txt = pcall(vd.tooltip, ct.modList, bm)
            if ok and type(txt) == "string" and txt ~= "" then
                tip:AddLine(14, txt)
            end
        end
        if vd.ifNode and bm.spec and bm.spec.nodes then
            local function addNodeHint(nid)
                local node = bm.spec.nodes[nid]
                if node and node.dn then
                    tip:AddLine(14, "This option is specific to '" .. node.dn .. "'.")
                end
            end
            if type(vd.ifNode) == "table" then
                for _, nid in ipairs(vd.ifNode) do addNodeHint(nid) end
            else
                addNodeHint(vd.ifNode)
            end
        end
    end

    -- 2. Invalid non-default warning OR stat-compare diff (ConfigTab.lua:752-798)
    if isInvalid then
        tip:AddLine(14, (colorCodes and colorCodes.NEGATIVE or "^xDD0022") .. "This config option is conditional with missing source and is invalid.")
    elseif (vd.type == "check") or (vd.type == "list" and hoverVal ~= nil) then
        local valueMapped = (vd.type == "check") and (not cur) or hoverVal
        if valueMapped ~= cur and bm.calcsTab and bm.calcsTab.GetMiscCalculator then
            local okCalc, calcFunc, calcBase = pcall(function()
                return bm.calcsTab:GetMiscCalculator(bm)
            end)
            if okCalc and calcFunc and calcBase then
                local savedFlag = bm.buildFlag
                local inputs = activeSet.input
                local beforeLines = #(tip.lines or { })
                tip:AddSeparator(10)
                local okSim, simOut = pcall(function()
                    inputs[vd.var] = valueMapped
                    syncSingleVarControl(ct, activeSet, vd)
                    ct:BuildModList()
                    return calcFunc()
                end)
                inputs[vd.var] = cur
                syncSingleVarControl(ct, activeSet, vd)
                ct:BuildModList()
                bm.buildFlag = savedFlag
                if okSim and simOut then
                    local prefix = (vd.type == "check") and "^7Toggling this" or "^7Selecting this"
                    pcall(function()
                        bm:AddStatComparesToTooltip(tip, calcBase, simOut, prefix .. " option will give you:")
                    end)
                end
                -- Remove dangling separator if no stat diff lines were added
                if #(tip.lines or { }) == beforeLines + 1 then
                    t_remove(tip.lines)
                end
            end
        end
    end

    return marshalTooltip(tip)
end

-- ============================================================================
-- Phase 7 Selftests
-- ============================================================================

-- Selftest 1: Config sets CRUD + varControls placeholder shim + set isolation.
function pob_selftestConfigSets()
    local bm, ct = ctx()
    if not bm or not ct then return fail("no configTab") end

    local origOrder = copyTable(ct.configSetOrderList)
    local origActiveId = ct.activeConfigSetId
    local origCount = #origOrder

    -- Create a new set (PR #9647 NewConfigSet path)
    local rCreate = pob_configCreateSet("Selftest Set A")
    if not rCreate or not rCreate.ok then
        return fail("create set failed: " .. tostring(rCreate and rCreate.error))
    end
    local setAId = rCreate.id
    local listAfterCreate = pob_configListSets()
    local createCountOk = (#listAfterCreate.sets == origCount + 1)
    local defaultBanditOk = (ct.configSets[setAId].input.bandit == "None")

    -- Mutate enemyIsBoss -> "Uber" in Set A and verify varControls shim sets placeholders
    local rBoss = pob_configSetOption("enemyIsBoss", "Uber")
    local activeSetA = ct.configSets[setAId]
    local phRes = activeSetA.placeholder and activeSetA.placeholder.enemyFireResist
    local phLevel = activeSetA.placeholder and activeSetA.placeholder.enemyLevel
    local varControlsShimOk = (rBoss and rBoss.ok == true and phRes ~= nil and phRes > 0 and ct.enemyLevel == 85)

    -- Copy Set A -> Set B, verify Boss setting copied
    local setAOrderIdx = listAfterCreate.activeIndex
    local rCopy = pob_configCopySet(setAOrderIdx, "Selftest Set B")
    if not rCopy or not rCopy.ok then
        return fail("copy set failed")
    end
    local setBId = rCopy.id
    local copyInheritedOk = (ct.configSets[setBId].input.enemyIsBoss == "Uber")

    -- Rename Set B
    local listAfterCopy = pob_configListSets()
    local setBOrderIdx = listAfterCopy.activeIndex
    local rRename = pob_configRenameSet(setBOrderIdx, "Selftest Set B Renamed")
    local renameOk = (rRename and rRename.ok == true and ct.configSets[setBId].title == "Selftest Set B Renamed")

    -- Move Set B up by 1
    local rMove = pob_configMoveSet(setBOrderIdx, setBOrderIdx - 1)
    local moveOk = (rMove and rMove.ok == true and ct.configSetOrderList[setBOrderIdx - 1] == setBId)

    -- Switch back to original set 1 and verify isolation
    local origIdx = 1
    for i, id in ipairs(ct.configSetOrderList) do
        if id == origActiveId then origIdx = i; break end
    end
    pob_configSetActiveSet(origIdx)
    local isolatedOk = (ct.activeConfigSetId == origActiveId and ct.configSets[origActiveId].input.enemyIsBoss ~= "Uber")

    -- Clean up Set B and Set A
    for _, delId in ipairs({ setBId, setAId }) do
        for i, id in ipairs(ct.configSetOrderList) do
            if id == delId then
                pob_configDeleteSet(i)
                break
            end
        end
    end
    ct:SetActiveConfigSet(origActiveId)
    ct:ResetUndo()
    bm.buildFlag = true
    pob_recalculate()

    local restoredOk = (#ct.configSetOrderList == origCount and ct.activeConfigSetId == origActiveId)
    local ok = createCountOk and defaultBanditOk and varControlsShimOk
        and copyInheritedOk and renameOk and moveOk and isolatedOk and restoredOk

    return {
        ok = ok,
        createCountOk = createCountOk,
        defaultBanditOk = defaultBanditOk,
        varControlsShimOk = varControlsShimOk,
        uberFireResistPlaceholder = phRes,
        uberLevelPlaceholder = phLevel,
        copyInheritedOk = copyInheritedOk,
        renameOk = renameOk,
        moveOk = moveOk,
        isolatedOk = isolatedOk,
        restoredOk = restoredOk,
    }
end

-- Selftest 2: Conditional visibility + Show All + invalid non-default highlight + search + undo/redo + UpdateLevel.
function pob_selftestConfigVis()
    local bm, ct, activeSet = ctx()
    if not bm or not ct or not activeSet then return fail("no configTab") end

    local origToggle = ct.toggleConfigs
    local origEnemyLevel = activeSet.input.enemyLevel

    bm.buildFlag = true
    pob_recalculate()
    local usage = pob_getConfigUsageSets()
    if not usage then return fail("no usage sets") end

    -- Find a conditional check option that is currently NOT relevant and NOT Show-All-excluded
    local vl = getVarList() or { }
    local cv = getConfigVisibility()
    local hiddenCheckVar = nil
    local excludedVar = nil
    for _, vd in ipairs(vl) do
        if vd.var and vd.type == "check" and not vd.hideIfInvalid and not vd.doNotHighlight then
            if (vd.ifNode or vd.ifCond or vd.ifEnemyCond) and not isRelevantForBuild(vd, bm, usage, activeSet.input) then
                local excluded = cv and cv.isShowAllExcluded and cv.isShowAllExcluded(vd)
                if not excluded and not hiddenCheckVar and not activeSet.input[vd.var] then
                    hiddenCheckVar = vd.var
                elseif excluded and not excludedVar and not activeSet.input[vd.var] then
                    excludedVar = vd.var
                end
            end
        end
        if hiddenCheckVar and excludedVar then break end
    end
    if not hiddenCheckVar then return fail("could not find hidden conditional check var") end

    local function findInState(st, varName)
        for _, sec in ipairs(st.sections or { }) do
            for _, it in ipairs(sec.items or { }) do
                if it.var == varName then return it end
            end
        end
        return nil
    end

    -- 1. Hidden by default
    pob_configSetToggleAll(false)
    local stDefault = pob_configGetState("")
    local hiddenInitiallyOk = (findInState(stDefault, hiddenCheckVar) == nil)

    -- 2. Show All reveals eligible hidden option, still hides excluded option
    pob_configSetToggleAll(true)
    local stShowAll = pob_configGetState("")
    local showAllRevealsOk = (findInState(stShowAll, hiddenCheckVar) ~= nil)
    local showAllExcludesOk = (not excludedVar) or (findInState(stShowAll, excludedVar) == nil)

    -- 3. Disable Show All, set hidden option to non-default -> stays visible as INVALID (red + tooltip)
    pob_configSetToggleAll(false)
    pob_configSetOption(hiddenCheckVar, true)
    local stInvalid = pob_configGetState("")
    local invItem = findInState(stInvalid, hiddenCheckVar)
    local invalidHighlightOk = (invItem ~= nil and invItem.isInvalid == true and invItem.borderState == "invalid"
        and invItem.displayLabel:find("%^xDD0022") ~= nil)
    local invTip = pob_configTooltip(hiddenCheckVar)
    local invalidTipOk = false
    for _, l in ipairs(invTip.lines or { }) do
        if l.text and l.text:lower():find("invalid", 1, true) then
            invalidTipOk = true
            break
        end
    end

    -- 4. Undo restores hiddenCheckVar to false; Redo sets it back to true; Undo again cleans up
    pob_configUndo()
    local undoOk = (not activeSet.input[hiddenCheckVar])
    pob_configRedo()
    local redoOk = (activeSet.input[hiddenCheckVar] == true)
    pob_configUndo()

    -- 5. Search: normal query finds bandit; malformed Lua pattern does not crash
    local stSearch = pob_configGetState("bandit")
    local searchFoundBandit = (findInState(stSearch, "bandit") ~= nil)
    local searchFiltered = (findInState(stSearch, "enemyIsBoss") == nil)
    local okPat, stPat = pcall(pob_configGetState, "[unclosed(pattern*")
    local searchPatternSafeOk = (okPat and type(stPat) == "table")

    -- 6. UpdateLevel clamps enemyLevel to data.misc.MaxEnemyLevel
    pob_configSetOption("enemyLevel", 999)
    local clampOk = (ct.enemyLevel == data.misc.MaxEnemyLevel)

    -- Restore
    pob_configSetOption("enemyLevel", origEnemyLevel)
    activeSet.input[hiddenCheckVar] = nil
    pob_configSetToggleAll(origToggle)
    ct:BuildModList()
    ct:ResetUndo()
    bm.buildFlag = true
    pob_recalculate()

    local ok = hiddenInitiallyOk and showAllRevealsOk and showAllExcludesOk
        and invalidHighlightOk and invalidTipOk and undoOk and redoOk
        and searchFoundBandit and searchFiltered and searchPatternSafeOk and clampOk

    return {
        ok = ok,
        testedVar = hiddenCheckVar,
        excludedVar = excludedVar,
        hiddenInitiallyOk = hiddenInitiallyOk,
        showAllRevealsOk = showAllRevealsOk,
        showAllExcludesOk = showAllExcludesOk,
        invalidHighlightOk = invalidHighlightOk,
        invalidTipOk = invalidTipOk,
        undoOk = undoOk,
        redoOk = redoOk,
        searchFoundBandit = searchFoundBandit,
        searchFiltered = searchFiltered,
        searchPatternSafeOk = searchPatternSafeOk,
        clampOk = clampOk,
    }
end

-- Selftest 3: <Config> XML round-trip, legacy flat Input + back-compat rewrites, ImportCalcSettings.
function pob_selftestConfigPersist()
    local bm, ct = ctx()
    if not bm or not ct then return fail("no configTab") end

    -- Snapshot original XML to restore cleanly at end
    local origXml = { elem = "Config" }
    ct:Save(origXml)
    local origBandit = bm.bandit
    local origMajor = bm.pantheonMajorGod
    local origMinor = bm.pantheonMinorGod

    -- 1. Mutate options (incl. Bandit/Pantheon + Boss + Custom Mod) and create a 2nd set
    pob_configSetOption("bandit", "Alira")
    pob_configSetOption("pantheonMajorGod", "TheBrineKing")
    pob_configSetOption("enemyIsBoss", "Pinnacle")
    pob_configUpdateCustomMod(1, "Selftest Group", true, "+10 to maximum Life")

    local rSet2 = pob_configCreateSet("Bossing")
    pob_configSetOption("enemyIsBoss", "Uber")
    local set2Id = rSet2.id

    -- 2. Save to <Config> XML
    local savedXml = { elem = "Config" }
    ct:Save(savedXml)
    local activeAttrOk = (tonumber(savedXml.attrib and savedXml.attrib.activeConfigSet) == set2Id)
    local savedSetCount = 0
    local hasNonDefaultOnly = true
    for _, node in ipairs(savedXml) do
        if node.elem == "ConfigSet" then
            savedSetCount = savedSetCount + 1
            for _, child in ipairs(node) do
                if child.elem == "Input" and child.attrib.name == "bandit" and child.attrib.string == "None" then
                    hasNonDefaultOnly = false
                end
            end
        end
    end
    local savedSetsOk = (savedSetCount >= 2)

    -- 3. Test legacy flat <Input> XML + back-compat rewrites (Shaper->Pinnacle, Uber Atziri->Atziri)
    local legacyXml = {
        elem = "Config",
        attrib = { },
        { elem = "Input", attrib = { name = "enemyIsBoss", string = "Shaper" } },
        { elem = "Input", attrib = { name = "presetBossSkills", string = "Uber Atziri Flameblast" } },
        { elem = "Placeholder", attrib = { name = "enemyPhysicalReduction", number = "15" } },
    }
    ct:Load(legacyXml, "selftest_legacy")
    local backCompatOk = (ct.configSets[1].input.enemyIsBoss == "Pinnacle"
        and ct.configSets[1].input.presetBossSkills == "Atziri Flameblast"
        and ct.configSets[1].placeholder.enemyPhysicalReduction == 15)

    -- 4. Test ImportCalcSettings migration
    local prevCalcsLowLife = bm.calcsTab.input.Cond_LowLife
    bm.calcsTab.input.Cond_LowLife = true
    ct:ImportCalcSettings()
    local importCalcOk = (ct.configSets[ct.activeConfigSetId].input.conditionLowLife == true
        and bm.calcsTab.input.Cond_LowLife == nil)
    bm.calcsTab.input.Cond_LowLife = prevCalcsLowLife

    -- 5. Reload savedXml and verify full round-trip fidelity
    ct:Load(savedXml, "selftest_roundtrip")
    local rtActiveOk = (ct.activeConfigSetId == set2Id
        and ct.configSets[set2Id] ~= nil
        and ct.configSets[set2Id].input.enemyIsBoss == "Uber")
    local set1 = ct.configSets[ct.configSetOrderList[1]]
    local rtSet1Ok = (set1 ~= nil
        and set1.input.bandit == "Alira"
        and set1.input.pantheonMajorGod == "TheBrineKing"
        and set1.input.enemyIsBoss == "Pinnacle"
        and set1.customModsList and set1.customModsList[1]
        and set1.customModsList[1].text == "+10 to maximum Life")

    -- Restore original XML snapshot cleanly
    ct:Load(origXml, "selftest_restore")
    bm.bandit = origBandit
    bm.pantheonMajorGod = origMajor
    bm.pantheonMinorGod = origMinor
    ct:BuildModList()
    ct:ResetUndo()
    bm.buildFlag = true
    pob_recalculate()

    local ok = activeAttrOk and savedSetsOk and hasNonDefaultOnly
        and backCompatOk and importCalcOk and rtActiveOk and rtSet1Ok

    return {
        ok = ok,
        activeAttrOk = activeAttrOk,
        savedSetsOk = savedSetsOk,
        hasNonDefaultOnly = hasNonDefaultOnly,
        backCompatOk = backCompatOk,
        importCalcOk = importCalcOk,
        rtActiveOk = rtActiveOk,
        rtSet1Ok = rtSet1Ok,
    }
end
