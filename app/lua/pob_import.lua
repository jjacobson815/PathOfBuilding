-- Path of Building (Qt port)
--
-- Module: pob_import.lua  —  Import/Export tab bridge (Phase 11)
--
-- Ports src/Classes/ImportTab.lua + BuildSiteTools + PoEAPI into a unified,
-- guided QML bridge:
--   Part 11.1 — Build sharing (generate/copy/upload via BuildSiteTools,
--               open from URL/code/dev-JSON, Export Support checkbox)
--   Part 11.2 — Character account import flow (OAuth via PoEAPI + LaunchServer,
--               account-name + #discriminator + POESESSID fallback)
--   Part 11.3 — Character import pipeline (reuses ImportTab:ImportPassiveTreeAndJewels
--               and ImportTab:ImportItemsAndSkills with re-import socket-group
--               preservation, new build default vs confirmed overwrite)
--   Part 11.4 — Usability state helpers (plain-word status, explicit disabled
--               reasons, collapsed Options with 1-sentence explanations)
--
-- OAuth token storage keeps legacy Settings.xml plaintext (PoEAPI:UpdateMain)
-- for v1 to preserve src/ immutability.

local t_insert = table.insert
local t_remove = table.remove
local s_format = string.format
local m_max = math.max
local dkjson = require("dkjson")

local EMIT_IMPORT = { "import" }
local EMIT_IMPORT_NET = { "import", "network" }
local EMIT_IMPORT_BUILD = { "import", "build", "tree", "items", "skills", "config", "notes", "party", "compare", "mode", "calcs" }
local EMIT_IMPORT_CHAR = { "import", "build", "tree", "items", "skills", "config", "calcs" }

local REALMS = {
    { label = "PC",   id = "PC",   realmCode = "pc",   hostName = "https://www.pathofexile.com/", profileURL = "account/view-profile/" },
    { label = "Xbox", id = "XBOX", realmCode = "xbox", hostName = "https://www.pathofexile.com/", profileURL = "account/view-profile/" },
    { label = "Sony", id = "SONY", realmCode = "sony", hostName = "https://www.pathofexile.com/", profileURL = "account/view-profile/" },
}

local OPTION_DEFS = {
    {
        key = "deleteJewels",
        label = "Delete existing jewels",
        description = "Removes all jewels currently socketed in the passive tree before importing the character's jewels.",
    },
    {
        key = "deleteSkills",
        label = "Delete existing skills",
        description = "Replaces existing skill groups with the character's gems while keeping your group order and enabled states.",
    },
    {
        key = "deleteEquipment",
        label = "Delete existing equipment",
        description = "Removes all currently equipped items before equipping the character's gear.",
    },
    {
        key = "ignoreWeaponSwap",
        label = "Ignore weapon swap",
        description = "Skips items and gems socketed in your secondary weapon swap slots.",
    },
}

-- Persistent UI state across tab switches and build reloads.
local ui = {
    authMethod = "oauth",      -- "oauth" | "account"
    realmId = nil,             -- "PC" | "XBOX" | "SONY"
    accountName = nil,         -- string
    sessionId = "",            -- optional POESESSID fallback for private profiles
    selectedLeague = "All",
    selectedCharIndex = 0,     -- 1-based index into filtered characters
    importTree = true,
    importItems = true,
    targetMode = "new",        -- "new" | "overwrite"
    deleteJewels = true,
    deleteSkills = true,
    deleteEquipment = true,
    ignoreWeaponSwap = false,

    busy = false,
    busyStep = "",
    statusText = "",
    errorText = "",
    oauthSubScriptId = nil,
    oauthStartedAt = nil,
    rateLimitEndTime = nil,

    -- Cached character lists per source & realmCode
    oauthCharacters = {},      -- [realmCode] = { char, ... }
    accountCharacters = {},    -- [realmCode] = { char, ... }
    accountFetchedFor = {},    -- [realmCode] = accountName

    -- Share this build
    shareCode = "",
    shareSiteId = nil,
    shareBusy = false,
    shareStatus = "",
    shareError = "",

    -- Open a build from link or code
    openInput = "",
    openValid = false,
    openKind = "none",         -- "none" | "url" | "code" | "json"
    openSiteIndex = nil,
    openSiteLabel = "",
    openDetail = "",
    openXML = nil,
    openJson = nil,
    openMode = "new",          -- "new" | "overwrite" | "compare"
    openFetching = false,
    openStatus = "",
    openError = "",
}

local function importCtx()
    local bm = main and main.modes and main.modes.BUILD
    return bm, bm and bm.importTab
end

local function ensureApi()
    if main and not main.api then
        main.api = new("PoEAPI"):PoEAPI(main.lastToken, main.lastRefreshToken, main.tokenExpiry)
    end
    return main and main.api
end

local function fail(msg)
    return { ok = false, error = tostring(msg or "Unknown error") }
end

local function emitSignal(name)
    if pob and pob.emitSignal then
        pob.emitSignal(name)
    end
end

local function emitList(list)
    if not pob or not pob.emitSignal then return end
    for _, sig in ipairs(list) do
        pob.emitSignal(sig)
    end
end

local function findRealm(realmId)
    local target = realmId or ui.realmId or (main and main.lastRealm) or "PC"
    for _, r in ipairs(REALMS) do
        if r.id == target or r.realmCode == target:lower() then
            return r
        end
    end
    return REALMS[1]
end

local function getExportSites()
    local out = {}
    if buildSites and buildSites.websiteList then
        for _, site in ipairs(buildSites.websiteList) do
            if site.postUrl and site.postFields and site.codeOut then
                t_insert(out, site)
            end
        end
    end
    return out
end

local function findExportSite(siteId)
    local sites = getExportSites()
    if siteId then
        for _, s in ipairs(sites) do
            if s.id == siteId then return s end
        end
    end
    -- Prefer pobb.in if available, else first exportable site
    for _, s in ipairs(sites) do
        if s.id == "POBBin" then return s end
    end
    return sites[1]
end

local function classColorCode(charClass)
    if not charClass or charClass == "?" then
        return (colorCodes and colorCodes.DEFAULT) or "^7"
    end
    local cc = colorCodes and colorCodes[charClass:upper()]
    if cc then return cc end
    local witch = { Elementalist = true, Necromancer = true, Occultist = true, Harbinger = true, Herald = true, ["Bog Shaman"] = true }
    local templar = { Guardian = true, Inquisitor = true, Hierophant = true, ["Architect of Chaos"] = true, Polytheist = true, Puppeteer = true }
    local shadow = { Assassin = true, Trickster = true, Saboteur = true, Surfcaster = true, ["Servant of Arakaali"] = true, ["Blind Prophet"] = true }
    local duelist = { Gladiator = true, Slayer = true, Champion = true, Gambler = true, Paladin = true, Aristocrat = true }
    local ranger = { Raider = true, Pathfinder = true, Deadeye = true, Warden = true, ["Daughter of Oshabi"] = true, Whisperer = true, Wildspeaker = true }
    local marauder = { Juggernaut = true, Berserker = true, Chieftain = true, Antiquarian = true, Behemoth = true, ["Ancestral Commander"] = true }
    local scion = { Ascendant = true, Reliquarian = true, Luminary = true, Scavenger = true }
    if witch[charClass] then return colorCodes.WITCH or "^7" end
    if templar[charClass] then return colorCodes.TEMPLAR or "^7" end
    if shadow[charClass] then return colorCodes.SHADOW or "^7" end
    if duelist[charClass] then return colorCodes.DUELIST or "^7" end
    if ranger[charClass] then return colorCodes.RANGER or "^7" end
    if marauder[charClass] then return colorCodes.MARAUDER or "^7" end
    if scion[charClass] then return colorCodes.SCION or "^7" end
    return (colorCodes and colorCodes.DEFAULT) or "^7"
end

local function activeRawCharacters(realmCode)
    if ui.authMethod == "oauth" then
        return ui.oauthCharacters[realmCode]
    else
        return ui.accountCharacters[realmCode]
    end
end

local function buildLeaguesAndChars(realmCode, lastCharHash)
    local raw = activeRawCharacters(realmCode)
    local leagues = {}
    local seenLeague = {}
    if raw then
        for _, c in ipairs(raw) do
            if (not c.realm or c.realm == realmCode) and c.league and not seenLeague[c.league] then
                seenLeague[c.league] = true
                t_insert(leagues, c.league)
            end
        end
    end
    table.sort(leagues, function(a, b) return a:lower() < b:lower() end)
    t_insert(leagues, 1, "All")

    -- Ensure selectedLeague is valid
    local leagueValid = false
    for _, l in ipairs(leagues) do
        if l == ui.selectedLeague then leagueValid = true; break end
    end
    if not leagueValid then
        local pref = main and main.lastLeague
        if pref and seenLeague[pref] then
            ui.selectedLeague = pref
        else
            ui.selectedLeague = "All"
        end
    end

    local chars = {}
    if raw then
        for _, c in ipairs(raw) do
            if (not c.realm or c.realm == realmCode)
                and (ui.selectedLeague == "All" or c.league == ui.selectedLeague)
            then
                local name = c.name or "?"
                local cls = c.class or "?"
                local lvl = tonumber(c.level) or 0
                local lg = c.league or "?"
                local cc = classColorCode(cls)
                local detail = ui.selectedLeague == "All"
                    and s_format("%s%s ^x808080lvl %d (%s)", cc, cls, lvl, lg)
                    or s_format("%s%s ^x808080lvl %d", cc, cls, lvl)
                t_insert(chars, {
                    name = name,
                    className = cls,
                    level = lvl,
                    league = lg,
                    realm = c.realm or realmCode,
                    label = s_format("^7%s  %s", name, detail),
                    detail = detail,
                    raw = c,
                })
            end
        end
    end
    table.sort(chars, function(a, b) return a.name:lower() < b.name:lower() end)

    -- Clamp or restore selectedCharIndex
    if #chars == 0 then
        ui.selectedCharIndex = 0
    elseif ui.selectedCharIndex < 1 or ui.selectedCharIndex > #chars then
        ui.selectedCharIndex = 1
        if lastCharHash and common and common.sha1 then
            for i, c in ipairs(chars) do
                if common.sha1(c.name) == lastCharHash then
                    ui.selectedCharIndex = i
                    break
                end
            end
        end
    end

    return leagues, chars
end

local function getAccountHistory()
    local list = {}
    if main and main.gameAccounts then
        for name, _ in pairs(main.gameAccounts) do
            if type(name) == "string" and #name > 0 then
                t_insert(list, name)
            end
        end
    end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    return list
end

local function isValidAccountName(name)
    if type(name) ~= "string" then return false end
    return name:match("%S[#%-]%d%d%d%d$") ~= nil
end

local function sanitizeAccountPaste(text)
    if type(text) ~= "string" then return "" end
    return text:gsub(".", function(c)
        local b = c:byte()
        if b >= 128 then
            return s_format("%%%02X", b)
        end
        return c
    end)
end

local function isAlreadySiteUrl(text)
    if not text or #text == 0 or not buildSites or not buildSites.websiteList then
        return false
    end
    for _, site in ipairs(buildSites.websiteList) do
        if site.matchURL and text:match(site.matchURL) then
            return true
        end
    end
    return false
end

local function buildStateSnapshot()
    local bm, it = importCtx()
    local api = ensureApi()

    if not ui.realmId then
        ui.realmId = (it and it.lastRealm) or (main and main.lastRealm) or "PC"
    end
    if ui.accountName == nil then
        ui.accountName = (it and it.controls and it.controls.siteAccountName and it.controls.siteAccountName.buf)
            or (main and main.lastAccountName) or ""
    end
    if not ui.shareSiteId then
        local site = findExportSite((it and it.exportWebsiteSelected) or (main and main.lastExportWebsite))
        ui.shareSiteId = site and site.id or ""
    end

    local realm = findRealm(ui.realmId)
    local now = os.time()

    -- OAuth timer expiry check (60s window matching legacy ImportTab.lua)
    local oauthSecondsLeft = 0
    if ui.oauthStartedAt then
        oauthSecondsLeft = m_max(0, (ui.oauthStartedAt + 60) - now)
        if oauthSecondsLeft == 0 then
            ui.oauthStartedAt = nil
            ui.oauthSubScriptId = nil
            ui.busy = false
            ui.busyStep = ""
            if not (api and api.authToken) then
                ui.statusText = "Sign-in timed out. Click Authorize with Path of Exile to try again."
            end
        end
    end

    local rateLimitSecondsLeft = 0
    if ui.rateLimitEndTime then
        rateLimitSecondsLeft = m_max(0, ui.rateLimitEndTime - now)
        if rateLimitSecondsLeft == 0 then
            ui.rateLimitEndTime = nil
        end
    end

    local oauthAuthorized = (api and api.authToken ~= nil) or false
    local oauthWaiting = (not oauthAuthorized) and (ui.oauthStartedAt ~= nil)

    local lastCharHash = (it and it.lastCharacterHash) or (main and main.lastCharacterHash)
    local leagues, chars = buildLeaguesAndChars(realm.realmCode, lastCharHash)

    -- Strip raw table from character entries returned to QML
    local qmlChars = {}
    for _, c in ipairs(chars) do
        t_insert(qmlChars, {
            name = c.name,
            className = c.className,
            level = c.level,
            league = c.league,
            realm = c.realm,
            label = c.label,
            detail = c.detail,
        })
    end

    local accountValid = isValidAccountName(ui.accountName)
    local accountHint = ""
    if ui.accountName ~= "" and not accountValid then
        accountHint = "Include the #1234 discriminator at the end of your account name (e.g. " .. ui.accountName .. "#1234)."
    end

    -- Disabled reasons for Fetch Characters
    local canFetch = true
    local fetchDisabledReason = ""
    if ui.busy then
        canFetch = false
        fetchDisabledReason = ui.busyStep ~= "" and ui.busyStep or "Another import operation is in progress."
    elseif rateLimitSecondsLeft > 0 then
        canFetch = false
        fetchDisabledReason = s_format("Path of Exile rate limit active. Wait %d seconds.", rateLimitSecondsLeft)
    elseif ui.authMethod == "oauth" and not oauthAuthorized then
        canFetch = false
        fetchDisabledReason = "Sign in with your Path of Exile account first."
    elseif ui.authMethod == "account" and not accountValid then
        canFetch = false
        fetchDisabledReason = ui.accountName == ""
            and "Enter your Path of Exile account name (including #1234)."
            or "Account name must include the #1234 discriminator."
    end

    -- Disabled reasons for Import Character
    local selectedChar = (ui.selectedCharIndex >= 1 and ui.selectedCharIndex <= #qmlChars) and qmlChars[ui.selectedCharIndex] or nil
    local canImportChar = true
    local importDisabledReason = ""
    if ui.busy then
        canImportChar = false
        importDisabledReason = ui.busyStep ~= "" and ui.busyStep or "Import is currently in progress."
    elseif rateLimitSecondsLeft > 0 then
        canImportChar = false
        importDisabledReason = s_format("Rate limited. Please wait %d seconds.", rateLimitSecondsLeft)
    elseif not selectedChar then
        canImportChar = false
        if ui.authMethod == "oauth" and not oauthAuthorized then
            importDisabledReason = "Sign in with Path of Exile and fetch your characters first."
        elseif ui.authMethod == "account" and not accountValid then
            importDisabledReason = "Enter a valid account name (#1234) and fetch characters first."
        else
            importDisabledReason = "Fetch and select a character before importing."
        end
    elseif not ui.importTree and not ui.importItems then
        canImportChar = false
        importDisabledReason = "Choose at least one item to import (Passive Tree & Jewels or Items & Skills)."
    end

    local importBtnLabel = ui.targetMode == "overwrite"
        and "Import into Current Build"
        or (selectedChar and ("Import \"" .. selectedChar.name .. "\" as New Build") or "Import as New Build")

    -- Plain-word status text
    local statusText = ui.statusText
    if statusText == "" then
        if ui.busy and ui.busyStep ~= "" then
            statusText = ui.busyStep
        elseif oauthWaiting then
            statusText = s_format("Waiting for browser sign-in... (%ds left — URL copied to clipboard)", oauthSecondsLeft)
        elseif rateLimitSecondsLeft > 0 then
            statusText = s_format("Too many requests. Please wait %d seconds.", rateLimitSecondsLeft)
        elseif ui.authMethod == "oauth" then
            statusText = oauthAuthorized and "Signed in with Path of Exile." or "Not signed in. Authorize with Path of Exile or switch to Account Name."
        else
            statusText = #qmlChars > 0
                and s_format("Ready to import from %s (%d characters).", ui.accountName, #qmlChars)
                or "Enter a public account name with #1234 to fetch characters."
        end
    end

    -- Options list with 1-sentence descriptions
    local optionsList = {}
    for _, def in ipairs(OPTION_DEFS) do
        t_insert(optionsList, {
            key = def.key,
            label = def.label,
            checked = ui[def.key] == true,
            description = def.description,
        })
    end

    -- Share section
    local exportSites = {}
    for _, s in ipairs(getExportSites()) do
        t_insert(exportSites, { id = s.id, label = s.label })
    end
    local shareIsLink = isAlreadySiteUrl(ui.shareCode)
    local canCopy = #ui.shareCode > 0
    local copyDisabledReason = canCopy and "" or "Generate a build code first."
    local canUpload = (not ui.shareBusy) and (#exportSites > 0) and (not shareIsLink)
    local uploadDisabledReason = ""
    if ui.shareBusy then
        uploadDisabledReason = "Uploading build to sharing site..."
    elseif shareIsLink then
        uploadDisabledReason = "This build has already been uploaded as a short link."
    elseif #exportSites == 0 then
        uploadDisabledReason = "No build sharing sites are configured."
    end

    local exportParty = (it and it.controls and it.controls.enablePartyExportBuffs and it.controls.enablePartyExportBuffs.state == true)
        or (bm and bm.partyTab and bm.partyTab.enableExportBuffs == true) or false

    -- Open build section
    local canOpenImport = ui.openValid and (not ui.openFetching)
    local openDisabledReason = ""
    if ui.openFetching then
        openDisabledReason = "Downloading build..."
    elseif ui.openInput == "" then
        openDisabledReason = "Paste a build share code or link (pobb.in, maxroll, pastebin, etc.) first."
    elseif not ui.openValid then
        openDisabledReason = ui.openDetail ~= "" and ui.openDetail or "The pasted text is not a valid build code or supported link."
    end

    local openBtnLabel = "Open as New Build"
    if ui.openFetching then
        openBtnLabel = "Downloading..."
    elseif ui.openMode == "overwrite" then
        openBtnLabel = "Replace Current Build"
    elseif ui.openMode == "compare" then
        openBtnLabel = "Open as Comparison"
    end

    local realmListOut = {}
    for _, r in ipairs(REALMS) do
        t_insert(realmListOut, { id = r.id, label = r.label, realmCode = r.realmCode })
    end

    return {
        ok = true,
        authMethod = ui.authMethod,
        oauthAuthorized = oauthAuthorized,
        oauthWaiting = oauthWaiting,
        oauthSecondsLeft = oauthSecondsLeft,
        rateLimitSecondsLeft = rateLimitSecondsLeft,
        realmId = realm.id,
        realms = realmListOut,
        accountName = ui.accountName,
        accountHistory = getAccountHistory(),
        accountNameValid = accountValid,
        accountNameHint = accountHint,
        sessionId = ui.sessionId,
        leagues = leagues,
        selectedLeague = ui.selectedLeague,
        characters = qmlChars,
        selectedCharIndex = ui.selectedCharIndex,
        importTree = ui.importTree,
        importItems = ui.importItems,
        targetMode = ui.targetMode,
        currentBuildName = (bm and bm.buildName) or "Unnamed build",
        options = optionsList,
        busy = ui.busy,
        busyStep = ui.busyStep,
        statusText = statusText,
        errorText = ui.errorText,
        canFetchCharacters = canFetch,
        fetchDisabledReason = fetchDisabledReason,
        canImportCharacter = canImportChar,
        importDisabledReason = importDisabledReason,
        importButtonLabel = importBtnLabel,
        share = {
            code = ui.shareCode,
            isLink = shareIsLink,
            exportParty = exportParty,
            exportPartyDescription = "Include auras, curses, and enemy modifiers so another build can import this character in the Party tab.",
            sites = exportSites,
            selectedSiteId = ui.shareSiteId,
            busy = ui.shareBusy,
            statusText = ui.shareStatus,
            errorText = ui.shareError,
            canCopy = canCopy,
            copyDisabledReason = copyDisabledReason,
            canUpload = canUpload,
            uploadDisabledReason = uploadDisabledReason,
        },
        open = {
            input = ui.openInput,
            valid = ui.openValid,
            kind = ui.openKind,
            siteLabel = ui.openSiteLabel,
            detail = ui.openDetail,
            mode = ui.openMode,
            fetching = ui.openFetching,
            statusText = ui.openStatus,
            errorText = ui.openError,
            canImport = canOpenImport,
            importDisabledReason = openDisabledReason,
            importButtonLabel = openBtnLabel,
        },
    }
end

-- ============================================================================
-- STATE QUERY
-- ============================================================================

function pob_importGetState()
    local bm, it = importCtx()
    if not bm or not it then
        return fail("importTab unavailable")
    end
    return buildStateSnapshot()
end

-- ============================================================================
-- PART 11.1 — BUILD SHARING (GENERATE / COPY / UPLOAD / OPEN FROM LINK OR CODE)
-- ============================================================================

local function generateCurrentBuildCode(bm, it)
    local xml = bm:SaveDB("code")
    if not xml or #xml == 0 then
        return nil, "Could not serialize current build."
    end
    local compressed = Deflate(xml)
    if not compressed then
        return nil, "Could not compress build XML."
    end
    local code = common.base64.encode(compressed):gsub("+", "-"):gsub("/", "_")
    if it and it.controls and it.controls.generateCodeOut then
        it.controls.generateCodeOut:SetText(code)
    end
    return code
end

function pob_importGenerateCode()
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    local code, err = generateCurrentBuildCode(bm, it)
    if not code then
        ui.shareError = err
        ui.shareStatus = ""
        local st = buildStateSnapshot()
        st._emit = EMIT_IMPORT
        return st
    end
    ui.shareCode = code
    ui.shareError = ""
    ui.shareStatus = "Build code generated. Copy it or upload to a sharing site."
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT
    return st
end

function pob_importCopyShareCode()
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    if #ui.shareCode == 0 then
        return fail("Generate a build code first.")
    end
    Copy(ui.shareCode)
    ui.shareStatus = ui.shareCode:match("^https?://") and "Share link copied to clipboard." or "Build code copied to clipboard."
    ui.shareError = ""
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT
    return st
end

function pob_importSetExportParty(enabled)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    local flag = (enabled == true)
    if it.controls and it.controls.enablePartyExportBuffs then
        it.controls.enablePartyExportBuffs.state = flag
    end
    if bm.partyTab then
        bm.partyTab.enableExportBuffs = flag
    end
    bm.buildFlag = true
    local st = buildStateSnapshot()
    st._emit = { "import", "build", "party" }
    return st
end

function pob_importSetShareSite(siteId)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    local site = findExportSite(siteId)
    if not site then return fail("Unknown export site: " .. tostring(siteId)) end
    ui.shareSiteId = site.id
    if main then main.lastExportWebsite = site.id end
    it.exportWebsiteSelected = site.id
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT
    return st
end

function pob_importUploadBuild(siteId)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    local site = findExportSite(siteId or ui.shareSiteId)
    if not site then return fail("No export site available.") end
    ui.shareSiteId = site.id
    if main then main.lastExportWebsite = site.id end
    it.exportWebsiteSelected = site.id

    -- Auto-generate code if user clicked Upload directly
    if #ui.shareCode == 0 then
        local code, err = generateCurrentBuildCode(bm, it)
        if not code then
            ui.shareError = err
            local st = buildStateSnapshot()
            st._emit = EMIT_IMPORT
            return st
        end
        ui.shareCode = code
    elseif isAlreadySiteUrl(ui.shareCode) then
        return fail("Build has already been uploaded as a short link.")
    end

    local subId = buildSites.UploadBuild(ui.shareCode, site)
    if not subId then
        ui.shareBusy = false
        ui.shareError = "Could not start upload to " .. site.label .. "."
        local st = buildStateSnapshot()
        st._emit = EMIT_IMPORT
        return st
    end

    ui.shareBusy = true
    ui.shareError = ""
    ui.shareStatus = "Uploading to " .. site.label .. "..."

    launch:RegisterSubScript(subId, function(pasteLink, errMsg)
        ui.shareBusy = false
        if errMsg or not pasteLink or #tostring(pasteLink) == 0 then
            ui.shareError = "Could not create link on " .. site.label .. ": " .. tostring(errMsg or "empty response")
            ui.shareStatus = ""
        else
            local finalLink = (site.codeOut or "") .. tostring(pasteLink):gsub("^%s+", ""):gsub("%s+$", "")
            ui.shareCode = finalLink
            if it and it.controls and it.controls.generateCodeOut then
                it.controls.generateCodeOut:SetText(finalLink)
            end
            ui.shareError = ""
            ui.shareStatus = "Uploaded to " .. site.label .. ". Click Copy to share."
        end
        emitSignal("import")
    end)

    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT_NET
    return st
end

local function decodeBuildCodeToXml(raw)
    if type(raw) ~= "string" then return nil end
    local cleaned = raw:gsub("%s+", ""):gsub("-", "+"):gsub("_", "/")
    if #cleaned == 0 then return nil end
    local okDec, decoded = pcall(common.base64.decode, cleaned)
    if not okDec or not decoded or #decoded == 0 then return nil end
    local okInf, xml = pcall(Inflate, decoded)
    if not okInf or type(xml) ~= "string" or #xml == 0 then return nil end
    if not xml:find("<PathOfBuilding", 1, true) and not xml:match("^%s*<%?xml") and not xml:match("^%s*<") then
        return nil
    end
    return xml
end

local function validateOpenInput(buf)
    ui.openInput = buf or ""
    ui.openValid = false
    ui.openKind = "none"
    ui.openSiteIndex = nil
    ui.openSiteLabel = ""
    ui.openDetail = ""
    ui.openXML = nil
    ui.openJson = nil
    ui.openError = ""

    if #ui.openInput == 0 then
        return
    end

    local urlText = ui.openInput:gsub("^[%s?]+", ""):gsub("[%s?]+$", "")
    -- Unwrap YouTube / Google redirect wrappers (mirrors ImportTab.lua)
    if urlText:match("youtube%.com/redirect%?") or urlText:match("google%.com/url%?") then
        local nested = urlText:gsub(".*[?&]q=([^&]+).*", "%1")
        if UrlDecode then
            urlText = UrlDecode(nested) or urlText
        else
            urlText = nested:gsub("+", " "):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
        end
    end

    -- Support pob:// URI scheme via BuildSiteTools
    if urlText:match("^pob:[/\\]*") and buildSites and buildSites.ParseImportLinkFromURI then
        local parsed = buildSites.ParseImportLinkFromURI(urlText)
        if parsed then
            urlText = parsed
        end
    end

    -- Match against known build sites
    if buildSites and buildSites.websiteList then
        for idx, site in ipairs(buildSites.websiteList) do
            if site.matchURL and urlText:match(site.matchURL) then
                ui.openInput = urlText
                ui.openValid = true
                ui.openKind = "url"
                ui.openSiteIndex = idx
                ui.openSiteLabel = site.label
                ui.openDetail = "Valid " .. site.label .. " link"
                return
            end
        end
    end

    -- Dev-mode raw character JSON
    if launch and launch.devMode and urlText:match("^%{.*%}$") then
        local jsonData, _, errDecode = dkjson.decode(urlText)
        if errDecode or type(jsonData) ~= "table" then
            ui.openDetail = "Invalid JSON format (could not decode)."
            return
        end
        if not jsonData.character then
            ui.openDetail = "Invalid character JSON (missing 'character' object)."
            return
        end
        local ch = jsonData.character
        if not ch.equipment or not ch.passives then
            ui.openDetail = "Invalid character JSON (missing 'equipment' or 'passives')."
            return
        end
        ui.openJson = ch
        ui.openValid = true
        ui.openKind = "json"
        ui.openDetail = "Valid character JSON (dev mode)"
        return
    end

    -- Raw base64 + deflate build code
    local xml = decodeBuildCodeToXml(urlText)
    if xml then
        ui.openXML = xml
        ui.openValid = true
        ui.openKind = "code"
        ui.openDetail = "Valid build code"
        return
    end

    ui.openDetail = "Not a recognized build code or supported build link."
end

function pob_importValidateInput(text)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    validateOpenInput(text)
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT
    return st
end

function pob_importSetOpenMode(mode)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    if mode ~= "new" and mode ~= "overwrite" and mode ~= "compare" then
        return fail("Invalid open mode: " .. tostring(mode))
    end
    ui.openMode = mode
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT
    return st
end

local function applyOpenedXml(xmlText, importLink)
    local bm = main and main.modes and main.modes.BUILD
    if not bm then return false, "Build mode unavailable." end

    if ui.openMode == "overwrite" then
        bm:Shutdown()
        bm:Init(bm.dbFileName, bm.buildName, xmlText, false, importLink)
        bm.viewMode = "TREE"
        ui.openStatus = "Replaced current build."
        ui.openError = ""
        return true
    elseif ui.openMode == "compare" then
        if not bm.compareTab then
            return false, "Compare tab is unavailable."
        end
        if bm.compareTab:ImportBuild(xmlText, "Imported comparison") then
            bm.viewMode = "COMPARE"
            ui.openStatus = "Opened build in Compare tab."
            ui.openError = ""
            return true
        else
            return false, "Failed to import build for comparison."
        end
    else
        bm:Shutdown()
        bm:Init(false, "Imported build", xmlText, false, importLink)
        bm.viewMode = "TREE"
        ui.openStatus = "Opened as a new build."
        ui.openError = ""
        return true
    end
end

function pob_importOpenBuild(confirmed)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    if not ui.openValid or ui.openFetching then
        return fail(ui.openDetail ~= "" and ui.openDetail or "Paste a valid build code or link first.")
    end

    if ui.openMode == "overwrite" and confirmed ~= true then
        return {
            ok = false,
            needsConfirm = true,
            confirmTitle = "Replace Current Build?",
            confirmMessage = s_format(
                "Importing into \"%s\" will replace its entire passive tree, items, skills, configuration, and notes.",
                bm.buildName or "Unnamed build"
            ),
        }
    end

    if ui.openKind == "url" and not ui.openXML then
        local site = buildSites.websiteList[ui.openSiteIndex]
        if not site then
            return fail("Unknown build site.")
        end
        ui.openFetching = true
        ui.openStatus = "Downloading build from " .. site.label .. "..."
        ui.openError = ""
        local linkUrl = ui.openInput

        buildSites.DownloadBuild(linkUrl, site, function(isSuccess, data)
            ui.openFetching = false
            if not isSuccess then
                ui.openError = "Download failed: " .. tostring(data)
                ui.openStatus = ""
                emitSignal("import")
                return
            end
            local xml = decodeBuildCodeToXml(data)
            if not xml then
                ui.openError = "Downloaded data was not a valid Path of Building code."
                ui.openStatus = ""
                emitSignal("import")
                return
            end
            local okApply, errApply = applyOpenedXml(xml, linkUrl)
            if not okApply then
                ui.openError = errApply
                ui.openStatus = ""
                emitSignal("import")
                return
            end
            emitList(EMIT_IMPORT_BUILD)
        end)

        local st = buildStateSnapshot()
        st._emit = EMIT_IMPORT_NET
        return st
    end

    if ui.openKind == "json" and ui.openJson then
        it:ImportItemsAndSkills(ui.openJson, true, true, false)
        it:ImportPassiveTreeAndJewels(ui.openJson, true)
        bm.buildFlag = true
        ui.openStatus = "Imported character JSON."
        ui.openError = ""
        local st = buildStateSnapshot()
        st._emit = EMIT_IMPORT_CHAR
        return st
    end

    local okApply, errApply = applyOpenedXml(ui.openXML, nil)
    if not okApply then
        ui.openError = errApply
        local st = buildStateSnapshot()
        st._emit = EMIT_IMPORT
        return st
    end
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT_BUILD
    return st
end

-- ============================================================================
-- PART 11.2 — CHARACTER ACCOUNT IMPORT FLOW (OAUTH + ACCOUNT NAME + POESESSID)
-- ============================================================================

function pob_importSetAuthMethod(method)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    if method ~= "oauth" and method ~= "account" then
        return fail("Invalid auth method: " .. tostring(method))
    end
    ui.authMethod = method
    ui.errorText = ""
    ui.statusText = ""
    ui.selectedCharIndex = 0
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT
    return st
end

function pob_importSetRealm(realmId)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    local realm = findRealm(realmId)
    ui.realmId = realm.id
    if it.controls and it.controls.accountRealm then
        it.controls.accountRealm:SelByValue(realm.id, "id")
    end
    if it.controls and it.controls.siteAccountRealm then
        it.controls.siteAccountRealm:SelByValue(realm.id, "id")
    end
    ui.selectedCharIndex = 0
    ui.errorText = ""
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT
    return st
end

function pob_importSetAccountName(name)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    local sanitized = sanitizeAccountPaste(name or "")
    ui.accountName = sanitized
    if it.controls and it.controls.siteAccountName then
        it.controls.siteAccountName:SetText(sanitized)
    end
    -- Restore saved POESESSID for this account if present
    if main and main.gameAccounts and main.gameAccounts[sanitized] and main.gameAccounts[sanitized].sessionID then
        ui.sessionId = main.gameAccounts[sanitized].sessionID
    end
    ui.errorText = ""
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT
    return st
end

function pob_importSetSessionId(sid)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    ui.sessionId = (sid or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT
    return st
end

function pob_importRemoveAccountHistory(accountName)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    if accountName and main and main.gameAccounts then
        main.gameAccounts[accountName] = nil
    end
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT
    return st
end

function pob_importSetLeague(league)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    ui.selectedLeague = league or "All"
    ui.selectedCharIndex = 0
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT
    return st
end

function pob_importSetCharacter(index)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    ui.selectedCharIndex = tonumber(index) or 0
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT
    return st
end

local function fetchOAuthCharactersInternal()
    local api = ensureApi()
    if not api or not api.authToken then
        ui.errorText = "Sign in with Path of Exile first."
        emitSignal("import")
        return false
    end
    local realm = findRealm(ui.realmId)
    ui.busy = true
    ui.busyStep = "Fetching characters from Path of Exile..."
    ui.errorText = ""
    ui.statusText = ""

    api:DownloadCharacterList(realm.realmCode, function(body, err, timeNext)
        ui.busy = false
        ui.busyStep = ""
        if not err and body and body.characters then
            ui.oauthCharacters[realm.realmCode] = body.characters
            ui.selectedCharIndex = 0
            ui.errorText = ""
            ui.statusText = s_format("Loaded %d characters (%s).", #body.characters, realm.label)
        elseif err == "Response code: 429" then
            ui.rateLimitEndTime = timeNext or (os.time() + 10)
            ui.errorText = "Rate limited by Path of Exile API. Please wait a few seconds."
        elseif err and tostring(err):match("401") then
            api:ResetDetails()
            ui.errorText = "Your Path of Exile session expired. Please authorize again."
        else
            ui.errorText = "Could not fetch characters: " .. tostring(err or "invalid response")
        end
        emitSignal("import")
    end)
    return true
end

function pob_importOAuthStart()
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    local api = ensureApi()
    if not api then return fail("PoEAPI unavailable") end

    -- Snapshot existing subscript IDs so we can capture the new LaunchServer ID for cancel
    local beforeIds = {}
    if launch and launch.subScripts then
        for id, _ in pairs(launch.subScripts) do
            beforeIds[id] = true
        end
    end

    ui.busy = true
    ui.busyStep = "Waiting for browser sign-in..."
    ui.errorText = ""
    ui.statusText = "Waiting for browser sign-in... (URL copied to clipboard)"
    ui.oauthStartedAt = os.time()
    it.oauthTimer = ui.oauthStartedAt

    api:FetchAuthToken(function(errCode)
        ui.oauthStartedAt = nil
        ui.oauthSubScriptId = nil
        it.oauthTimer = nil
        if errCode then
            ui.busy = false
            ui.busyStep = ""
            ui.errorText = "Sign-in failed: " .. tostring(errCode)
            ui.statusText = ""
            emitSignal("import")
        else
            ui.errorText = ""
            ui.statusText = "Signed in with Path of Exile. Fetching characters..."
            emitSignal("import")
            fetchOAuthCharactersInternal()
        end
    end)

    if launch and launch.subScripts then
        for id, _ in pairs(launch.subScripts) do
            if not beforeIds[id] then
                ui.oauthSubScriptId = id
                break
            end
        end
    end

    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT_NET
    return st
end

function pob_importOAuthCancel()
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    if ui.oauthSubScriptId then
        if AbortSubScript then
            pcall(AbortSubScript, ui.oauthSubScriptId)
        end
        if launch and launch.subScripts then
            launch.subScripts[ui.oauthSubScriptId] = nil
        end
        ui.oauthSubScriptId = nil
    end
    ui.oauthStartedAt = nil
    it.oauthTimer = nil
    ui.busy = false
    ui.busyStep = ""
    ui.errorText = ""
    ui.statusText = "Sign-in cancelled."
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT_NET
    return st
end

function pob_importOAuthLogout()
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    local api = ensureApi()
    if api then
        api:ResetDetails()
    end
    ui.oauthCharacters = {}
    if it.characterList then
        it.characterList = {}
    end
    ui.oauthStartedAt = nil
    ui.oauthSubScriptId = nil
    ui.selectedCharIndex = 0
    ui.busy = false
    ui.busyStep = ""
    ui.errorText = ""
    ui.statusText = "Signed out of Path of Exile."
    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT
    return st
end

local function fetchAccountCharactersInternal(it)
    local realm = findRealm(ui.realmId)
    if not isValidAccountName(ui.accountName) then
        ui.errorText = "Account name must include the #1234 discriminator."
        return false
    end

    local accountName
    if realm.realmCode == "pc" then
        accountName = ui.accountName:gsub("%s+", "")
    else
        accountName = ui.accountName:gsub("^[%s?]+", ""):gsub("[%s?]+$", ""):gsub("%s", "+")
    end
    accountName = accountName:gsub("(.*)[#%-]", "%1#")

    ui.busy = true
    ui.busyStep = "Fetching character list..."
    ui.errorText = ""
    ui.statusText = ""

    local reqOpts = nil
    if ui.sessionId and #ui.sessionId > 0 then
        reqOpts = { header = "Cookie: POESESSID=" .. ui.sessionId }
    end

    local listUrl = realm.hostName .. "character-window/get-characters?accountName="
        .. accountName:gsub("#", "%%23") .. "&realm=" .. realm.realmCode

    launch:DownloadPage(listUrl, function(response, errMsg)
        if errMsg == "Response code: 401" or errMsg == "Response code: 403" then
            ui.busy = false
            ui.busyStep = ""
            ui.errorText = "Account profile is private or does not exist. Make it public, sign in with Path of Exile, or provide a POESESSID."
            emitSignal("import")
            return
        elseif errMsg == "Response code: 404" then
            ui.busy = false
            ui.busyStep = ""
            ui.errorText = "Account name not found. Check spelling and the #1234 discriminator."
            emitSignal("import")
            return
        elseif errMsg then
            ui.busy = false
            ui.busyStep = ""
            ui.errorText = "Could not retrieve character list: " .. tostring(errMsg):gsub("\n", " ")
            emitSignal("import")
            return
        end

        local charList, parseErr = dkjson.decode(response and response.body or "")
        if type(charList) ~= "table" then
            charList, parseErr = it:ProcessSiteJSON(response and response.body or "")
        end
        if type(charList) ~= "table" then
            ui.busy = false
            ui.busyStep = ""
            ui.errorText = "Could not read character list response: " .. tostring(parseErr or "invalid JSON")
            emitSignal("import")
            return
        end
        if #charList == 0 then
            ui.busy = false
            ui.busyStep = ""
            ui.errorText = "This account has no characters to import."
            emitSignal("import")
            return
        end

        -- Profile-page scrape to normalize account name casing (mirrors ImportTab.lua)
        ui.busyStep = "Verifying account profile..."
        emitSignal("import")

        local profileUrl = realm.hostName .. realm.profileURL .. accountName:gsub("#", "%%23")
        launch:DownloadPage(profileUrl, function(profResp, profErr)
            ui.busy = false
            ui.busyStep = ""

            local resolvedName = accountName
            if not profErr and profResp and profResp.body then
                local matched = profResp.body:match("/view%-profile/([^/]+)/characters")
                if matched then
                    matched = matched:gsub(".", function(c)
                        if c:byte(1) > 127 then
                            return s_format("%%%2X", c:byte(1))
                        end
                        return c
                    end)
                    resolvedName = matched:gsub("(.*)[#%-]", "%1#")
                end
            end

            ui.accountName = resolvedName
            if it and it.controls and it.controls.siteAccountName then
                it.controls.siteAccountName:SetText(resolvedName)
            end
            ui.accountCharacters[realm.realmCode] = charList
            ui.accountFetchedFor[realm.realmCode] = resolvedName
            ui.selectedCharIndex = 0

            if main then
                main.lastRealm = realm.id
                main.lastAccountName = resolvedName
                main.gameAccounts = main.gameAccounts or {}
                main.gameAccounts[resolvedName] = main.gameAccounts[resolvedName] or {}
                if ui.sessionId and #ui.sessionId > 0 then
                    main.gameAccounts[resolvedName].sessionID = ui.sessionId
                end
            end
            if it then
                it.lastRealm = realm.id
                if common and common.sha1 then
                    it.lastAccountHash = common.sha1(resolvedName)
                end
            end

            ui.errorText = ""
            ui.statusText = s_format("Loaded %d characters for %s (%s).", #charList, resolvedName, realm.label)
            emitSignal("import")
        end, reqOpts)
    end, reqOpts)

    return true
end

function pob_importFetchCharacters()
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    if ui.busy then return fail("Another operation is in progress.") end

    if ui.authMethod == "oauth" then
        if not fetchOAuthCharactersInternal() then
            local st = buildStateSnapshot()
            st._emit = EMIT_IMPORT
            return st
        end
    else
        if not fetchAccountCharactersInternal(it) then
            local st = buildStateSnapshot()
            st._emit = EMIT_IMPORT
            return st
        end
    end

    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT_NET
    return st
end

-- ============================================================================
-- PART 11.3 — CHARACTER IMPORT PIPELINE
-- ============================================================================

function pob_importSetOptions(opts)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    if type(opts) ~= "table" then return fail("Expected options table") end

    if opts.importTree ~= nil then ui.importTree = (opts.importTree == true) end
    if opts.importItems ~= nil then ui.importItems = (opts.importItems == true) end
    if opts.targetMode == "new" or opts.targetMode == "overwrite" then
        ui.targetMode = opts.targetMode
    end
    if opts.deleteJewels ~= nil then ui.deleteJewels = (opts.deleteJewels == true) end
    if opts.deleteSkills ~= nil then ui.deleteSkills = (opts.deleteSkills == true) end
    if opts.deleteEquipment ~= nil then ui.deleteEquipment = (opts.deleteEquipment == true) end
    if opts.ignoreWeaponSwap ~= nil then ui.ignoreWeaponSwap = (opts.ignoreWeaponSwap == true) end

    -- Sync legacy checkboxes on importTab
    if it.controls then
        if it.controls.charImportTreeClearJewels then it.controls.charImportTreeClearJewels.state = ui.deleteJewels end
        if it.controls.siteCharImportTreeClearJewels then it.controls.siteCharImportTreeClearJewels.state = ui.deleteJewels end
        if it.controls.charImportItemsClearSkills then it.controls.charImportItemsClearSkills.state = ui.deleteSkills end
        if it.controls.siteCharImportItemsClearSkills then it.controls.siteCharImportItemsClearSkills.state = ui.deleteSkills end
        if it.controls.charImportItemsClearItems then it.controls.charImportItemsClearItems.state = ui.deleteEquipment end
        if it.controls.siteCharImportItemsClearItems then it.controls.siteCharImportItemsClearItems.state = ui.deleteEquipment end
        if it.controls.charImportItemsIgnoreWeaponSwap then it.controls.charImportItemsIgnoreWeaponSwap.state = ui.ignoreWeaponSwap end
        if it.controls.siteCharImportItemsIgnoreWeaponSwap then it.controls.siteCharImportItemsIgnoreWeaponSwap.state = ui.ignoreWeaponSwap end
    end

    local st = buildStateSnapshot()
    st._emit = EMIT_IMPORT
    return st
end

local function applyCharacterToBuild(charData, charName, realm, league, doTree, doItems)
    local bm = main and main.modes and main.modes.BUILD
    if not bm then return false, "Build mode unavailable." end

    -- Default target = new build named after the character
    if ui.targetMode == "new" then
        bm:Shutdown()
        bm:Init(false, charName, nil, false)
    end

    local targetIt = bm.importTab
    if not targetIt then return false, "ImportTab unavailable after build init." end

    if main then
        main.lastRealm = realm.id
        main.lastLeague = league
        if common and common.sha1 then
            main.lastCharacterHash = common.sha1(charName)
        end
    end
    targetIt.lastRealm = realm.id
    targetIt.lastLeague = league
    if common and common.sha1 then
        targetIt.lastCharacterHash = common.sha1(charName)
    end

    if doTree and charData.passives then
        targetIt:ImportPassiveTreeAndJewels(charData, ui.deleteJewels)
    end
    if doItems and charData.equipment then
        targetIt:ImportItemsAndSkills(charData, ui.deleteEquipment, ui.deleteSkills, ui.ignoreWeaponSwap)
    end

    bm.buildFlag = true
    return true
end

function pob_importExecuteCharacter(confirmed)
    local bm, it = importCtx()
    if not bm or not it then return fail("importTab unavailable") end
    if ui.busy then return fail("Another import operation is in progress.") end

    local realm = findRealm(ui.realmId)
    local lastCharHash = (it and it.lastCharacterHash) or (main and main.lastCharacterHash)
    local _, chars = buildLeaguesAndChars(realm.realmCode, lastCharHash)
    local picked = (ui.selectedCharIndex >= 1 and ui.selectedCharIndex <= #chars) and chars[ui.selectedCharIndex] or nil
    if not picked then
        return fail("Select a character to import first.")
    end
    if not ui.importTree and not ui.importItems then
        return fail("Choose at least Passive Tree & Jewels or Items & Skills to import.")
    end

    local doTree = ui.importTree
    local doItems = ui.importItems

    -- Explicit confirmation when overwriting the currently open build
    if ui.targetMode == "overwrite" and confirmed ~= true then
        local parts = {}
        if doTree then t_insert(parts, "Passive Tree & Jewels") end
        if doItems then t_insert(parts, "Items & Skills") end
        return {
            ok = false,
            needsConfirm = true,
            confirmTitle = "Overwrite Current Build?",
            confirmMessage = s_format(
                "Importing \"%s\" into \"%s\" will overwrite: %s.",
                picked.name,
                bm.buildName or "Unnamed build",
                table.concat(parts, " and ")
            ),
        }
    end

    local charRaw = picked.raw
    local charName = picked.name
    local charLeague = picked.league

    if ui.authMethod == "oauth" then
        local api = ensureApi()
        if not api or not api.authToken then
            return fail("Sign in with Path of Exile first.")
        end
        ui.busy = true
        ui.busyStep = "Downloading " .. charName .. "... 1 of 2"
        ui.errorText = ""
        ui.statusText = ""

        api:DownloadCharacter(realm.realmCode, charName, function(data, errMsg)
            if not data or not data.character then
                ui.busy = false
                ui.busyStep = ""
                ui.errorText = "Could not import " .. charName .. ": " .. tostring(errMsg or "empty response")
                emitSignal("import")
                return
            end
            ui.busyStep = "Applying character data... 2 of 2"
            emitSignal("import")

            local okApply, errApply = applyCharacterToBuild(data.character, charName, realm, charLeague, doTree, doItems)
            ui.busy = false
            ui.busyStep = ""
            if not okApply then
                ui.errorText = errApply
                emitSignal("import")
                return
            end
            ui.errorText = ""
            ui.statusText = ui.targetMode == "new"
                and s_format("Imported %s into a new build.", charName)
                or s_format("Imported %s into the current build.", charName)
            emitList(EMIT_IMPORT_CHAR)
        end)

        local st = buildStateSnapshot()
        st._emit = EMIT_IMPORT_NET
        return st
    else
        -- Account-name import (1 or 2 HTTP requests depending on checkboxes)
        local accountName = ui.accountName
        local reqOpts = (ui.sessionId and #ui.sessionId > 0)
            and { header = "Cookie: POESESSID=" .. ui.sessionId }
            or nil
        local totalSteps = (doTree and 1 or 0) + (doItems and 1 or 0)
        local combined = copyTable(charRaw)

        local function finishAccountImport()
            local okApply, errApply = applyCharacterToBuild(combined, charName, realm, charLeague, doTree, doItems)
            ui.busy = false
            ui.busyStep = ""
            if not okApply then
                ui.errorText = errApply
                emitSignal("import")
                return
            end
            ui.errorText = ""
            ui.statusText = ui.targetMode == "new"
                and s_format("Imported %s into a new build.", charName)
                or s_format("Imported %s into the current build.", charName)
            emitList(EMIT_IMPORT_CHAR)
        end

        local function fetchItemsStep(stepNum)
            ui.busyStep = s_format("Importing items and skills... %d of %d", stepNum, totalSteps)
            emitSignal("import")
            local itemsUrl = realm.hostName .. "character-window/get-items?accountName="
                .. accountName:gsub("#", "%%23") .. "&character=" .. urlEncode(charName) .. "&realm=" .. realm.realmCode
            launch:DownloadPage(itemsUrl, function(response, errMsg)
                if errMsg or not response or response.body == "false" then
                    ui.busy = false
                    ui.busyStep = ""
                    ui.errorText = "Failed to download items: " .. tostring(errMsg or "empty response")
                    emitSignal("import")
                    return
                end
                local parsed = dkjson.decode(response.body)
                if type(parsed) ~= "table" then
                    ui.busy = false
                    ui.busyStep = ""
                    ui.errorText = "Failed to parse items response."
                    emitSignal("import")
                    return
                end
                combined.equipment = parsed.items or {}
                combined.guardian = parsed.guardian
                finishAccountImport()
            end, reqOpts)
        end

        ui.busy = true
        ui.errorText = ""
        ui.statusText = ""

        if doTree then
            ui.busyStep = s_format("Importing passive tree... 1 of %d", totalSteps)
            local treeUrl = realm.hostName .. "character-window/get-passive-skills?accountName="
                .. accountName:gsub("#", "%%23") .. "&character=" .. urlEncode(charName) .. "&realm=" .. realm.realmCode
            launch:DownloadPage(treeUrl, function(response, errMsg)
                if errMsg or not response or response.body == "false" then
                    ui.busy = false
                    ui.busyStep = ""
                    ui.errorText = "Failed to download passive tree: " .. tostring(errMsg or "empty response")
                    emitSignal("import")
                    return
                end
                local parsed = dkjson.decode(response.body)
                if type(parsed) ~= "table" then
                    ui.busy = false
                    ui.busyStep = ""
                    ui.errorText = "Failed to parse passive tree response."
                    emitSignal("import")
                    return
                end
                -- Account-name imports omit quest choices, preserve current build values
                local curBm = main and main.modes and main.modes.BUILD
                if curBm and curBm.configTab and curBm.configTab.input then
                    parsed.bandit_choice = parsed.bandit_choice or curBm.configTab.input.bandit
                    parsed.pantheon_major = parsed.pantheon_major or curBm.configTab.input.pantheonMajorGod
                    parsed.pantheon_minor = parsed.pantheon_minor or curBm.configTab.input.pantheonMinorGod
                end
                combined.passives = parsed
                combined.jewels = parsed.items or {}
                if doItems then
                    fetchItemsStep(2)
                else
                    finishAccountImport()
                end
            end, reqOpts)
        else
            fetchItemsStep(1)
        end

        local st = buildStateSnapshot()
        st._emit = EMIT_IMPORT_NET
        return st
    end
end

-- ============================================================================
-- SELFTESTS (Phase 11)
-- ============================================================================

local function resetUiStateForTest()
    ui.authMethod = "oauth"
    ui.realmId = "PC"
    ui.accountName = ""
    ui.sessionId = ""
    ui.selectedLeague = "All"
    ui.selectedCharIndex = 0
    ui.importTree = true
    ui.importItems = true
    ui.targetMode = "new"
    ui.deleteJewels = true
    ui.deleteSkills = true
    ui.deleteEquipment = true
    ui.ignoreWeaponSwap = false
    ui.busy = false
    ui.busyStep = ""
    ui.statusText = ""
    ui.errorText = ""
    ui.oauthSubScriptId = nil
    ui.oauthStartedAt = nil
    ui.rateLimitEndTime = nil
    ui.oauthCharacters = {}
    ui.accountCharacters = {}
    ui.accountFetchedFor = {}
    ui.shareCode = ""
    ui.shareSiteId = nil
    ui.shareBusy = false
    ui.shareStatus = ""
    ui.shareError = ""
    ui.openInput = ""
    ui.openValid = false
    ui.openKind = "none"
    ui.openSiteIndex = nil
    ui.openSiteLabel = ""
    ui.openDetail = ""
    ui.openXML = nil
    ui.openJson = nil
    ui.openMode = "new"
    ui.openFetching = false
    ui.openStatus = ""
    ui.openError = ""
end

function pob_selftestImportShare()
    local res = { ok = false }
    local bm, it = importCtx()
    if not bm or not it then
        res.error = "importTab unavailable"
        return res
    end

    local origXml = bm:SaveDB("code")
    local origName = bm.buildName
    local origFile = bm.dbFileName
    local origView = bm.viewMode
    local origUpload = buildSites.UploadBuild
    local origDownload = buildSites.DownloadBuild
    local origReg = launch.RegisterSubScript

    local okRun, errRun = pcall(function()
        resetUiStateForTest()

        -- 1. Generate share code
        local gen = pob_importGenerateCode()
        res.generateOk = gen.ok and gen.share and type(gen.share.code) == "string" and #gen.share.code > 20
        local code = gen.share and gen.share.code or ""

        -- 2. Validate round-trip code
        local valGood = pob_importValidateInput(code)
        res.validateGoodOk = valGood.ok and valGood.open.valid == true and valGood.open.kind == "code"

        -- 3. Refuse invalid code
        local valBad = pob_importValidateInput("!!!not-a-valid-pob-code!!!")
        res.validateBadRefusedOk = valBad.ok and valBad.open.valid == false and valBad.open.canImport == false
            and #(valBad.open.importDisabledReason or "") > 0

        -- 4. YouTube redirect unwrap + site recognition
        local yt = pob_importValidateInput("https://www.youtube.com/redirect?q=https%3A%2F%2Fpobb.in%2Ftest12345")
        res.redirectUnwrapOk = yt.ok and yt.open.valid == true and yt.open.kind == "url"
            and yt.open.siteLabel == "pobb.in" and yt.open.input == "https://pobb.in/test12345"

        -- 5. Export site provider list
        local hasPobbin = false
        for _, s in ipairs(gen.share.sites or {}) do
            if s.id == "POBBin" then hasPobbin = true end
        end
        res.siteProvidersOk = #(gen.share.sites or {}) >= 4 and hasPobbin

        -- 6. Mocked upload
        local capturedCb
        buildSites.UploadBuild = function(c, site)
            return 99901
        end
        launch.RegisterSubScript = function(self, id, cb)
            capturedCb = cb
        end
        pob_importSetShareSite("POBBin")
        local upStart = pob_importUploadBuild("POBBin")
        res.uploadStartOk = upStart.ok and upStart.share.busy == true and type(capturedCb) == "function"
        if capturedCb then
            capturedCb("selftestPasteId", nil)
        end
        local upDone = pob_importGetState()
        res.uploadDoneOk = upDone.ok and upDone.share.busy == false
            and upDone.share.code == "https://pobb.in/selftestPasteId"
            and upDone.share.isLink == true and upDone.share.canUpload == false

        -- 7. Mocked URL download + overwrite confirm guard + open as new build
        buildSites.DownloadBuild = function(link, site, cb)
            cb(true, code, link)
        end
        pob_importValidateInput("https://pobb.in/selftestPasteId")
        pob_importSetOpenMode("overwrite")
        local needConf = pob_importOpenBuild(false)
        res.overwriteConfirmOk = needConf.ok == false and needConf.needsConfirm == true

        pob_importSetOpenMode("new")
        local openRes = pob_importOpenBuild(false)
        res.mockedFetchOpenOk = openRes.ok == true and main.modes.BUILD.buildName == "Imported build"

        -- 8. Export Support checkbox
        local ep = pob_importSetExportParty(true)
        res.exportPartyOk = ep.ok and ep.share.exportParty == true and main.modes.BUILD.partyTab.enableExportBuffs == true
    end)

    -- Restore mocks and original build
    buildSites.UploadBuild = origUpload
    buildSites.DownloadBuild = origDownload
    launch.RegisterSubScript = origReg
    if main and main.modes and main.modes.BUILD and origXml then
        main.modes.BUILD:Shutdown()
        main.modes.BUILD:Init(origFile, origName, origXml, false)
        main.modes.BUILD.viewMode = origView
    end
    resetUiStateForTest()

    if not okRun then
        res.error = tostring(errRun)
        res.ok = false
        return res
    end

    res.ok = (res.generateOk == true) and (res.validateGoodOk == true) and (res.validateBadRefusedOk == true)
        and (res.redirectUnwrapOk == true) and (res.siteProvidersOk == true) and (res.uploadStartOk == true)
        and (res.uploadDoneOk == true) and (res.overwriteConfirmOk == true) and (res.mockedFetchOpenOk == true)
        and (res.exportPartyOk == true)
    return res
end

function pob_selftestImportPipeline()
    local res = { ok = false }
    local bm, it = importCtx()
    if not bm or not it then
        res.error = "importTab unavailable"
        return res
    end

    local origXml = bm:SaveDB("code")
    local origName = bm.buildName
    local origFile = bm.dbFileName
    local origView = bm.viewMode

    local okRun, errRun = pcall(function()
        resetUiStateForTest()

        -- Pick 2 real adjacent passive nodes from the Witch starting area
        local tree = bm.spec.tree
        local witchStartId = tree.classes[3] and tree.classes[3].startNodeId
        local hashes = {}
        if witchStartId and tree.nodes[witchStartId] then
            for _, linkedId in ipairs(tree.nodes[witchStartId].linkedId or {}) do
                local node = tree.nodes[linkedId]
                if node and node.type == "Normal" and not node.ascendancyName then
                    t_insert(hashes, linkedId)
                    if #hashes >= 2 then break end
                end
            end
        end

        local fixtureChar = {
            name = "SelftestWitch",
            realm = "pc",
            class = "Witch",
            league = "Standard",
            level = 85,
            experience = 1000000,
            passives = {
                hashes = hashes,
                hashes_ex = {},
                mastery_effects = {},
                jewel_data = {},
                skill_overrides = {},
                bandit_choice = "Alira",
                pantheon_major = "Solaris",
                pantheon_minor = "Shakari",
            },
            jewels = {},
            equipment = {
                {
                    id = "selftest-body-1",
                    inventoryId = "BodyArmour",
                    frameType = 2,
                    name = "Fate Shroud",
                    typeLine = "Vaal Regalia",
                    ilvl = 84,
                    sockets = {
                        { group = 0, sColour = "B" },
                        { group = 0, sColour = "B" },
                    },
                    socketedItems = {
                        {
                            socket = 0,
                            typeLine = "Fireball",
                            support = false,
                            properties = {
                                { name = "Level", values = { { "20", 0 } } },
                                { name = "Quality", values = { { "+20%", 1 } } },
                            },
                        },
                        {
                            socket = 1,
                            typeLine = "Arcane Surge Support",
                            support = true,
                            properties = {
                                { name = "Level", values = { { "20", 0 } } },
                                { name = "Quality", values = { { "+0%", 0 } } },
                            },
                        },
                    },
                    explicitMods = {
                        "+80 to maximum Energy Shield",
                        "+40 to maximum Life",
                    },
                },
                {
                    id = "selftest-ring-1",
                    inventoryId = "Ring",
                    frameType = 2,
                    name = "Doom Band",
                    typeLine = "Coral Ring",
                    ilvl = 80,
                    implicitMods = { "+25 to maximum Life" },
                    explicitMods = { "+55 to maximum Life", "+30% to Fire Resistance" },
                },
            },
        }

        -- Import passive tree & jewels
        it:ImportPassiveTreeAndJewels(fixtureChar, true)
        res.treeAllocCount = select(1, bm.spec:CountAllocNodes())
        res.treeOk = res.treeAllocCount >= #hashes and #hashes > 0
            and bm.characterLevel == 85
            and bm.configTab.input.bandit == "Alira"

        -- Import items & skills
        it:ImportItemsAndSkills(fixtureChar, true, true, false)
        local bodyId = bm.itemsTab.slots["Body Armour"] and bm.itemsTab.slots["Body Armour"].selItemId or 0
        local ringId = bm.itemsTab.slots["Ring 1"] and bm.itemsTab.slots["Ring 1"].selItemId or 0
        res.itemsOk = bodyId ~= 0 and ringId ~= 0
        res.skillGroupCount = #bm.skillsTab.socketGroupList
        res.skillsOk = res.skillGroupCount >= 1
            and bm.skillsTab.socketGroupList[1].gemList
            and #bm.skillsTab.socketGroupList[1].gemList == 2

        -- Mutate socket group state, then re-import with clearSkills=true to verify preservation
        local sg = bm.skillsTab.socketGroupList[1]
        sg.label = "PreservedMainLabel"
        sg.enabled = false
        sg.includeInFullDPS = true

        it:ImportItemsAndSkills(fixtureChar, true, true, false)
        local sgAfter = bm.skillsTab.socketGroupList[1]
        res.reimportPreservedOk = sgAfter ~= nil
            and sgAfter.label == "PreservedMainLabel"
            and sgAfter.enabled == false
            and sgAfter.includeInFullDPS == true
    end)

    -- Clean restore
    if main and main.modes and main.modes.BUILD and origXml then
        main.modes.BUILD:Shutdown()
        main.modes.BUILD:Init(origFile, origName, origXml, false)
        main.modes.BUILD.viewMode = origView
    end
    resetUiStateForTest()

    if not okRun then
        res.error = tostring(errRun)
        res.ok = false
        return res
    end

    res.ok = (res.treeOk == true) and (res.itemsOk == true)
        and (res.skillsOk == true) and (res.reimportPreservedOk == true)
    return res
end

function pob_selftestImportAccountFlow()
    local res = { ok = false }
    local bm, it = importCtx()
    if not bm or not it then
        res.error = "importTab unavailable"
        return res
    end

    local api = ensureApi()
    local origToken = api.authToken
    local origRefresh = api.refreshToken
    local origExpiry = api.tokenExpiry
    local origDownloadPage = launch.DownloadPage
    local origLaunchSub = LaunchSubScript
    local origAbortSub = AbortSubScript
    local origSaveSettings = main.SaveSettings
    local origEmit = pob and pob.emitSignal
    local origLastAccount = main.lastAccountName
    local origLastRealm = main.lastRealm
    local origAccounts = copyTable(main.gameAccounts or {})

    local emitCount = 0
    local abortedId = nil

    local okRun, errRun = pcall(function()
        resetUiStateForTest()
        main.SaveSettings = function() end
        if pob then
            pob.emitSignal = function(sig)
                if sig == "import" then emitCount = emitCount + 1 end
                if origEmit then origEmit(sig) end
            end
        end

        -- 1. OAuth start & cancel
        LaunchSubScript = function() return 88801 end
        AbortSubScript = function(id) abortedId = id end
        api.authToken = nil
        api.refreshToken = nil
        api.tokenExpiry = nil

        local stStart = pob_importOAuthStart()
        res.oauthStartOk = stStart.ok and stStart.oauthWaiting == true and stStart.busy == true

        local stCancel = pob_importOAuthCancel()
        res.oauthCancelOk = stCancel.ok and abortedId == 88801 and stCancel.oauthWaiting == false and stCancel.busy == false

        -- 2. OAuth authenticated -> fetch characters -> rate limit -> logout
        api.authToken = "mock-access-token"
        api.refreshToken = "mock-refresh-token"
        api.tokenExpiry = os.time() + 3600

        launch.DownloadPage = function(self, url, cb, opts)
            if url:find("/character", 1, true) then
                cb({
                    header = "HTTP/1.1 200 OK\r\n",
                    body = dkjson.encode({
                        characters = {
                            { name = "OAuthRanger", realm = "pc", class = "Deadeye", league = "Standard", level = 94 },
                            { name = "OAuthWitch", realm = "pc", class = "Elementalist", league = "Settlers", level = 98 },
                        }
                    })
                }, nil)
            else
                cb(nil, "Unexpected URL: " .. tostring(url))
            end
        end

        pob_importFetchCharacters()
        local stOAuthChars = pob_importGetState()
        res.oauthFetchOk = stOAuthChars.ok and #(stOAuthChars.characters or {}) == 2
            and #(stOAuthChars.leagues or {}) == 3 and emitCount >= 1

        -- 3. OAuth logout resets token and list
        local stLogout = pob_importOAuthLogout()
        res.oauthLogoutOk = stLogout.ok and stLogout.oauthAuthorized == false and #(stLogout.characters or {}) == 0

        -- 4. Account-name validation (missing discriminator refused with reason)
        pob_importSetAuthMethod("account")
        local stBadAcct = pob_importSetAccountName("NoDiscriminator")
        res.badAccountRefusedOk = stBadAcct.ok and stBadAcct.accountNameValid == false
            and stBadAcct.canFetchCharacters == false and #(stBadAcct.fetchDisabledReason or "") > 0

        -- 5. Account-name 403 private error handling
        pob_importSetAccountName("PrivateUser#1234")
        launch.DownloadPage = function(self, url, cb, opts)
            cb(nil, "Response code: 403")
        end
        pob_importFetchCharacters()
        local stPriv = pob_importGetState()
        res.privateErrorOk = stPriv.ok and stPriv.busy == false
            and stPriv.errorText:lower():find("private", 1, true) ~= nil

        -- 6. Account-name success flow (get-characters + profile case scrape)
        pob_importSetAccountName("publicuser#4321")
        launch.DownloadPage = function(self, url, cb, opts)
            if url:find("get-characters", 1, true) then
                cb({
                    body = dkjson.encode({
                        { name = "PublicDuelist", realm = "pc", class = "Slayer", league = "Standard", level = 92 },
                    })
                }, nil)
            elseif url:find("view-profile", 1, true) then
                cb({
                    body = '<a href="/account/view-profile/PublicUser-4321/characters">Chars</a>'
                }, nil)
            else
                cb(nil, "Unexpected URL: " .. tostring(url))
            end
        end
        pob_importFetchCharacters()
        local stPub = pob_importGetState()
        res.accountFetchOk = stPub.ok and stPub.busy == false and stPub.errorText == ""
            and stPub.accountName == "PublicUser#4321"
            and #(stPub.characters or {}) == 1
            and stPub.characters[1].name == "PublicDuelist"
            and stPub.canImportCharacter == true
    end)

    -- Restore everything cleanly
    launch.DownloadPage = origDownloadPage
    LaunchSubScript = origLaunchSub
    AbortSubScript = origAbortSub
    main.SaveSettings = origSaveSettings
    if pob then pob.emitSignal = origEmit end
    api.authToken = origToken
    api.refreshToken = origRefresh
    api.tokenExpiry = origExpiry
    main.lastAccountName = origLastAccount
    main.lastRealm = origLastRealm
    main.gameAccounts = origAccounts
    resetUiStateForTest()

    if not okRun then
        res.error = tostring(errRun)
        res.ok = false
        return res
    end

    res.ok = (res.oauthStartOk == true) and (res.oauthCancelOk == true)
        and (res.oauthFetchOk == true) and (res.oauthLogoutOk == true)
        and (res.badAccountRefusedOk == true) and (res.privateErrorOk == true)
        and (res.accountFetchOk == true)
    return res
end
