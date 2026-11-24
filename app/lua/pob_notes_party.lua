-- Path of Building (Qt port)
--
-- Module: pob_notes_party.lua  —  Notes & Party tabs bridge
-- Phase 9 (Notes & Party Tabs).
--
-- NotesTab (src/Classes/NotesTab.lua):
--   Rich text editor with 12 color-code insert buttons, Show/Hide Color Codes
--   toggle, <Notes> XML + modFlag.
-- PartyTab (src/Classes/PartyTab.lua):
--   Offline code/URL validation & import, destination selector, Append/Clear,
--   Show Advanced Info, Disable Party Effects, Rebuild All, 7 data buffers +
--   summary labels, ParseBuffs -> ModLists, <Party> XML + modFlag.
--
-- All functions return plain Lua tables/primitives (never calc-touched objects)
-- with `_emit` signals so LuaEngine::invoke notifies QML controllers/views.

local t_insert = table.insert
local s_format = string.format

local EMIT_NOTES = { "build", "notes" }
local EMIT_PARTY = { "build", "party" }
local EMIT_PARTY_CALCS = { "build", "party", "calcs" }

local function notesCtx()
    local bm = main and main.modes and main.modes.BUILD
    return bm, bm and bm.notesTab
end

local function partyCtx()
    local bm = main and main.modes and main.modes.BUILD
    return bm, bm and bm.partyTab
end

local function fail(msg)
    return { ok = false, error = msg }
end

local function escapeColorCodes(s)
    return (s or ""):gsub("%^x(%x%x%x%x%x%x)", "^_x%1"):gsub("%^(%d)", "^_%1")
end

local function unescapeColorCodes(s)
    return (s or ""):gsub("%^_x(%x%x%x%x%x%x)", "^x%1"):gsub("%^_(%d)", "^%1")
end

-- ============================================================================
-- NOTES TAB BRIDGE
-- ============================================================================

local NOTES_COLOR_BUTTONS = {
    { key = "NORMAL",       label = "NORMAL",       code = function() return colorCodes.NORMAL or "^xC8C8C8" end },
    { key = "MAGIC",        label = "MAGIC",        code = function() return colorCodes.MAGIC or "^x8888FF" end },
    { key = "RARE",         label = "RARE",         code = function() return colorCodes.RARE or "^xFFFF77" end },
    { key = "UNIQUE",       label = "UNIQUE",       code = function() return colorCodes.UNIQUE or "^xAF6025" end },
    { key = "FIRE",         label = "FIRE",         code = function() return colorCodes.FIRE or "^xB97123" end },
    { key = "COLD",         label = "COLD",         code = function() return colorCodes.COLD or "^x3F6DB3" end },
    { key = "LIGHTNING",    label = "LIGHTNING",    code = function() return colorCodes.LIGHTNING or "^xADAA47" end },
    { key = "CHAOS",        label = "CHAOS",        code = function() return colorCodes.CHAOS or "^xD02090" end },
    { key = "STRENGTH",     label = "STRENGTH",     code = function() return colorCodes.STRENGTH or "^xD20000" end },
    { key = "DEXTERITY",    label = "DEXTERITY",    code = function() return colorCodes.DEXTERITY or "^x46A200" end },
    { key = "INTELLIGENCE", label = "INTELLIGENCE", code = function() return colorCodes.INTELLIGENCE or "^x6699FF" end },
    { key = "DEFAULT",      label = "DEFAULT",      code = function() return "^7" end },
}

local function buildNotesState(bm, nt)
    local colors = {}
    for _, btn in ipairs(NOTES_COLOR_BUTTONS) do
        local c = btn.code()
        colors[#colors + 1] = {
            key = btn.key,
            label = btn.label,
            code = c,
            escapedCode = escapeColorCodes(c),
        }
    end
    local buf = (nt.controls and nt.controls.edit and nt.controls.edit.buf) or ""
    nt.modFlag = ((nt.lastContent or "") ~= buf)
    return {
        ok = true,
        text = buf,
        showColorCodes = nt.showColorCodes == true,
        modFlag = nt.modFlag == true,
        colors = colors,
    }
end

function pob_notesGetState()
    local bm, nt = notesCtx()
    if not bm or not nt or not nt.controls or not nt.controls.edit then
        return fail("notesTab unavailable")
    end
    return buildNotesState(bm, nt)
end

