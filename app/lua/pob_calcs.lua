-- Path of Building (Qt port)
--
-- Module: pob_calcs.lua  --  Calcs tab bridge (Phase 8)
--
-- WHAT THIS IS
--   The Calcs tab (src/Classes/CalcsTab.lua, CalcSectionControl.lua,
--   CalcBreakdownControl.lua, src/Modules/CalcSections.lua) re-authored over
--   the LIVE legacy calcsTab. Three pieces:
--
--   1. A reusable SECTION-MODEL RESOLVER (pob_calcs.resolveSections): walks a
--      CalcSectionControl list against an actor and returns plain rows --
--      CheckFlag gating (flag/flagList/playerFlag/notFlag/notFlagList/
--      haveOutput), legacy UpdateSize heights, and formatCalcStr cell text
--      (incl. {N:mod:i,j} live modStore:Combine). It takes the section list
--      and actors as arguments so the Compare tab (Phase 13) can resolve the
--      same grid for a second build.
--   2. ON-DEMAND BREAKDOWN SERIALIZATION (pob_calcs.serializeBreakdown): a
--      port of CalcBreakdownControl:SetBreakdownData/AddBreakdownSection/
--      AddModSection to data. Runs per click/hover (never bulk): reads
--      actor.breakdown[key] and issues live modStore:Tabulate/Combine; item /
--      tree cross-refs become ids (itemId / nodeId) resolved by the item
--      tooltip bridge and the embedded TreeViewer.
--   3. The tab's own state: the INDEPENDENT *Calcs skill selection (driven by
--      calcsTab.input.skill_number, NOT build.mainSocketGroup), Calculation
--      Mode (input.misc_buffMode), Show Minion Stats, subsection collapse
--      (subSection.collapsed -- the field CalcsTab:Save/Load persist as
--      <Section id subsection collapsed>), search and undo/redo.
--
--   Every value crossing the bridge is a plain string/number/bool table; no
--   closures, mod objects or Tooltip objects are returned.

local t_insert = table.insert
local m_floor = math.floor
local m_min = math.min
local m_max = math.max
local m_sin = math.sin
local m_cos = math.cos
local m_pi = math.pi
local band = bit.band

local M = { }
pob_calcs = M

local EMIT = { "build", "calcs" }

local function ctx()
    local bm = main and main.modes and main.modes.BUILD
    return bm, bm and bm.calcsTab
end