function pob_notesSetText(text)
    local bm, nt = notesCtx()
    if not bm or not nt or not nt.controls or not nt.controls.edit then
        return fail("notesTab unavailable")
    end
    local t = text or ""
    nt.controls.edit.buf = t
    bm.notes = nt.showColorCodes and unescapeColorCodes(t) or t
    nt.modFlag = ((nt.lastContent or "") ~= nt.controls.edit.buf)
    local st = buildNotesState(bm, nt)
    st._emit = EMIT_NOTES
    return st
end

function pob_notesToggleColorCodes()
    local bm, nt = notesCtx()
    if not bm or not nt or not nt.controls or not nt.controls.edit then
        return fail("notesTab unavailable")
    end
    nt:SetShowColorCodes(not nt.showColorCodes)
    bm.notes = nt.showColorCodes and unescapeColorCodes(nt.controls.edit.buf) or nt.controls.edit.buf
    nt.modFlag = ((nt.lastContent or "") ~= nt.controls.edit.buf)
    local st = buildNotesState(bm, nt)
    st._emit = EMIT_NOTES
    return st
end

function pob_notesSetShowColorCodes(setting)
    local bm, nt = notesCtx()
    if not bm or not nt or not nt.controls or not nt.controls.edit then
        return fail("notesTab unavailable")
    end
    nt:SetShowColorCodes(setting == true)
    bm.notes = nt.showColorCodes and unescapeColorCodes(nt.controls.edit.buf) or nt.controls.edit.buf
    nt.modFlag = ((nt.lastContent or "") ~= nt.controls.edit.buf)
    local st = buildNotesState(bm, nt)
    st._emit = EMIT_NOTES
    return st
end

-- Helper mirroring NotesTab:SetColor (NotesTab.lua:64-73) for a selection string.
-- Returns the replacement string for `selText` (or the code to insert if empty).
function pob_notesWrapSelection(selText, colorCode)
    local _, nt = notesCtx()
    local showCodes = nt and nt.showColorCodes == true
    local text = colorCode or "^7"
    if showCodes then
        text = escapeColorCodes(text)
    end
    local sel = selText or ""
    if sel == "" then
        return text
    end
    local patLast = showCodes and "^.*(%^_x%x%x%x%x%x%x)" or "^.*(%^x%x%x%x%x%x)"
    local patStrip = showCodes and "%^_x%x%x%x%x%x%x" or "%^x%x%x%x%x%x"
    local lastColor = sel:match(patLast) or (showCodes and "^_7" or "^7")
    return text .. sel:gsub(patStrip, "") .. lastColor
end

-- ============================================================================
-- PARTY TAB BRIDGE
-- ============================================================================

local PARTY_DESTINATIONS = {
    "All",
    "Party Member Stats",
    "Aura",
    "Curse",
    "Warcry Skills",
    "Link Skills",
    "EnemyConditions",
    "EnemyMods",
}

local function updatePartyModFlag(pt)
    if not pt or not pt.controls or not pt.lastContent then return end
    local c = pt.controls
    pt.modFlag = (pt.lastContent.Aura ~= c.editAuras.buf
        or pt.lastContent.Curse ~= c.editCurses.buf
        or pt.lastContent.Warcry ~= c.editWarcries.buf
        or pt.lastContent.Link ~= c.editLinks.buf
        or pt.lastContent.PartyMemberStats ~= c.editPartyMemberStats.buf
        or pt.lastContent.EnemyCond ~= c.enemyCond.buf
        or pt.lastContent.EnemyMods ~= c.enemyMods.buf
        or pt.lastContent.EnableExportBuffs ~= pt.enableExportBuffs
        or pt.lastContent.showAdvancedTools ~= c.ShowAdvanceTools.state)
end

local function hasActivePartyEffects(pt)
    if not pt then return false end
    if pt.actor then
        for _, cat in ipairs({ "Aura", "Curse", "Warcry", "Link" }) do
            if pt.actor[cat] and next(pt.actor[cat]) ~= nil then
                return true
            end
        end
        if pt.actor.output and next(pt.actor.output) ~= nil then
            return true
        end
        if pt.actor.modDB and pt.actor.modDB.mods and next(pt.actor.modDB.mods) ~= nil then
            return true
        end
    end
    if pt.enemyModList and #pt.enemyModList > 0 then
        return true
    end
    return false
end

local function buildPartyState(pt)
    local c = pt.controls
    updatePartyModFlag(pt)
    return {
        ok = true,
        importCode = c.importCodeIn.buf or "",
        importDetail = pt.importCodeDetail or "",
        importValid = pt.importCodeValid == true,
        importIsUrl = pt.importCodeSite ~= nil,
        destinations = PARTY_DESTINATIONS,
        destinationIndex = c.importCodeDestination.selIndex or 1,
        append = c.appendNotReplace.state == true,
        showAdvanced = c.ShowAdvanceTools.state == true,
        modFlag = pt.modFlag == true,
        effectsActive = hasActivePartyEffects(pt),
        buffers = {
            auras = c.editAuras.buf or "",
            simpleAuras = c.simpleAuras.label or "",
            warcries = c.editWarcries.buf or "",
            simpleWarcries = c.simpleWarcries.label or "",
            links = c.editLinks.buf or "",
            simpleLinks = c.simpleLinks.label or "",
            partyStats = c.editPartyMemberStats.buf or "",
            enemyCond = c.enemyCond.buf or "",
            simpleEnemyCond = c.simpleEnemyCond.label or "",
            enemyMods = c.enemyMods.buf or "",
            simpleEnemyMods = c.simpleEnemyMods.label or "",
            curses = c.editCurses.buf or "",
            simpleCurses = c.simpleCurses.label or "",
        },
    }
end

function pob_partyGetState()
    local _, pt = partyCtx()
    if not pt or not pt.controls then
        return fail("partyTab unavailable")
    end
    return buildPartyState(pt)
end

function pob_partySetImportCode(code)
    local _, pt = partyCtx()
    if not pt or not pt.controls or not pt.controls.importCodeIn then
        return fail("partyTab unavailable")
    end
    pt.controls.importCodeIn:SetText(code or "", true)
    local st = buildPartyState(pt)
    st._emit = EMIT_PARTY
    return st
end

function pob_partySetDestination(index)
    local _, pt = partyCtx()
    if not pt or not pt.controls or not pt.controls.importCodeDestination then
        return fail("partyTab unavailable")
    end
    local idx = tonumber(index) or 1
    if idx < 1 then idx = 1 end
    if idx > #PARTY_DESTINATIONS then idx = #PARTY_DESTINATIONS end
    pt.controls.importCodeDestination.selIndex = idx
    local st = buildPartyState(pt)
    st._emit = EMIT_PARTY
    return st
end

function pob_partySetAppend(state)
    local _, pt = partyCtx()
    if not pt or not pt.controls or not pt.controls.appendNotReplace then
        return fail("partyTab unavailable")
    end
    pt.controls.appendNotReplace.state = (state == true)
    local st = buildPartyState(pt)
    st._emit = EMIT_PARTY
    return st
end

function pob_partySetShowAdvanced(state)
    local _, pt = partyCtx()
    if not pt or not pt.controls or not pt.controls.ShowAdvanceTools then
        return fail("partyTab unavailable")
    end
    pt.controls.ShowAdvanceTools.state = (state == true)
    updatePartyModFlag(pt)
    local st = buildPartyState(pt)
    st._emit = EMIT_PARTY
    return st
end

function pob_partyImport()
    local bm, pt = partyCtx()
    if not bm or not pt or not pt.controls or not pt.controls.importCodeGo then
        return fail("partyTab unavailable")
    end
    if not pt.importCodeValid then
        return fail("Invalid or empty import code")
    end
    if pt.importCodeSite and not pt.importCodeXML then
        return fail("URL fetch requires Phase 10 network; paste a build export code instead")
    end
    pt.controls.importCodeGo.onClick()
    pob_recalculate()
    updatePartyModFlag(pt)
    local st = buildPartyState(pt)
    st._emit = EMIT_PARTY_CALCS
    return st
end

function pob_partyClear()
    local bm, pt = partyCtx()
    if not bm or not pt or not pt.controls or not pt.controls.clear then
        return fail("partyTab unavailable")
    end
    pt.controls.clear.onClick()
    pob_recalculate()
    updatePartyModFlag(pt)
    local st = buildPartyState(pt)
    st._emit = EMIT_PARTY_CALCS
    return st
end

function pob_partyDisableEffects()
    local bm, pt = partyCtx()
    if not bm or not pt or not pt.controls or not pt.controls.removeEffects then
        return fail("partyTab unavailable")
    end
    pt.controls.removeEffects.onClick()
    pob_recalculate()
    updatePartyModFlag(pt)
    local st = buildPartyState(pt)
    st._emit = EMIT_PARTY_CALCS
    return st
end