---------------------------------------------------------------------------
-- Colour helpers (legacy colour codes -> #RRGGBB for QML rectangles)
---------------------------------------------------------------------------

local DIGIT_HEX = {
    ["0"] = "#000000", ["1"] = "#FF0000", ["2"] = "#00FF00", ["3"] = "#0000FF",
    ["4"] = "#FFFF00", ["5"] = "#FF00FF", ["6"] = "#00FFFF", ["7"] = "#FFFFFF",
    ["8"] = "#B3B3B3", ["9"] = "#666666",
}

function M.codeHex(code, default)
    if type(code) == "table" then
        -- {r, g, b} 0..1 (SetDrawColor table form)
        local r, g, b = code[1] or 0, code[2] or 0, code[3] or 0
        return string.format("#%02X%02X%02X", m_floor(r * 255 + 0.5), m_floor(g * 255 + 0.5), m_floor(b * 255 + 0.5))
    end
    if type(code) ~= "string" then return default end
    local hex = code:match("^%^[xX](%x%x%x%x%x%x)")
    if hex then return "#" .. hex:upper() end
    local d = code:match("^%^(%d)")
    if d then return DIGIT_HEX[d] end
    return default
end

---------------------------------------------------------------------------
-- 1. Section-model resolver
---------------------------------------------------------------------------

-- Port of CalcsTab:CheckFlag (CalcsTab.lua:396) with explicit actors.
function M.checkFlag(obj, actor, player)
    if not actor or not actor.mainSkill then return false end
    local skillFlags = actor.mainSkill.skillFlags or { }
    if obj.flag and not skillFlags[obj.flag] then return false end
    if obj.flagList then
        for _, flag in ipairs(obj.flagList) do
            if not skillFlags[flag] then return false end
        end
    end
    if obj.playerFlag then
        local p = player or actor
        if not (p.mainSkill and p.mainSkill.skillFlags and p.mainSkill.skillFlags[obj.playerFlag]) then
            return false
        end
    end
    if obj.notFlag and skillFlags[obj.notFlag] then return false end
    if obj.notFlagList then
        for _, flag in ipairs(obj.notFlagList) do
            if skillFlags[flag] then return false end
        end
    end
    if obj.haveOutput then
        local out = actor.output or { }
        local ns, var = obj.haveOutput:match("^(%a+)%.(%a+)$")
        if ns then
            if not out[ns] or not out[ns][var] or out[ns][var] == 0 then return false end
        elseif not out[obj.haveOutput] or out[obj.haveOutput] == 0 then
            return false
        end
    end
    return true
end

local function safeFormat(fmt, actor, colData)
    if not formatCalcStr then return "" end
    local ok, v = pcall(formatCalcStr, fmt, actor, colData)
    if ok and v ~= nil then return tostring(v) end
    return ""
end

local function hasBreakdownEntries(colData)
    for _, sub in ipairs(colData) do
        if type(sub) == "table" and (sub.breakdown or sub.modName) then return true end
    end
    return false
end

-- Resolve one CalcSectionControl into plain data. Mirrors UpdateSize
-- (CalcSectionControl.lua:114, height/enabled) and DrawContent (:437, which
-- subsections/rows are drawn; a collapsed PRIMARY subsection stops drawing).
-- keyPrefix addresses cells for the breakdown round trip ("si:ui:ri:ci").
function M.resolveSection(section, si, actor, player, colWidth)
    colWidth = colWidth or 230
    local widthCols = section.widthCols or 1
    local width = widthCols * colWidth + 8 * (widthCols - 1)
    local res = {
        index = si,
        id = section.id,
        group = section.group,
        widthCols = widthCols,
        width = width,
        colour = M.codeHex(section.colour, "#FFFFFF"),
        special = section.id == "SkillSelect",
        enabled = false,
        height = 22,
        subs = { },
    }
    if not M.checkFlag(section, actor, player) then
        return res
    end
    -- UpdateSize, line for line (including its running-`enabled` quirk).
    local height = 2
    local enabled = false
    local rowEnabled = { }
    for ui, subSec in ipairs(section.subSection) do
        local tempHeight = 0
        rowEnabled[ui] = { }
        for ri, rowData in ipairs(subSec.data) do
            local en = M.checkFlag(rowData, actor, player)
            rowEnabled[ui][ri] = en
            if en then
                enabled = true
                height = height + 18
                tempHeight = tempHeight + 18
            end
        end
        if enabled and not subSec.collapsed then
            height = height + 22
        else
            height = height - tempHeight + 20
        end
    end
    if not enabled then
        return res
    end
    res.enabled = true
    res.height = (not section.subSection[1].collapsed) and height or 22

    -- DrawContent: which subsections/rows are actually drawn.
    local primary = true
    for ui, subSec in ipairs(section.subSection) do
        local sub = {
            index = ui,
            id = subSec.id or (subSec.label or ""):gsub("%W", ""),
            label = subSec.label or "",
            collapsed = subSec.collapsed and true or false,
            extra = subSec.data.extra and safeFormat(subSec.data.extra, actor) or "",
            rows = { },
        }
        t_insert(res.subs, sub)
        if subSec.collapsed then
            if primary then break end
            primary = false
        else
            primary = false
            local cellWidth = subSec.data.colWidth or (width - 136)
            for ri, rowData in ipairs(subSec.data) do
                if rowEnabled[ui][ri] then
                    local row = {
                        index = ri,
                        label = rowData.label or "",
                        color = rowData.color or "^7",
                        bgCol = M.codeHex(rowData.bgCol, "#000000"),
                        textSize = rowData.textSize or 14,
                        cells = { },
                    }
                    for ci, colData in ipairs(rowData) do
                        local cell = {
                            key = si .. ":" .. ui .. ":" .. ri .. ":" .. ci,
                            width = cellWidth,
                            text = "",
                            breakdown = false,
                        }
                        if colData.control then
                            cell.control = colData.controlName
                        elseif colData.format and M.checkFlag(colData, actor, player) then
                            cell.text = "^7" .. safeFormat(colData.format, actor, colData)
                            cell.breakdown = hasBreakdownEntries(colData)
                        end
                        t_insert(row.cells, cell)
                    end
                    t_insert(sub.rows, row)
                end
            end
        end
    end
    return res
end

-- Resolve a whole section list (any build / actor pair).
function M.resolveSections(sectionList, actor, player, colWidth)
    local out = { }
    for si, section in ipairs(sectionList or { }) do
        t_insert(out, M.resolveSection(section, si, actor, player, colWidth))
    end
    return out
end

-- Calcs-tab actor (CalcSectionControl:Draw): minion when "Show Minion Stats".
function M.calcsActor(ct)
    local env = ct and ct.calcsEnv
    if not env then return nil, nil end
    local actor = (ct.input.showMinion and env.minion) or env.player
    return actor, env
end

local function ensureOutput(bm, ct)
    pob_recalculate()
    if not ct.calcsEnv then
        pcall(function() ct:BuildOutput() end)
    end
    return ct.calcsEnv ~= nil
end

function pob_calcsGetGrid()
    local bm, ct = ctx()
    if not ct then return nil end
    if not ensureOutput(bm, ct) then return nil end
    local actor, env = M.calcsActor(ct)
    local sections = M.resolveSections(ct.sectionList, actor, env.player, ct.colWidth)
    return {
        sections = sections,
        colWidth = ct.colWidth or 230,
        portrait = (main and main.portraitMode) and true or false,
        showMinion = ct.input.showMinion and true or false,
        buffMode = ct.input.misc_buffMode or "EFFECTIVE",
        skillNumber = ct.input.skill_number or 1,
        outputRevision = bm.outputRevision or 0,
    }
end

-- CalcsTab:SearchMatch (CalcsTab.lua:435) for every drawn label: returns the
-- keys ("si:ui" subsection labels, "si:ui:ri" row labels) that match. Legacy
-- uses Lua find with patterns, so a malformed pattern simply matches nothing.
function pob_calcsSearch(str)
    local bm, ct = ctx()
    local res = { count = 0, keys = { }, matched = { }, sections = { } }
    if not ct or type(str) ~= "string" then return res end
    local needle = str:lower()
    if #needle == 0 then return res end
    local function match(txt)
        if not txt or txt == "" then return false end
        local ok, found = pcall(string.find, txt:lower(), needle)
        return ok and found ~= nil
    end
    for si, section in ipairs(ct.sectionList) do
        for ui, subSec in ipairs(section.subSection) do
            if match(subSec.label) then
                local k = si .. ":" .. ui
                t_insert(res.keys, k)
                res.matched[k] = true
                res.sections[tostring(si)] = true
            end
            for ri, rowData in ipairs(subSec.data) do
                if match(rowData.label) then
                    local k = si .. ":" .. ui .. ":" .. ri
                    t_insert(res.keys, k)
                    res.matched[k] = true
                    res.sections[tostring(si)] = true
                end
            end
        end
    end
    res.count = #res.keys
    return res
end

-- The +/- toggle (CalcSectionControl.lua:50-55): flips subSec.collapsed and
-- marks the tab modified. No recalc -- QML re-reads the grid.
function pob_calcsToggleSubsection(si, ui)
    local bm, ct = ctx()
    if not ct then return { ok = false, error = "no calcsTab" } end
    local section = ct.sectionList[tonumber(si) or 0]
    local subSec = section and section.subSection[tonumber(ui) or 0]
    if not subSec then return { ok = false, error = "no such subsection" } end
    subSec.collapsed = not subSec.collapsed
    ct.modFlag = true
    return { ok = true, collapsed = subSec.collapsed }
end

---------------------------------------------------------------------------
-- 3. Independent *Calcs skill selection + calc mode
---------------------------------------------------------------------------

-- The payload pob_getMainSkillControls(suffix) builds, but for the Calcs
-- tab's own socket group (calcsTab.input.skill_number) -- legacy calls
-- RefreshSkillSelectControls(controls, self.input.skill_number, "Calcs").
-- The shared builder reads build.mainSocketGroup, so it is pointed at
-- skill_number for the duration of the (recalc-free) read and restored.
function pob_calcsGetSkillSelect()
    local bm, ct = ctx()
    if not ct or not pob_getMainSkillControls then return nil end
    pob_recalculate()
    local count = #bm.skillsTab.socketGroupList
    local skillNumber = m_min(m_max(count, 1), ct.input.skill_number or 1)
    local saved = bm.mainSocketGroup
    local savedFlag = bm.buildFlag
    bm.mainSocketGroup = skillNumber
    bm.buildFlag = false
    local ok, d = pcall(pob_getMainSkillControls, "Calcs")
    bm.mainSocketGroup = saved
    bm.buildFlag = savedFlag
    if not ok or not d then return nil end
    d.mainSocketGroup = skillNumber
    d.showMinion = ct.input.showMinion and true or false
    d.buffMode = ct.input.misc_buffMode or "EFFECTIVE"
    local actor, env = M.calcsActor(ct)
    local player = env and env.player
    local flags = player and player.mainSkill and player.mainSkill.skillFlags or { }
    local aflags = actor and actor.mainSkill and actor.mainSkill.skillFlags or { }
    -- Row gates of the SkillSelect section (CalcsTab.lua:67-125).
    d.rowFlags = {
        multiPart = flags.multiPart and true or false,
        multiStage = flags.multiStage and true or false,
        mine = flags.mine and true or false,
        haveMinion = aflags.haveMinion and true or false,
        minion = aflags.minion and true or false,
        spectre = aflags.spectre and true or false,
    }
    d.buffModes = {
        { label = "Unbuffed", buffMode = "UNBUFFED" },
        { label = "Buffed", buffMode = "BUFFED" },
        { label = "In Combat", buffMode = "COMBAT" },
        { label = "Effective DPS", buffMode = "EFFECTIVE" },
    }
    return d
end

local function calcsSrcInstance(bm, ct)
    local sg = bm.skillsTab.socketGroupList[ct.input.skill_number or 1]
    if not sg then return nil end
    local list = sg.displaySkillListCalcs
    local active = list and list[sg.mainActiveSkillCalcs or 1]
    if not active or not active.activeEffect then return nil, sg end
    return active.activeEffect.srcInstance, sg
end

local function commit(bm, ct, undo)
    if undo then ct:AddUndoState() end
    bm.buildFlag = true
    pob_recalculate()
    return { ok = true, outputRevision = bm.outputRevision or 0, _emit = EMIT }
end

-- field: group | skill | part | stages | mines | minion | minionSkill.
-- Each mirrors its CalcsTab.lua:46-125 callback (incl. which ones push undo).
function pob_calcsSetSkill(field, value)
    local bm, ct = ctx()
    if not ct then return { ok = false, error = "no calcsTab" } end
    if field == "group" then
        ct.input.skill_number = tonumber(value) or 1
        return commit(bm, ct, true)
    end
    local srcInstance, sg = calcsSrcInstance(bm, ct)
    if field == "skill" then
        if not sg then return { ok = false, error = "no socket group" } end
        sg.mainActiveSkillCalcs = tonumber(value) or 1
        return commit(bm, ct, false)
    end
    if not srcInstance then return { ok = false, error = "no active skill" } end
    if field == "part" then
        srcInstance.skillPartCalcs = tonumber(value)
    elseif field == "stages" then
        srcInstance.skillStageCountCalcs = tonumber(value)
    elseif field == "mines" then
        srcInstance.skillMineCountCalcs = tonumber(value)
    elseif field == "minion" then
        if type(value) == "table" and value.itemSetId then
            srcInstance.skillMinionItemSetCalcs = value.itemSetId
        elseif type(value) == "table" and value.minionId then
            srcInstance.skillMinionCalcs = value.minionId
        else
            return { ok = false, error = "value needs minionId or itemSetId" }
        end
    elseif field == "minionSkill" then
        srcInstance.skillMinionSkillCalcs = tonumber(value)
    else
        return { ok = false, error = "unknown field " .. tostring(field) }
    end
    return commit(bm, ct, true)
end

local BUFF_MODES = { UNBUFFED = true, BUFFED = true, COMBAT = true, EFFECTIVE = true }

-- name: misc_buffMode (Calculation Mode; affects ONLY calcsEnv) | showMinion.
function pob_calcsSetInput(name, value)
    local bm, ct = ctx()
    if not ct then return { ok = false, error = "no calcsTab" } end
    if name == "misc_buffMode" then
        if not BUFF_MODES[value] then return { ok = false, error = "bad buffMode" } end
        ct.input.misc_buffMode = value
        return commit(bm, ct, true)
    elseif name == "showMinion" then
        -- CalcsTab.lua:94-97: undo state only; the grid just swaps actors.
        ct.input.showMinion = value and true or false
        ct:AddUndoState()
        return { ok = true, _emit = { "calcs" } }
    end
    return { ok = false, error = "unknown input " .. tostring(name) }
end

-- Ctrl+Z / Ctrl+Y (CalcsTab.lua:323-328).
function pob_calcsUndo()
    local bm, ct = ctx()
    if not ct or not ct.undo or #ct.undo < 2 then return { ok = false } end
    ct:Undo()
    return commit(bm, ct, false)
end

function pob_calcsRedo()
    local bm, ct = ctx()
    if not ct or not ct.redo or #ct.redo < 1 then return { ok = false } end
    ct:Redo()
    return commit(bm, ct, false)
end

---------------------------------------------------------------------------
-- 2. On-demand breakdown serializer
---------------------------------------------------------------------------

local function cellData(ct, key)
    if type(key) ~= "string" then return nil end
    local si, ui, ri, ci = key:match("^(%d+):(%d+):(%d+):(%d+)$")
    if not si then return nil end
    local section = ct.sectionList[tonumber(si)]
    local subSec = section and section.subSection[tonumber(ui)]
    local rowData = subSec and subSec.data[tonumber(ri)]
    local colData = rowData and rowData[tonumber(ci)]
    return colData, rowData, subSec, section
end

local function numSep(s)
    s = tostring(s)
    if formatNumSep then
        local ok, r = pcall(formatNumSep, s)
        if ok and r then return (r) end
    end
    return s
end

-- DrawBreakdownTable's per-cell number test (CalcBreakdownControl.lua:611-614).
local function numericLike(s)
    local _, alpha = s:gsub("%a", " ")
    local _, notes = s:gsub(" to ", " ")
    local _, paren = s:gsub("%b()", " ")
    return alpha == 0 or notes > 0 or paren > 0
end

-- Turn a TABLE section (rowList + colList) into plain rows. Only columns some
-- row fills are kept (legacy only gives those a width). rowTip(row, col)
-- returns a plain tooltip descriptor or nil.
local function tableSection(label, footer, rowList, colList, rowTip)
    local cols = { }
    for _, col in ipairs(colList) do
        for _, row in ipairs(rowList) do
            if row[col.key] ~= nil then
                t_insert(cols, col)
                break
            end
        end
    end
    local rows = { }
    for _, row in ipairs(rowList) do
        local cells = { }
        for _, col in ipairs(cols) do
            local v = row[col.key]
            local cell = { text = "" }
            if v ~= nil then
                local s = tostring(v)
                local num = numericLike(s)
                cell.text = "^7" .. (num and numSep(s) or s)
                cell.right = (num and col.right) and true or false
                local tip = rowTip and rowTip(row, col)
                if tip then cell.tip = tip end
            end
            t_insert(cells, cell)
        end
        t_insert(rows, { cells = cells })
    end
    local outCols = { }
    for _, col in ipairs(cols) do
        t_insert(outCols, { label = col.label, key = col.key, right = col.right and true or false })
    end
    return {
        type = "TABLE",
        label = label or "",
        footer = footer or "",
        cols = outCols,
        rows = rows,
    }
end

-- Radius visualiser geometry: main:RenderCircle's projected circle
-- (Main.lua:1601) sampled to a polygon in the 480x270 image space the legacy
-- section uses (8 + 1920/4 wide, 4 + 1080/4 high, minus the 4px inset).
function M.radiusPolygon(radius, width, height)
    width = width or 480
    height = height or 270
    local pts = { }
    if not (main and main.WorldToScreen) then return pts end
    for i = 0, 179 do
        local r = i / 180 * 2 * m_pi
        local px, py = main:WorldToScreen(m_sin(r) * radius, m_cos(r) * radius, 0, width, height)
        px = m_min(width, m_max(0, px))
        py = m_min(height, m_max(0, py))
        t_insert(pts, px)
        t_insert(pts, py)
    end
    return pts
end

-- Port of AddModSection (CalcBreakdownControl.lua:302) to data.
local function addModSection(out, fmt, build, actor, sectionData, modList)
    local cfg = (sectionData.cfg and actor.mainSkill[sectionData.cfg .. "Cfg"]
        and copyTable(actor.mainSkill[sectionData.cfg .. "Cfg"], true)) or { }
    cfg.source = sectionData.modSource
    cfg.actor = sectionData.actor
    local modStore = (sectionData.enemy and actor.enemy.modDB)
        or (sectionData.cfg and actor.mainSkill.skillModList) or actor.modDB
    local rowList
    if modList then
        rowList = copyTable(modList)
    elseif type(sectionData.modName) == "table" then
        rowList = modStore:Tabulate(sectionData.modType, cfg, unpack(sectionData.modName))
    else
        rowList = modStore:Tabulate(sectionData.modType, cfg, sectionData.modName)
    end
    if #rowList == 0 then return end

    local colList = {
        { label = "Value", key = "displayValue" },
        { label = "Stat", key = "name" },
        { label = "Skill types", key = "flags" },
        { label = "Notes", key = "tags" },
        { label = "Source", key = "source" },
        { label = "Source Name", key = "sourceName" },
    }

    local function byValue(a, b)
        return a.mod.name > b.mod.name or (a.mod.name == b.mod.name and type(a.value) == "number" and type(b.value) == "number") and a.value > b.value
    end
    if not modList and not sectionData.modType then
        pcall(table.sort, rowList, function(a, b)
            if a.mod.type == b.mod.type then
                return byValue(a, b)
            end
            return a.mod.type < b.mod.type
        end)
    else
        pcall(table.sort, rowList, byValue)
    end

    -- Per-source totals (the Source column's tooltip), via live Combine.
    local sourceTotals = { }
    if not modList and not sectionData.modSource then
        local types, typeList = { }, { }
        for _, row in ipairs(rowList) do
            if not types[row.mod.type] then
                types[row.mod.type] = true
                t_insert(typeList, row.mod.type)
            end
            local sourceType = (row.mod.source or ""):match("[^:]+") or ""
            sourceTotals[sourceType] = sourceTotals[sourceType] or { }
        end
        for sourceType, lines in pairs(sourceTotals) do
            cfg.source = sourceType
            for _, modType in ipairs(typeList) do
                local names = type(sectionData.modName) == "table" and sectionData.modName or { sectionData.modName }
                for _, modName in ipairs(names) do
                    local total = modStore:Combine(modType, cfg, modName)
                    if modType == "MORE" then
                        total = round((total - 1) * 100)
                    end
                    if total and total ~= 0 then
                        local line = fmt:FormatModValue(total, modType)
                        if type(sectionData.modName) == "table" then
                            line = line .. " " .. modName:gsub("(%l)(%u)", "%1 %2")
                        end
                        t_insert(lines, tostring(line))
                    end
                end
            end
        end
    end

    local plainRows = { }
    for _, row in ipairs(rowList) do
        local p = { }
        if not sectionData.modType then
            p.displayValue = fmt:FormatModValue(row.value, row.mod.type)
        else
            colList[1].right = true
            p.displayValue = formatRound(row.value, 2)
        end
        if modList or type(sectionData.modName) == "table" then
            p.name = fmt:FormatModName(row.mod.name)
        end
        local sourceType = row.mod.source and row.mod.source:match("[^:]+") or ""
        p.source = sourceType
        if not modList and not sectionData.modSource then
            p._sourceTotals = sourceTotals[sourceType]
        end
        if sourceType == "Item" then
            local itemId = tonumber(row.mod.source:match("Item:(%d+):.+"))
            local item = itemId and build.itemsTab.items[itemId]
            if item then
                p.sourceName = (colorCodes[item.rarity] or "") .. item.name
                p._itemId = item.id
                p._itemSlot = row.mod.sourceSlot
            end
        elseif sourceType == "Tree" then
            local nodeId = row.mod.source:match("Tree:(%d+)")
            local textNodeId = row.mod.source:match("Tree:([%w_]+)")
            if nodeId then
                local n = tonumber(nodeId)
                local node = build.spec.nodes[n] or build.spec.tree.nodes[n]
                    or (build.latestTree and build.latestTree.nodes[n])
                if node then
                    p.sourceName = node.dn
                    -- Cluster-jewel abstract nodes have no location
                    -- (CalcBreakdownControl.lua:633): no viewer for those.
                    if node.x and node.y then p._nodeId = node.id or n end
                end
            elseif textNodeId then
                local tree = build.spec.tree
                p.sourceName = tree.tattoo and tree.tattoo.idMap and tree.tattoo.idMap[textNodeId]
                if not p.sourceName and tree.legion and tree.legion.nodes then
                    for _, node in pairs(tree.legion.nodes) do
                        if node.id == textNodeId then
                            p.sourceName = node.dn
                            break
                        end
                    end
                end
            end
        elseif sourceType == "Skill" then
            local skill = build.data.skills[row.mod.source:match("Skill:(.+)") or ""]
            p.sourceName = skill and skill.name
        elseif sourceType == "Pantheon" then
            p.sourceName = row.mod.source:match("Pantheon:(.+)")
        elseif sourceType == "Spectre" then
            p.sourceName = row.mod.source:match("Spectre:(.+)")
        elseif sourceType == "Custom" then
            p.sourceName = row.mod.source:match("Custom:(.+)")
        end

        if (row.mod.flags or 0) ~= 0 or (row.mod.keywordFlags or 0) ~= 0 then
            local flagNames = { }
            for flags, src in pairs({ [row.mod.flags or 0] = ModFlag, [row.mod.keywordFlags or 0] = KeywordFlag }) do
                for name, val in pairs(src) do
                    if band(flags, val) == val then
                        t_insert(flagNames, name)
                    end
                end
            end
            table.sort(flagNames)
            p.flags = table.concat(flagNames, ", ")
        end
        if row.mod[1] then
            local tags
            local baseVal = type(row.mod.value) == "number" and (fmt:FormatModBase(row.mod, row.mod.value) .. " ")
            for _, tag in ipairs(row.mod) do
                local desc
                if tag.type == "Condition" or tag.type == "ActorCondition" then
                    local cond = (tag.var or tag.varList) and ": " .. (tag.neg and "Not " or "") .. fmt:FormatVarNameOrList(tag.var, tag.varList) or ""
                    desc = (tag.actor and (tag.actor:sub(1, 1):upper() .. tag.actor:sub(2) .. " ") or "") .. "Condition" .. cond
                elseif tag.type == "Multiplier" then
                    local base = tag.base and (fmt:FormatModBase(row.mod, tag.base) .. " + " .. math.abs(row.mod.value) .. " ") or baseVal or ""
                    desc = base .. "per " .. (tag.div and (tag.div .. " ") or "") .. fmt:FormatVarNameOrList(tag.var, tag.varList)
                    baseVal = ""
                elseif tag.type == "PerStat" then
                    local base = tag.base and (fmt:FormatModBase(row.mod, tag.base) .. " + " .. math.abs(row.mod.value) .. " ") or baseVal or ""
                    desc = base .. "per " .. (tag.div or 1) .. " " .. (tag.actor and (tag.actor .. " ") or "") .. fmt:FormatVarNameOrList(tag.stat, tag.statList)
                    baseVal = ""
                elseif tag.type == "PercentStat" then
                    local finalPercent = (row.mod.value * ((tag.percent or 1) / 100)) * 100
                    local base = tag.base and (fmt:FormatModBase(row.mod, tag.base) .. " + " .. math.abs(finalPercent) .. " ") or fmt:FormatModBase(row.mod, finalPercent)
                    desc = base .. "% of " .. (tag.actor and (tag.actor .. " ") or "") .. fmt:FormatVarNameOrList(tag.percentVar or tag.stat, tag.statList)
                    baseVal = ""
                elseif tag.type == "MultiplierThreshold" or tag.type == "StatThreshold" then
                    desc = "If " .. fmt:FormatVarNameOrList(tag.var or tag.stat, tag.varList or tag.statList) .. (tag.upper and " <= " or " >= ") .. (tag.thresholdPercent and tag.thresholdPercent .. "% " or "") .. (tag.threshold or fmt:FormatModName(tag.thresholdVar or tag.thresholdStat))
                elseif tag.type == "SkillName" then
                    desc = "Skill: " .. (tag.skillNameList and table.concat(tag.skillNameList, " / ") or tag.skillName)
                elseif tag.type == "SkillId" then
                    local skill = build.data.skills[tag.skillId]
                    desc = "Skill: " .. (skill and skill.name or tostring(tag.skillId))
                elseif tag.type == "SkillType" then
                    for name, st in pairs(SkillType) do
                        if st == tag.skillType then
                            desc = "Skill type: " .. (tag.neg and "Not " or "") .. fmt:FormatModName(name)
                            break
                        end
                    end
                    if not desc then
                        desc = "Skill type: " .. (tag.neg and "Not " or "") .. "?"
                    end
                elseif tag.type == "BaseFlag" then
                    desc = "Base flag: " .. (tag.neg and "Not " or "") .. fmt:FormatModName(tostring(tag.baseFlag))
                elseif tag.type == "SlotNumber" then
                    desc = "When in slot #" .. tag.num
                elseif tag.type == "GlobalEffect" then
                    desc = fmt:FormatModName(tag.effectType)
                elseif tag.type == "Limit" then
                    desc = "Limited to " .. (tag.limitVar and fmt:FormatModName(tag.limitVar) or fmt:FormatModBase(row.mod, tag.limit))
                elseif tag.type == "MonsterTag" then
                    desc = "Monster Tag: " .. (tag.monsterTagList and table.concat(tag.monsterTagList, "/") or tag.monsterTag)
                else
                    desc = fmt:FormatModName(tag.type)
                end
                if desc then
                    tags = (tags and tags .. ", " or "") .. desc
                end
            end
            p.tags = tags
        end
        -- FormatModName returns (string, count): keep the string only.
        if p.name then p.name = tostring((p.name)) end
        t_insert(plainRows, p)
    end

    t_insert(out, tableSection(sectionData.label, nil, plainRows, colList, function(row, col)
        if col.key == "source" and row._sourceTotals then
            local lines = { "^7Total from " .. row.source .. ":" }
            for _, l in ipairs(row._sourceTotals) do t_insert(lines, "^7" .. l) end
            return { kind = "lines", lines = lines }
        elseif col.key == "sourceName" and row._itemId then
            return { kind = "item", itemId = row._itemId, slot = row._itemSlot or "" }
        elseif col.key == "sourceName" and row._nodeId then
            return { kind = "node", nodeId = row._nodeId }
        end
    end))
end

-- Port of AddBreakdownSection (CalcBreakdownControl.lua:147) to data.
local function addBreakdownSection(out, fmt, build, actor, sectionData)
    local breakdown
    local ns, name = sectionData.breakdown:match("^(%a+)%.(%a+)$")
    if ns then
        breakdown = actor.breakdown and actor.breakdown[ns] and actor.breakdown[ns][name]
    else
        breakdown = actor.breakdown and actor.breakdown[sectionData.breakdown]
    end
    if not breakdown then return end

    if #breakdown > 0 then
        local lines = { }
        for _, line in ipairs(breakdown) do
            t_insert(lines, numSep(tostring(line)))
        end
        t_insert(out, { type = "TEXT", textSize = 16, lines = lines })
    end

    if breakdown.radius then
        t_insert(out, {
            type = "RADIUS",
            radius = breakdown.radius,
            width = 8 + 1920 / 4,
            height = 4 + 1080 / 4,
            guide = (_SRC_DIR or ".") .. "/Assets/range_guide.png",
            overlay = (_SRC_DIR or ".") .. "/Assets/game_ui_small.png",
            polygon = M.radiusPolygon(breakdown.radius, 480, 270),
        })
    end

    if breakdown.rowList and #breakdown.rowList > 0 then
        local rowList = copyTable(breakdown.rowList, true)
        local colKey = breakdown.colList[1].key
        if breakdown.source then
            pcall(table.sort, rowList, function(a, b)
                if a.reqNum then return a.reqNum > b.reqNum end
                return a[colKey] > b[colKey]
            end)
        end
        t_insert(out, tableSection(breakdown.label, breakdown.footer, rowList, breakdown.colList))
    end

    if breakdown.reservations and #breakdown.reservations > 0 then
        t_insert(out, tableSection(nil, nil, breakdown.reservations, {
            { label = "Skill", key = "skillName" },
            { label = "Base", key = "base" },
            { label = "MCM", key = "mult" },
            { label = "More/less", key = "more" },
            { label = "Inc/red", key = "inc" },
            { label = "Efficiency", key = "efficiency" },
            { label = "Efficiency More/less", key = "efficiencyMore" },
            { label = "Reservation", key = "total" },
        }))
    end

    if breakdown.damageTypes and #breakdown.damageTypes > 0 then
        t_insert(out, tableSection(nil, nil, breakdown.damageTypes, {
            { label = "From", key = "source", right = true },
            { label = "Base", key = "base" },
            { label = "Inc/red", key = "inc" },
            { label = "More/less", key = "more" },
            { label = "Converted Damage", key = "convSrc" },
            { label = "Total", key = "total" },
            { label = "Conversion", key = "convDst" },
            { label = "Gain", key = "gainDst" },
        }))
    end

    if breakdown.slots and #breakdown.slots > 0 then
        local colList, rowList = nil, { }
        if sectionData.gearOnly then
            colList = {
                { label = "Value", key = "base", right = true },
                { label = "Source", key = "source" },
                { label = "Name", key = "sourceLabel" },
            }
            for _, row in ipairs(breakdown.slots) do
                if row.item and row.item.armourData and (row.base or 0) > 0 then
                    t_insert(rowList, row)
                end
            end
        else
            colList = {
                { label = "Base", key = "base", right = true },
                { label = "Inc/red", key = "inc" },
                { label = "More/less", key = "more" },
                { label = "Total", key = "total", right = true },
                { label = "Source", key = "source" },
                { label = "Name", key = "sourceLabel" },
            }
            for _, row in ipairs(breakdown.slots) do t_insert(rowList, row) end
        end
        if #rowList > 0 then
            pcall(table.sort, rowList, function(a, b) return (a.base or 0) > (b.base or 0) end)
            -- Plain copies: legacy writes sourceLabel/closures onto the LIVE
            -- rows; the port never mutates breakdown data.
            local plain = { }
            for _, row in ipairs(rowList) do
                local p = {
                    base = row.base, inc = row.inc, more = row.more, total = row.total,
                    source = row.source,
                }
                if row.item then
                    p.sourceLabel = (colorCodes[row.item.rarity] or "") .. (row.item.name or "")
                    p._itemId = row.item.id
                    p._itemSlot = row.source
                else
                    p.sourceLabel = row.sourceName
                end
                t_insert(plain, p)
            end
            t_insert(out, tableSection(nil, nil, plain, colList, function(row, col)
                if col.key == "sourceLabel" and row._itemId then
                    return { kind = "item", itemId = row._itemId, slot = row._itemSlot or "" }
                end
            end))
        end
    end

    if breakdown.modList and #breakdown.modList > 0 then
        addModSection(out, fmt, build, actor, sectionData, breakdown.modList)
    end
end

-- SetBreakdownData (CalcBreakdownControl.lua:60) as data: every entry of the
-- cell's colData that passes CheckFlag contributes its sections.
function M.serializeBreakdown(build, fmt, colData, actor, player)
    local sections = { }
    for _, sectionData in ipairs(colData) do
        if type(sectionData) == "table" and M.checkFlag(sectionData, actor, player) then
            if sectionData.breakdown then
                addBreakdownSection(sections, fmt, build, actor, sectionData)
            elseif sectionData.modName then
                addModSection(sections, fmt, build, actor, sectionData)
            end
        end
    end
    return sections
end

-- Click/hover-time breakdown for one grid cell ("si:ui:ri:ci").
function pob_calcsGetBreakdown(key)
    local bm, ct = ctx()
    if not ct then return { ok = false, error = "no calcsTab" } end
    if not ensureOutput(bm, ct) then return { ok = false, error = "no calcs output" } end
    local colData, rowData = cellData(ct, key)
    if not colData or not colData.format then return { ok = false, error = "no such cell" } end
    local actor, env = M.calcsActor(ct)
    local fmt = ct.controls and ct.controls.breakdown
    if not fmt then return { ok = false, error = "no breakdown formatter" } end
    local ok, sections = pcall(M.serializeBreakdown, bm, fmt, colData, actor, env.player)
    if not ok then return { ok = false, error = tostring(sections) } end
    return {
        ok = true,
        key = key,
        label = rowData and rowData.label or "",
        sections = sections,
        count = #sections,
        outputRevision = bm.outputRevision or 0,
    }
end

-- Item tooltip for a breakdown row (AddItemTooltip via the Items bridge).
function pob_calcsItemTooltip(itemId, slotName)
    local id = tonumber(itemId)
    if not id then return { lines = { }, children = { } } end
    if type(slotName) == "string" and slotName ~= "" and pob_itemsSlotTooltip then
        local t = pob_itemsSlotTooltip(slotName, id, false)
        if t and t.lines and #t.lines > 0 then return t end
    end
    if pob_itemsTooltip then
        return pob_itemsTooltip("item", id, false)
    end
    return { lines = { }, children = { } }
end

---------------------------------------------------------------------------
-- Selftests
---------------------------------------------------------------------------

local function findCell(grid, pred)
    for _, s in ipairs(grid.sections) do
        for _, sub in ipairs(s.subs) do
            for _, row in ipairs(sub.rows) do
                for _, cell in ipairs(row.cells) do
                    if pred(s, sub, row, cell) then return cell, row, sub, s end
                end
            end
        end
    end
end

-- Walk a value and fail on anything that is not plain data.
local function isPlain(v, depth)
    depth = depth or 0
    if depth > 12 then return false end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" or t == "nil" then return true end
    if t ~= "table" or getmetatable(v) ~= nil then return false end
    for k, x in pairs(v) do
        if type(k) ~= "string" and type(k) ~= "number" then return false end
        if not isPlain(x, depth + 1) then return false end
    end
    return true
end

-- Two Fireball socket groups (added when absent) so the Calcs selection can
-- diverge from the side bar's. Returns ids to remove afterwards.
local function fixtureGroups(bm)
    local added = { }
    while #bm.skillsTab.socketGroupList < 2 do
        local id = pob_addSocketGroupWithGem("Selftest Calcs " .. (#added + 1), "Fireball")
        if not id then break end
        t_insert(added, id)
    end
    bm.buildFlag = true
    pob_recalculate()
    return added
end

local function removeGroups(bm, added)
    for i = #added, 1, -1 do
        local id = added[i]
        if bm.skillsTab.socketGroupList[id] then
            table.remove(bm.skillsTab.socketGroupList, id)
        end
    end
    if bm.skillsTab.socketGroupList and #added > 0 then
        bm.mainSocketGroup = m_min(bm.mainSocketGroup or 1, m_max(#bm.skillsTab.socketGroupList, 1))
        bm.buildFlag = true
        pob_recalculate()
    end
end

function pob_selftestCalcsGrid()
    local bm, ct = ctx()
    if not ct then return { ok = false, error = "no calcsTab" } end
    local res = { }
    local added = { }
    local savedInput = copyTable(ct.input)
    local savedMain = bm.mainSocketGroup
    local ok, err = pcall(function()
        added = fixtureGroups(bm)
        local grid = pob_calcsGetGrid()
        if not grid then error("no grid") end
        res.sections = #grid.sections
        if #grid.sections < 20 then error("too few sections: " .. #grid.sections) end
        if grid.sections[1].id ~= "SkillSelect" or not grid.sections[1].special then
            error("first section is not SkillSelect")
        end
        if not isPlain(grid) then error("grid payload not plain data") end

        -- Offence (group 1) + defence (groups 2/3) present and enabled.
        local groups = { }
        for _, s in ipairs(grid.sections) do
            if s.enabled then groups[s.group] = (groups[s.group] or 0) + 1 end
        end
        if not (groups[1] and groups[2] and groups[3]) then error("missing offence/defence groups") end

        -- Cell resolution: the Life cell equals formatCalcStr on the actor.
        local actor = ct.calcsEnv.player
        local lifeCell = findCell(grid, function(s, sub, row) return s.id == "Life" and row.label == "Total" end)
        if not lifeCell then error("Life/Total cell missing") end
        local colData = cellData(ct, lifeCell.key)
        local expect = "^7" .. formatCalcStr(colData.format, actor, colData)
        if lifeCell.text ~= expect then error("Life cell '" .. lifeCell.text .. "' ~= '" .. expect .. "'") end
        local lifeVal = tostring(round(actor.output.Life or 0))
        if not lifeCell.text:gsub(",", ""):find(lifeVal, 1, true) then
            error("Life cell lacks output.Life " .. lifeVal)
        end
        res.lifeCell = lifeCell.text

        -- {N:mod:i,j} resolves through live Combine (not "?").
        local modCell = findCell(grid, function(s, sub, row, cell)
            local cd = cellData(ct, cell.key)
            return cd and cd.format and cd.format:find(":mod:", 1, true) ~= nil and cell.text ~= ""
        end)
        if not modCell then error("no {N:mod:} cell resolved") end
        if modCell.text:find("?", 1, true) then error("mod cell unresolved: " .. modCell.text) end
        res.modCell = modCell.text

        -- Gating: a haveOutput row with zero output is hidden; flag gates.
        local gated = 0
        for si, section in ipairs(ct.sectionList) do
            for ui, subSec in ipairs(section.subSection) do
                for ri, rowData in ipairs(subSec.data) do
                    if rowData.haveOutput and not M.checkFlag(rowData, actor, actor) then
                        gated = gated + 1
                        local hit = findCell(grid, function(s, sub, row)
                            return s.index == si and sub.index == ui and row.index == ri
                        end)
                        if hit then error("haveOutput-gated row rendered: " .. tostring(rowData.label)) end
                    end
                end
            end
        end
        if gated == 0 then error("no gated rows exercised") end
        res.gated = gated
        if M.checkFlag({ flag = "__nope__" }, actor, actor) then error("flag gate passed") end
        if M.checkFlag({ notFlag = "spell" }, actor, actor) ~= not actor.mainSkill.skillFlags.spell then
            error("notFlag gate wrong")
        end

        -- Independent *Calcs selection: skill_number moves, sidebar doesn't.
        bm.mainSocketGroup = 1
        local r = pob_calcsSetSkill("group", 2)
        if not r.ok then error("set group failed") end
        if ct.input.skill_number ~= 2 then error("skill_number not set") end
        if bm.mainSocketGroup ~= 1 then error("sidebar mainSocketGroup moved") end
        local sel = pob_calcsGetSkillSelect()
        if not sel or sel.mainSocketGroup ~= 2 then error("skill select payload not on group 2") end
        if bm.mainSocketGroup ~= 1 then error("skill select read leaked mainSocketGroup") end
        if ct.calcsEnv.mainSocketGroup ~= 2 then error("calcsEnv not on group 2") end

        -- Calculation Mode affects only calcsEnv.
        local mainLife = ct.mainOutput.Life
        pob_calcsSetInput("misc_buffMode", "UNBUFFED")
        if ct.calcsEnv.mode_buffs then error("UNBUFFED left mode_buffs on") end
        if not ct.mainEnv.mode_effective then error("mainEnv left EFFECTIVE") end
        pob_calcsSetInput("misc_buffMode", "EFFECTIVE")
        if not ct.calcsEnv.mode_effective then error("EFFECTIVE not applied") end
        if ct.mainOutput.Life ~= mainLife then error("sidebar output changed by calc mode") end
        if pob_calcsSetInput("misc_buffMode", "BOGUS").ok then error("bogus mode accepted") end

        -- Collapse: primary collapse shrinks the section to 22px.
        local si
        for i, s in ipairs(grid.sections) do if s.id == "Life" then si = i end end
        local t = pob_calcsToggleSubsection(si, 1)
        local g2 = pob_calcsGetGrid()
        if not t.ok or g2.sections[si].height ~= 22 or #g2.sections[si].subs ~= 1 or #g2.sections[si].subs[1].rows ~= 0 then
            error("collapse not reflected")
        end
        pob_calcsToggleSubsection(si, 1)
        if pob_calcsGetGrid().sections[si].height <= 22 then error("expand not reflected") end

        -- Search.
        local sr = pob_calcsSearch("life")
        if sr.count == 0 then error("search found nothing") end
        if pob_calcsSearch("[").count ~= 0 then error("bad pattern matched") end
        res.searchHits = sr.count

        -- Minion actor toggle: add Raise Zombie, select it, toggle showMinion.
        local minionGroup = pob_addSocketGroupWithGem("Selftest Minion", "Raise Zombie")
        if minionGroup then
            t_insert(added, minionGroup)
            pob_calcsSetSkill("group", minionGroup)
            if ct.calcsEnv.minion then
                local gPlayer = pob_calcsGetGrid()
                pob_calcsSetInput("showMinion", true)
                local gMinion = pob_calcsGetGrid()
                local pLife = findCell(gPlayer, function(s, sub, row) return s.id == "Life" and row.label == "Total" end)
                local mLife = findCell(gMinion, function(s, sub, row) return s.id == "Life" and row.label == "Total" end)
                if not pLife or not mLife or pLife.text == mLife.text then
                    error("showMinion did not switch actor stats")
                end
                res.minionSwitched = true
                pob_calcsSetInput("showMinion", false)
            end
        end
    end)
    -- Restore.
    for k in pairs(ct.input) do ct.input[k] = nil end
    for k, v in pairs(savedInput) do ct.input[k] = v end
    bm.mainSocketGroup = savedMain
    removeGroups(bm, added)
    bm.buildFlag = true
    pob_recalculate()
    res.ok = ok
    if not ok then res.error = tostring(err) end
    return res
end

-- Pick an allocatable Normal node granting an attribute, by shortest path.
local function attributeNode(spec)
    local best
    for _, node in pairs(spec.nodes) do
        if node.type == "Normal" and not node.alloc and node.path and #node.path > 0 and not node.ascendancyName then
            for _, sd in ipairs(node.sd or { }) do
                if sd:find("to Strength") or sd:find("to Dexterity") or sd:find("to Intelligence") or sd:find("to all Attributes") then
                    if not best or #node.path < #best.path then best = node end
                    break
                end
            end
        end
    end
    return best
end

function pob_selftestCalcsBreakdown()
    local bm, ct = ctx()
    if not ct then return { ok = false, error = "no calcsTab" } end
    local res = { }
    local addedGroups = { }
    local addedItems = { }
    local savedSlots = { }
    local savedInput = copyTable(ct.input)
    local allocated
    local it = bm.itemsTab

    local function equipFixture(slotName, raw)
        local item = new("Item"):Item(raw)
        if not item.base then error("fixture base missing for " .. slotName) end
        item:NormaliseQuality()
        it:AddItem(item, true)
        t_insert(addedItems, item.id)
        local slot = it.slots[slotName]
        if slot then
            if savedSlots[slotName] == nil then savedSlots[slotName] = slot.selItemId or 0 end
            slot:SetSelItemId(item.id)
        end
        return item
    end

    local ok, err = pcall(function()
        local fbGroup = pob_addSocketGroupWithGem("Selftest Calcs FB", "Fireball")
        t_insert(addedGroups, fbGroup)
        local clarityGroup = pob_addSocketGroupWithGem("Selftest Calcs Aura", "Clarity")
        t_insert(addedGroups, clarityGroup)
        local hsGroup = pob_addSocketGroupWithGem("Selftest Calcs Melee", "Heavy Strike")
        t_insert(addedGroups, hsGroup)

        -- Equip gear so Life (inc>0 -> TEXT), FireResist (mod table + Item source),
        -- Armour (slots table + item ref), and Weapon 1 (MainHand.* namespace) all populate.
        local ring = equipFixture("Ring 1",
            "Rarity: Rare\nCalcs Probe Ring\nGold Ring\n+40 to maximum Life\n10% increased maximum Life\n+30% to Fire Resistance\n")
        local armour = equipFixture("Body Armour",
            "Rarity: Rare\nCalcs Probe Armour\nPlate Vest\n+100 to Armour\n")
        equipFixture("Weapon 1",
            "Rarity: Rare\nCalcs Probe Sword\nRusted Sword\nAdds 5 to 10 Physical Damage\n")
        it:PopulateSlots()

        -- Tree-sourced mod: allocate an attribute node.
        local node = attributeNode(bm.spec)
        if not node then error("no attribute node") end
        local a = pob_allocNode(node.id)
        if not a or not a.ok then error("alloc failed") end
        allocated = node.id

        ct.input.skill_number = fbGroup
        ct.input.showMinion = false
        ct.input.misc_buffMode = "EFFECTIVE"
        bm.buildFlag = true
        pob_recalculate()

        local grid = pob_calcsGetGrid()
        -- 1. Life/Total: TEXT lines matching actor.breakdown.Life line-for-line.
        local lifeCell = findCell(grid, function(s, sub, row) return s.id == "Life" and row.label == "Total" end)
        if not lifeCell or not lifeCell.breakdown then error("Life/Total cell has no breakdown") end
        local bd = pob_calcsGetBreakdown(lifeCell.key)
        if not bd.ok then error("Life breakdown: " .. tostring(bd.error)) end
        if not isPlain(bd) then error("breakdown payload not plain data") end
        local text
        for _, s in ipairs(bd.sections) do
            if s.type == "TEXT" and #s.lines > 0 then text = s end
        end
        if not text then error("Life breakdown has no TEXT lines") end
        local live = ct.calcsEnv.player.breakdown.Life
        if not live or #text.lines ~= #live then
            error("TEXT line count " .. #text.lines .. " ~= " .. tostring(live and #live))
        end
        res.lifeLines = #text.lines

        -- 2. Life/Total Base: mod table via live Tabulate + per-source Combine + Item tooltip.
        local baseCell = findCell(grid, function(s, sub, row) return s.id == "Life" and row.label == "Total Base" end)
        if not baseCell or not baseCell.breakdown then error("Life/Total Base has no breakdown") end
        local baseBd = pob_calcsGetBreakdown(baseCell.key)
        local modTable
        for _, s in ipairs(baseBd.sections or { }) do
            if s.type == "TABLE" then
                for _, c in ipairs(s.cols) do if c.key == "source" then modTable = s end end
            end
        end
        if not modTable then error("Life/Total Base has no mod table") end
        local tab = ct.calcsEnv.player.modDB:Tabulate("BASE", { }, "Life")
        if #modTable.rows ~= #tab then error("mod rows " .. #modTable.rows .. " ~= Tabulate " .. #tab) end
        local hasTotals, foundItem = false, false
        for _, row in ipairs(modTable.rows) do
            for _, cell in ipairs(row.cells) do
                if cell.tip and cell.tip.kind == "lines" and #cell.tip.lines > 1 then hasTotals = true end
                if cell.tip and cell.tip.kind == "item" and cell.tip.itemId == ring.id then foundItem = true end
            end
        end
        if not hasTotals then error("no per-source totals tooltip") end
        if not foundItem then error("Item-sourced mod row for ring not found") end
        local itemTip = pob_calcsItemTooltip(ring.id, "Ring 1")
        if not itemTip or not itemTip.lines or #itemTip.lines == 0 then error("item tooltip empty") end
        res.lifeRows = #modTable.rows

        -- 3. Attributes: allocated node shows up as a Tree row with nodeId.
        local foundNode = false
        for _, label in ipairs({ "Strength", "Dexterity", "Intelligence" }) do
            local cell = findCell(grid, function(s, sub, row) return s.id == "Attributes" and row.label == label end)
            if cell then
                local b = pob_calcsGetBreakdown(cell.key)
                for _, s in ipairs(b.sections or { }) do
                    for _, row in ipairs(s.rows or { }) do
                        for _, c in ipairs(row.cells) do
                            if c.tip and c.tip.kind == "node" and c.tip.nodeId == node.id then foundNode = true end
                        end
                    end
                end
            end
        end
        if not foundNode then error("tree-sourced row for node " .. node.id .. " not found") end
        res.nodeId = node.id

        -- 4. Slots table (Armour/Total) with item reference -> itemId.
        local armourCell = findCell(grid, function(s, sub, row) return s.id == "Armour" and row.label == "Total" end)
        if not armourCell then error("Armour/Total cell missing") end
        local ab = pob_calcsGetBreakdown(armourCell.key)
        local foundArmourSlot = false
        for _, s in ipairs(ab.sections or { }) do
            if s.type == "TABLE" then
                for _, row in ipairs(s.rows or { }) do
                    for _, c in ipairs(row.cells) do
                        if c.tip and c.tip.kind == "item" and c.tip.itemId == armour.id then
                            foundArmourSlot = true
                        end
                    end
                end
            end
        end
        if not foundArmourSlot then error("Armour slots table missing equipped armour itemId") end
        res.armourSlotsOk = true

        -- 5. Reservations table (Mana/Reserved with Clarity active).
        local resCell = findCell(grid, function(s, sub, row) return s.id == "Mana" and row.label == "Reserved" end)
        if not resCell then error("Mana/Reserved cell missing") end
        local resBd = pob_calcsGetBreakdown(resCell.key)
        local hasResTable = false
        for _, s in ipairs(resBd.sections or { }) do
            if s.type == "TABLE" and s.cols[1] and s.cols[1].key == "skillName" and #s.rows > 0 then
                hasResTable = true
            end
        end
        if not hasResTable then error("Mana/Reserved breakdown missing reservations table") end
        res.reservationsOk = true

        -- 6. DamageTypes table (Fireball Skill Hit Damage -> Fire column).
        local hitCell = findCell(grid, function(s, sub, row, cell)
            return s.id == "HitDamage" and row.label == "Skill Hit Damage" and cell.breakdown and cell.key:match(":5$") ~= nil
        end)
        if not hitCell then error("Skill Hit Damage Fire cell missing for Fireball") end
        local hitBd = pob_calcsGetBreakdown(hitCell.key)
        local hasDmgTypes = false
        for _, s in ipairs(hitBd.sections or { }) do
            if s.type == "TABLE" and s.cols[1] and s.cols[1].key == "source" and #s.rows > 0 then
                hasDmgTypes = true
            end
        end
        if not hasDmgTypes then error("Skill Hit Damage Fire breakdown missing damageTypes table") end
        res.damageTypesOk = true

        -- 7. Radius visualiser on an AoE stat (Fireball explosion).
        local radCell = findCell(grid, function(s, sub, row) return row.label == "Radius" end)
        if not radCell then error("no Radius cell for Fireball") end
        local rb = pob_calcsGetBreakdown(radCell.key)
        local rad
        for _, s in ipairs(rb.sections or { }) do if s.type == "RADIUS" then rad = s end end
        if not rad then error("Radius breakdown has no RADIUS section") end
        if rad.radius ~= ct.calcsEnv.player.breakdown.AreaOfEffectRadius.radius then error("radius mismatch") end
        if #rad.polygon < 20 then error("radius polygon empty") end
        res.radius = rad.radius

        -- 8. Namespaced breakdown lookup (MainHand.AverageHit with Heavy Strike).
        pob_calcsSetSkill("group", hsGroup)
        local hsGrid = pob_calcsGetGrid()
        local mhCell = findCell(hsGrid, function(s, sub, row) return s.id == "HitDamage" and row.label == "MH Average Hit" end)
        if not mhCell then error("MH Average Hit cell missing for Heavy Strike") end
        local mhBd = pob_calcsGetBreakdown(mhCell.key)
        if not mhBd.ok or mhBd.count == 0 then error("MainHand.AverageHit namespaced breakdown empty") end
        res.namespacedOk = true

        -- 9. Bad key rejected cleanly.
        if pob_calcsGetBreakdown("999:1:1:1").ok then error("bad key accepted") end
    end)
    if allocated then pcall(pob_deallocNode, allocated) end
    for slotName, oldId in pairs(savedSlots) do
        if it.slots[slotName] then it.slots[slotName]:SetSelItemId(oldId) end
    end
    for i = #addedItems, 1, -1 do
        pcall(pob_deleteItem, addedItems[i])
    end
    it:PopulateSlots()
    for k in pairs(ct.input) do ct.input[k] = nil end
    for k, v in pairs(savedInput) do ct.input[k] = v end
    removeGroups(bm, addedGroups)
    bm.buildFlag = true
    pob_recalculate()
    res.ok = ok
    if not ok then res.error = tostring(err) end
    return res
end

-- <Calcs> round trip: inputs (misc_buffMode, showMinion, skill_number) and a
-- subsection collapse survive SaveDB -> XML -> LoadDB.
function pob_selftestCalcsPersist()
    local bm, ct = ctx()
    if not ct then return { ok = false, error = "no calcsTab" } end
    local res = { }
    local ok, err = pcall(function()
        ct.input.misc_buffMode = "BUFFED"
        ct.input.showMinion = true
        -- Collapse a default-expanded subsection; expand a default-collapsed one.
        local collapseSec, expandSec
        for _, section in ipairs(ct.sectionList) do
            if section.id == "Life" then collapseSec = section end
            if section.id == "Rage" then expandSec = section end
        end
        if not collapseSec or not expandSec then error("fixture sections missing") end
        collapseSec.subSection[1].collapsed = true
        expandSec.subSection[1].collapsed = false
        local xmlText = bm:SaveDB(nil)
        if not xmlText then error("SaveDB nil") end
        res.hasBuffMode = xmlText:find('<Input name="misc_buffMode" string="BUFFED"/>', 1, true) ~= nil
        res.hasCollapse = xmlText:find('<Section collapsed="true" id="Life" subsection="Life"/>', 1, true) ~= nil
            or (xmlText:find('id="Life"', 1, true) ~= nil and xmlText:find('collapsed="true"', 1, true) ~= nil)
        if not res.hasBuffMode then error("XML lacks misc_buffMode input") end
        if not res.hasCollapse then error("XML lacks Life collapse") end

        pob_loadBuildXML(xmlText, "Calcs Persist Probe")
        local bm2, ct2 = ctx()
        if not ct2 then error("no calcsTab after load") end
        if ct2 == ct then error("calcsTab not rebuilt by load") end
        if ct2.input.misc_buffMode ~= "BUFFED" then error("buffMode lost: " .. tostring(ct2.input.misc_buffMode)) end
        if ct2.input.showMinion ~= true then error("showMinion lost") end
        local life, rage
        for _, section in ipairs(ct2.sectionList) do
            if section.id == "Life" then life = section end
            if section.id == "Rage" then rage = section end
        end
        if not life.subSection[1].collapsed then error("Life collapse lost") end
        if rage.subSection[1].collapsed then error("Rage expand lost") end
        -- And the grid reflects the loaded collapse.
        local grid = pob_calcsGetGrid()
        for _, s in ipairs(grid.sections) do
            if s.id == "Life" and s.enabled and s.height ~= 22 then error("loaded collapse not in grid") end
        end
    end)
    -- Clean slate (same discipline as pob_selftestSaveLoadRoundTrip).
    main:SetMode("BUILD", false, "Unnamed build")
    runCallback("OnFrame")
    res.ok = ok
    if not ok then res.error = tostring(err) end
    return res
end