function pob_partyRebuildAll()
    local bm, pt = partyCtx()
    if not bm or not pt or not pt.controls or not pt.controls.rebuild then
        return fail("partyTab unavailable")
    end
    pt.controls.rebuild.onClick()
    pob_recalculate()
    updatePartyModFlag(pt)
    local st = buildPartyState(pt)
    st._emit = EMIT_PARTY_CALCS
    return st
end

local BUFFER_CONTROL_MAP = {
    auras = "editAuras",
    warcries = "editWarcries",
    links = "editLinks",
    partyStats = "editPartyMemberStats",
    enemyCond = "enemyCond",
    enemyMods = "enemyMods",
    curses = "editCurses",
}

function pob_partySetBuffer(key, text)
    local _, pt = partyCtx()
    if not pt or not pt.controls then
        return fail("partyTab unavailable")
    end
    local ctrlName = BUFFER_CONTROL_MAP[key]
    if not ctrlName or not pt.controls[ctrlName] then
        return fail("Unknown party buffer key: " .. tostring(key))
    end
    pt.controls[ctrlName]:SetText(text or "")
    updatePartyModFlag(pt)
    local st = buildPartyState(pt)
    st._emit = EMIT_PARTY
    return st
end

-- ============================================================================
-- SELFTESTS (Phase 9)
-- ============================================================================

function pob_selftestNotes()
    local bm, nt = notesCtx()
    if not bm or not nt or not nt.controls or not nt.controls.edit then
        return fail("notesTab unavailable")
    end

    -- Snapshot original state
    local origBuf = nt.controls.edit.buf or ""
    local origShow = nt.showColorCodes == true
    local origLast = nt.lastContent or ""
    local origMod = nt.modFlag == true

    local function restore()
        nt.showColorCodes = origShow
        nt.controls.edit.buf = origBuf
        bm.notes = origShow and unescapeColorCodes(origBuf) or origBuf
        nt.lastContent = origLast
        nt.modFlag = origMod
    end

    local ok, err = pcall(function()
        local st0 = pob_notesGetState()
        assert(st0.ok and type(st0.colors) == "table" and #st0.colors == 12,
            "expected 12 color buttons, got " .. tostring(st0.colors and #st0.colors))

        local sample = "Test ^xB97123Fire^7 Note"
        local st1 = pob_notesSetText(sample)
        assert(st1.ok and pob_getNotes() == sample, "notes text mismatch after setText")
        assert(nt.modFlag == (origLast ~= sample), "notes modFlag did not track edit")

        local st2 = pob_notesToggleColorCodes()
        assert(st2.ok and st2.showColorCodes == true, "showColorCodes did not toggle on")
        assert(st2.text == "Test ^_xB97123Fire^_7 Note", "color codes not escaped: " .. tostring(st2.text))

        local wrappedEsc = pob_notesWrapSelection("Cold", colorCodes.COLD)
        assert(wrappedEsc:find("%^_x"), "wrapped selection should escape when showColorCodes=true")

        local st3 = pob_notesToggleColorCodes()
        assert(st3.ok and st3.showColorCodes == false, "showColorCodes did not toggle off")
        assert(st3.text == sample, "color codes not unescaped: " .. tostring(st3.text))

        local wrappedPlain = pob_notesWrapSelection("Cold", colorCodes.COLD)
        assert(wrappedPlain == (colorCodes.COLD .. "Cold^7"), "wrapped selection mismatch: " .. tostring(wrappedPlain))

        -- <Notes> XML round-trip
        local xml = { elem = "Notes" }
        nt:Save(xml)
        assert(xml[1] == sample, "Notes:Save XML mismatch")
        nt.controls.edit:SetText("")
        nt:Load(xml, "selftest")
        assert(nt.controls.edit.buf == sample, "Notes:Load XML round-trip mismatch")
    end)

    restore()
    if not ok then
        return fail(tostring(err))
    end
    return { ok = true }
end

function pob_selftestPartyTab()
    local bm, pt = partyCtx()
    if not bm or not pt or not pt.controls then
        return fail("partyTab unavailable")
    end

    -- Snapshot original party XML & state
    local savedXml = { elem = "Party" }
    pt:Save(savedXml)
    local origDest = pt.controls.importCodeDestination.selIndex or 1
    local origAppend = pt.controls.appendNotReplace.state == true
    local origAdv = pt.controls.ShowAdvanceTools.state == true

    local function restore()
        pt.controls.importCodeDestination.selIndex = 1 -- All
        pt.controls.clear.onClick()
        pt:Load(savedXml, "selftest")
        pt.controls.importCodeDestination.selIndex = origDest
        pt.controls.appendNotReplace.state = origAppend
        pt.controls.ShowAdvanceTools.state = origAdv
        pt:ResetModFlags()
        pob_recalculate()
    end

    local ok, err = pcall(function()
        pt.controls.importCodeDestination.selIndex = 1
        pob_partyClear()
        local baseArmour = (bm.calcsTab and bm.calcsTab.mainOutput and bm.calcsTab.mainOutput.Armour) or 0

        -- Build a minimal PoB export code containing a support aura (+1000 Armour)
        local auraMod = modLib.createMod("Armour", "BASE", 1000, "PartySelftest", 0, 0, { type = "GlobalEffect", effectType = "Aura" })
        local auraBuf = "Determination\n100\n" .. modLib.formatSourceMod(auraMod) .. "\n---"
        local exportXml = {
            elem = "PathOfBuilding",
            {
                elem = "Party",
                attrib = { destination = "All", append = "false", ShowAdvanceTools = "false" },
                { elem = "ExportedBuffs", attrib = { name = "Aura" }, auraBuf },
            }
        }
        local xmlText = common.xml.ComposeXML(exportXml)
        assert(xmlText and #xmlText > 0, "ComposeXML failed")
        local code = common.base64.encode(Deflate(xmlText)):gsub("+", "-"):gsub("/", "_")

        local stCode = pob_partySetImportCode(code)
        assert(stCode.ok and stCode.importValid == true, "import code not marked valid: " .. tostring(stCode.importDetail))

        local stImp = pob_partyImport()
        assert(stImp.ok, "pob_partyImport failed: " .. tostring(stImp.error))
        assert(stImp.buffers.auras:find("Determination", 1, true), "editAuras missing Determination")
        assert(stImp.buffers.simpleAuras:find("Determination", 1, true), "simpleAuras missing Determination")
        assert(pt.actor and pt.actor.Aura and pt.actor.Aura.Aura and pt.actor.Aura.Aura.Determination, "actor.Aura.Aura.Determination missing")

        local boostedArmour = (bm.calcsTab and bm.calcsTab.mainOutput and bm.calcsTab.mainOutput.Armour) or 0
        assert(boostedArmour > baseArmour,
            s_format("support aura did not raise Armour (base=%s, boosted=%s)", tostring(baseArmour), tostring(boostedArmour)))

        -- Disable Party Effects removes the stat boost without clearing buffers
        local stDis = pob_partyDisableEffects()
        assert(stDis.ok and not stDis.effectsActive, "effects still active after Disable Party Effects")
        local disabledArmour = (bm.calcsTab and bm.calcsTab.mainOutput and bm.calcsTab.mainOutput.Armour) or 0
        assert(disabledArmour == baseArmour,
            s_format("Armour not restored after disable (base=%s, disabled=%s)", tostring(baseArmour), tostring(disabledArmour)))
        assert(stDis.buffers.auras:find("Determination", 1, true), "Disable Party Effects should preserve buffer text")

        -- Rebuild All restores the aura effect
        local stReb = pob_partyRebuildAll()
        assert(stReb.ok and stReb.effectsActive, "Rebuild All did not restore party effects")
        local rebuiltArmour = (bm.calcsTab and bm.calcsTab.mainOutput and bm.calcsTab.mainOutput.Armour) or 0
        assert(rebuiltArmour == boostedArmour,
            s_format("Armour mismatch after Rebuild All (boosted=%s, rebuilt=%s)", tostring(boostedArmour), tostring(rebuiltArmour)))

        -- <Party> XML round-trip
        pob_partySetShowAdvanced(true)
        local rtXml = { elem = "Party" }
        pt:Save(rtXml)
        assert(rtXml.attrib and rtXml.attrib.ShowAdvanceTools == "true", "Party:Save ShowAdvanceTools attrib mismatch")

        pob_partyClear()
        pt:Load(rtXml, "selftest")
        bm.buildFlag = true
        pob_recalculate()
        local stRt = pob_partyGetState()
        assert(stRt.showAdvanced == true, "Party:Load ShowAdvanceTools mismatch")
        assert(stRt.buffers.auras:find("Determination", 1, true), "Party:Load XML round-trip missing Determination")
        local rtArmour = (bm.calcsTab and bm.calcsTab.mainOutput and bm.calcsTab.mainOutput.Armour) or 0
        assert(rtArmour == boostedArmour, "Party:Load XML round-trip did not restore Armour boost")
    end)

    restore()
    if not ok then
        return fail(tostring(err))
    end
    return { ok = true }
end
