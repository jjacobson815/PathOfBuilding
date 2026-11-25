-- app/lua/pob_network.lua
--
-- Phase 10: Network & Async Foundation helpers and selftests.
-- Auto-loaded by app/lua/pob_host.lua via `pcall(require, "pob_network")`.
--
-- Provides:
--   1. pob:// URI parsing & async build-import helpers (Part 10.3):
--      pob_parsePobUri, pob_importPobUri, pob_handleStartupUri, pob_getUriImportStatus
--   2. Async PoEURL passive-tree resolve & shrink helpers for TreeImportPopup /
--      TreeExportPopup (Part 10.2):
--      pob_resolvePoeUrl, pob_getPoeUrlStatus, pob_shrinkPoeUrl,
--      pob_getShrinkPoeUrlStatus, pob_cancelPoeUrl
--   3. Comprehensive headless selftests (zero external internet access; local
--      loopback HTTP/proxy/TCP servers):
--      pob_selftestSubScript(), pob_selftestNetwork()

local M = { }

-- Trigger SubScriptManager's lazy registration of `pob.processEvents` / `pob.sleepMs`
-- on the main Lua state right at module load time.
if IsSubScriptRunning then
    IsSubScriptRunning(0)
end

local _nextReqId = 1
local _poeUrlRequests = { }
local _uriRequests = { }

local function allocReqId()
    local id = _nextReqId
    _nextReqId = _nextReqId + 1
    return id
end

local function emitSignals(...)
    if pob and pob.emitSignal then
        pob.emitSignal(...)
    end
end

local function pumpUntil(pred, timeoutMs)
    timeoutMs = timeoutMs or 5000
    local t0 = GetTime and GetTime() or 0
    while not pred() do
        if pob and pob.processEvents then
            pob.processEvents(10)
        end
        if pred() then
            return true
        end
        local now = GetTime and GetTime() or (t0 + timeoutMs)
        if (now - t0) >= timeoutMs then
            return pred() and true or false
        end
        if pob and pob.sleepMs then
            pob.sleepMs(2)
        end
    end
    return true
end

-- Decode either a PoB base64url+deflate share code or raw `<PathOfBuilding>` XML.
local function decodeBuildPayload(payload)
    if type(payload) ~= "string" then
        return nil, "Empty build payload"
    end
    local trimmed = payload:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then
        return nil, "Empty build payload"
    end
    if trimmed:find("<PathOfBuilding", 1, true) then
        return trimmed, nil
    end
    if not common or not common.base64 or not common.base64.decode then
        return nil, "base64 decoder unavailable"
    end
    local b64 = trimmed:gsub("%s+", ""):gsub("%-", "+"):gsub("_", "/")
    local pad = #b64 % 4
    if pad == 2 then b64 = b64 .. "=="
    elseif pad == 3 then b64 = b64 .. "="
    end
    local okDec, compressed = pcall(common.base64.decode, b64)
    if not okDec or type(compressed) ~= "string" or #compressed == 0 then
        return nil, "Invalid build code encoding"
    end
    local okInf, xmlText = pcall(Inflate, compressed)
    if not okInf or type(xmlText) ~= "string" or not xmlText:find("<PathOfBuilding", 1, true) then
        return nil, "Invalid or corrupt compressed build data"
    end
    return xmlText, nil
end

local function activateImportedBuildXml(xmlText, buildName, importLink)
    if not main or not main.SetMode then
        return false, "Engine main object unavailable"
    end
    main:SetMode("BUILD", false, buildName or "Imported Build", xmlText, false, importLink)
    main.newModeChangeToTree = true
    -- Qt host has no frame timer: drive OnFrame immediately to realise SetMode,
    -- then run a recalculation pass and emit model change signals.
    if runCallback then
        runCallback("OnFrame")
    end
    if pob_recalculate then
        pob_recalculate()
    end
    emitSignals("build", "tree", "items", "skills", "config", "notes",
                "party", "compare", "import", "network", "mode", "calcs")
    return true, nil
end

-- ============================================================================
-- Part 10.3: pob:// URI parsing & startup / runtime import helpers
-- ============================================================================

function pob_parsePobUri(uri)
    uri = tostring(uri or ""):match("^%s*(.-)%s*$") or ""
    if uri == "" then
        return { ok = false, error = "Empty URI" }
    end
    if not buildSites or not buildSites.websiteList then
        return { ok = false, error = "BuildSiteTools unavailable" }
    end
    local importLink = buildSites.ParseImportLinkFromURI and buildSites.ParseImportLinkFromURI(uri) or nil
    local siteId, siteLabel, downloadUrl
    for _, siteInfo in ipairs(buildSites.websiteList) do
        local pat = "^[pP][oO][bB]:[/\\]*" .. siteInfo.id:lower() .. "[/\\]+(.+)"
        local lowerHead = uri:sub(1, 4):lower() .. uri:sub(5)
        if lowerHead:lower():match("^pob:[/\\]*" .. siteInfo.id:lower() .. "[/\\]+(.+)") then
            -- Match case-insensitively on scheme + provider id while preserving the build id's case!
            local idPart = uri:match("^[pP][oO][bB]:[/\\]*[^/\\]+[/\\]+(.+)$")
            if idPart and idPart ~= "" then
                local normalized = "pob://" .. siteInfo.id:lower() .. "/" .. idPart
                importLink = normalized:gsub("^pob:[/\\]*" .. siteInfo.id:lower() .. "[/\\]+(.+)", "https://" .. siteInfo.linkURL)
                downloadUrl = normalized:gsub("^pob:[/\\]*" .. siteInfo.id:lower() .. "[/\\]+(.+)", "https://" .. siteInfo.downloadURL)
                siteId = siteInfo.id
                siteLabel = siteInfo.label
                break
            end
        end
        local _ = pat
    end
    if not downloadUrl then
        return { ok = false, uri = uri, error = "Unsupported pob:// provider URI" }
    end
    return {
        ok = true,
        uri = uri,
        siteId = siteId,
        siteLabel = siteLabel,
        importLink = importLink or downloadUrl,
        downloadUrl = downloadUrl,
    }
end

function pob_importPobUri(uri, buildName)
    local parsed = pob_parsePobUri(uri)
    if not parsed.ok then
        return { ok = false, error = parsed.error or "Invalid pob:// URI" }
    end
    if not launch or not launch.DownloadPage then
        return { ok = false, error = "launch:DownloadPage unavailable" }
    end

    local reqId = allocReqId()
    local targetName = (type(buildName) == "string" and buildName:match("%S")) and buildName or "Imported Build"
    local entry = {
        reqId = reqId,
        done = false,
        ok = false,
        uri = parsed.uri,
        importLink = parsed.importLink,
        downloadUrl = parsed.downloadUrl,
        error = "",
    }
    _uriRequests[reqId] = entry

    -- Normalize scheme+siteId to lowercase for BuildSiteTools.DownloadBuild while keeping code case intact.
    local idPart = parsed.uri:match("^[pP][oO][bB]:[/\\]*[^/\\]+[/\\]+(.+)$")
    local normalizedUri = "pob://" .. parsed.siteId:lower() .. "/" .. tostring(idPart or "")

    buildSites.DownloadBuild(normalizedUri, nil, function(isSuccess, bodyOrErr, dlLink)
        if not isSuccess then
            entry.done = true
            entry.ok = false
            entry.error = tostring(bodyOrErr or "Download failed")
            emitSignals("import", "network")
            return
        end
        local xmlText, decErr = decodeBuildPayload(bodyOrErr)
        if not xmlText then
            entry.done = true
            entry.ok = false
            entry.error = tostring(decErr or "Decode failed")
            emitSignals("import", "network")
            return
        end
        local actOk, actErr = activateImportedBuildXml(xmlText, targetName, parsed.importLink or dlLink)
        entry.done = true
        entry.ok = actOk == true
        entry.error = actErr or ""
    end)

    return {
        ok = true,
        reqId = reqId,
        importLink = parsed.importLink,
        downloadUrl = parsed.downloadUrl,
        _emit = { "network" },
    }
end

function pob_handleStartupUri(explicitUri)
    local candidate = explicitUri
    if (not candidate or candidate == "") and type(arg) == "table" and type(arg[1]) == "string" then
        if arg[1]:lower():match("^pob:") then
            candidate = arg[1]
            arg[1] = nil
        end
    end
    if not candidate or candidate == "" then
        return { ok = false, handled = false }
    end
    local r = pob_importPobUri(candidate, "Imported Build")
    r.handled = r.ok == true
    return r
end

function pob_getUriImportStatus(reqId)
    local e = _uriRequests[tonumber(reqId) or 0]
    if not e then
        return { ok = false, done = true, error = "Unknown URI import request" }
    end
    return {
        ok = e.ok,
        done = e.done,
        uri = e.uri,
        importLink = e.importLink,
        downloadUrl = e.downloadUrl,
        error = e.error,
    }
end

-- ============================================================================
-- Part 10.2: Async PoEURL resolve & shrink helpers (TreeImportPopup / TreeExportPopup)
-- ============================================================================

function pob_resolvePoeUrl(treeName, treeLink)
    treeName = tostring(treeName or "")
    treeLink = tostring(treeLink or ""):match("^%s*(.-)%s*$") or ""
    if not treeName:match("%S") or not treeLink:match("%S") then
        return { ok = false, msg = "^1Enter both tree name and PoEURL link^7" }
    end
    if not treeLink:match("poeurl%.com/") then
        return { ok = false, msg = "^1Not a PoEURL link^7" }
    end
    if not treeLink:match("^https?://") then
        treeLink = "http://" .. treeLink
    end

    local reqId = allocReqId()
    local entry = {
        reqId = reqId,
        done = false,
        ok = false,
        cancelled = false,
        ssId = 0,
        index = 0,
        resolvedUrl = "",
        msg = "",
    }
    _poeUrlRequests[reqId] = entry

    local script = [[
        local treeLink, connectionProtocol, proxyURL, noSSL, ver = ...
        local curl = require("lcurl.safe")
        local current = treeLink
        for _ = 1, 3 do
            local easy = curl.easy()
            easy:setopt_url(current)
            easy:setopt(curl.OPT_USERAGENT, "Path of Building/" .. tostring(ver or "2.0"))
            if connectionProtocol then
                easy:setopt(curl.OPT_IPRESOLVE, connectionProtocol)
            end
            if proxyURL then
                easy:setopt(curl.OPT_PROXY, proxyURL)
            end
            if noSSL then
                easy:setopt(curl.OPT_SSL_VERIFYPEER, 0)
                easy:setopt(curl.OPT_SSL_VERIFYHOST, 0)
            end
            easy:setopt_writefunction(function()
                return true
            end)
            local _, err = easy:perform()
            local redirect = easy:getinfo(curl.INFO_REDIRECT_URL)
            easy:close()
            if err then
                return nil, err:msg()
            end
            if not redirect or redirect == "" then
                break
            end
            if not redirect:match("poeurl%.com/") then
                return redirect, nil
            end
            if redirect == current or redirect:match("poeurl%.com/?$") then
                break
            end
            current = redirect
        end
        return nil, "Failed to resolve PoEURL link"
    ]]

    local id = LaunchSubScript(
        script,
        "",
        "",
        treeLink,
        launch and launch.connectionProtocol or nil,
        launch and launch.proxyURL or nil,
        (launch and launch.noSSL) or false,
        (launch and launch.versionNumber) or "2.0"
    )
    if not id or id <= 0 then
        entry.done = true
        entry.ok = false
        entry.msg = "^1Failed to start PoEURL resolver^7"
        return { ok = false, msg = entry.msg }
    end

    entry.ssId = id
    if launch and launch.subScripts then
        launch.subScripts[id] = {
            type = "DOWNLOAD",
            callback = function(resolvedUrl, errMsg)
                if entry.cancelled then return end
                entry.ssId = 0
                if errMsg or type(resolvedUrl) ~= "string" or resolvedUrl == "" then
                    entry.done = true
                    entry.ok = false
                    entry.msg = "^1" .. tostring(errMsg or "Failed to resolve PoEURL link") .. "^7"
                    emitSignals("network")
                    return
                end
                entry.resolvedUrl = resolvedUrl
                local imp = pob_importTree and pob_importTree(treeName, resolvedUrl) or nil
                if imp and imp.ok then
                    entry.done = true
                    entry.ok = true
                    entry.index = tonumber(imp.index) or 0
                    entry.msg = ""
                    emitSignals("build", "tree", "items", "skills", "calcs", "network")
                else
                    entry.done = true
                    entry.ok = false
                    entry.msg = (imp and imp.msg) or "^1Failed to decode resolved tree link^7"
                    emitSignals("network")
                end
            end,
        }
    end

    return { ok = true, reqId = reqId, ssId = id, _emit = { "network" } }
end

function pob_getPoeUrlStatus(reqId)
    local e = _poeUrlRequests[tonumber(reqId) or 0]
    if not e then
        return { ok = false, done = true, msg = "^1PoEURL request not found^7" }
    end
    return {
        ok = e.ok,
        done = e.done,
        index = e.index,
        resolvedUrl = e.resolvedUrl,
        msg = e.msg,
    }
end

function pob_shrinkPoeUrl(treeLink)
    treeLink = tostring(treeLink or ""):match("^%s*(.-)%s*$") or ""
    if treeLink == "" then
        return { ok = false, msg = "^1Passive tree link is empty^7" }
    end
    if not launch or not launch.DownloadPage then
        return { ok = false, msg = "^1Network download unavailable^7" }
    end

    local reqId = allocReqId()
    local entry = {
        reqId = reqId,
        done = false,
        ok = false,
        cancelled = false,
        ssId = 0,
        shortUrl = "",
        msg = "",
    }
    _poeUrlRequests[reqId] = entry

    local shrinkEndpoint = "http://poeurl.com/shrink.php?url=" .. treeLink
    launch:DownloadPage(shrinkEndpoint, function(response, errMsg)
        if entry.cancelled then return end
        local body = (type(response) == "table" and type(response.body) == "string")
            and (response.body:match("^%s*(.-)%s*$") or "")
            or ""
        if errMsg or body == "" or body:find("[<>%s]") then
            entry.done = true
            entry.ok = false
            entry.msg = "^1Failed to get PoEURL link. Try again later.^7"
            emitSignals("network")
            return
        end
        entry.done = true
        entry.ok = true
        entry.shortUrl = "http://poeurl.com/" .. body
        emitSignals("tree", "network")
    end)

    return { ok = true, reqId = reqId, _emit = { "network" } }
end

function pob_getShrinkPoeUrlStatus(reqId)
    local e = _poeUrlRequests[tonumber(reqId) or 0]
    if not e then
        return { ok = false, done = true, msg = "^1PoEURL request not found^7" }
    end
    return {
        ok = e.ok,
        done = e.done,
        shortUrl = e.shortUrl,
        msg = e.msg,
    }
end

function pob_cancelPoeUrl(reqId)
    local e = _poeUrlRequests[tonumber(reqId) or 0]
    if not e then
        return { ok = false }
    end
    e.cancelled = true
    e.done = true
    e.ok = false
    if e.ssId and e.ssId > 0 and AbortSubScript then
        AbortSubScript(e.ssId)
        if launch and launch.subScripts then
            launch.subScripts[e.ssId] = nil
        end
        e.ssId = 0
    end
    return { ok = true }
end

-- ============================================================================
-- Headless Selftest 1: pob_selftestSubScript()
-- Exercises isolated worker Lua states, multi-return + nil preservation, `#@`
-- shebang scripts, funcList sync blocking proxies, subList async OnSubCall,
-- OnSubError, non-blocking UI proof during delayed worker, and AbortSubScript.
-- ============================================================================

function pob_selftestSubScript()
    local res = { ok = false }
    if not LaunchSubScript or not AbortSubScript or not IsSubScriptRunning then
        res.error = "SubScript host globals missing"
        return res
    end
    if not launch or not launch.subScripts then
        res.error = "launch.subScripts table missing"
        return res
    end

    -- 1. Multi-return + nil argument & nil return-slot preservation.
    do
        local done = false
        local r1, r2, r3, r4
        local id = LaunchSubScript([[
            local a, nilArg, b = ...
            assert(a == "hello", "arg1 mismatch")
            assert(nilArg == nil, "nil arg turned non-nil: " .. tostring(type(nilArg)))
            assert(b == 21, "arg3 mismatch")
            return "echo:" .. a, nil, b * 2, { nested = "yes" }
        ]], "", "", "hello", nil, 21)
        launch:RegisterSubScript(id, function(a, b, c, d)
            r1, r2, r3, r4 = a, b, c, d
            done = true
        end)
        local finishedInTime = pumpUntil(function() return done end, 3000)
        res.returnValuesOk = finishedInTime
            and r1 == "echo:hello"
            and r2 == nil
            and r3 == 42
            and type(r4) == "table" and r4.nested == "yes"
            and IsSubScriptRunning(id) == false
    end

    -- 2. `#@` header script compatibility (matches src/UpdateCheck.lua).
    do
        local done = false
        local val = nil
        local id = LaunchSubScript("#@\nlocal x = ...\nreturn x + 5\n", "", "", 37)
        launch:RegisterSubScript(id, function(v)
            val = v
            done = true
        end)
        pumpUntil(function() return done end, 3000)
        res.shebangOk = done and val == 42
    end

    -- 3. funcList synchronous blocking proxy to UI thread + multi-return.
    do
        local done = false
        local sumOut, pathOut
        _G._pob_st_syncAdd = function(x, y)
            return (tonumber(x) or 0) + (tonumber(y) or 0), GetScriptPath()
        end
        local id = LaunchSubScript([[
            local s, p = _pob_st_syncAdd(19, 23)
            local rt = GetRuntimePath()
            local wd = GetWorkDir()
            assert(type(rt) == "string" and #rt > 0, "GetRuntimePath empty")
            assert(type(wd) == "string" and #wd > 0, "GetWorkDir empty")
            return s, p
        ]], "GetScriptPath,GetRuntimePath,GetWorkDir,_pob_st_syncAdd", "")
        launch:RegisterSubScript(id, function(s, p)
            sumOut, pathOut = s, p
            done = true
        end)
        pumpUntil(function() return done end, 3000)
        _G._pob_st_syncAdd = nil
        res.funcListSyncOk = done and sumOut == 42 and pathOut == GetScriptPath()
    end

    -- 4. subList async fire-and-forget -> OnSubCall on UI thread.
    do
        local subCalls = { }
        local done = false
        _G._pob_st_subRecord = function(tag, num)
            subCalls[#subCalls + 1] = tostring(tag) .. ":" .. tostring(num)
        end
        local id = LaunchSubScript([[
            _pob_st_subRecord("alpha", 1)
            _pob_st_subRecord("beta", 2)
            ConPrintf("subscript subcall test ok")
            return #("ok")
        ]], "", "ConPrintf,_pob_st_subRecord")
        launch:RegisterSubScript(id, function()
            done = true
        end)
        pumpUntil(function() return done end, 3000)
        _G._pob_st_subRecord = nil
        res.subListAsyncOk = done
            and #subCalls == 2
            and subCalls[1] == "alpha:1"
            and subCalls[2] == "beta:2"
    end

    -- 5. OnSubError delivery when worker raises a runtime error.
    do
        local gotErr = nil
        local done = false
        local id = LaunchSubScript([[
            error("expected_subscript_failure_42")
        ]], "", "")
        launch.subScripts[id] = {
            type = "DOWNLOAD",
            callback = function(body, errMsg)
                if body == nil and errMsg then
                    gotErr = tostring(errMsg)
                end
                done = true
            end,
        }
        pumpUntil(function() return done end, 3000)
        res.onSubErrorOk = done
            and type(gotErr) == "string"
            and gotErr:find("expected_subscript_failure_42", 1, true) ~= nil
            and IsSubScriptRunning(id) == false
    end

    -- 6. Delayed worker non-blocking UI proof: UI thread keeps ticking while worker sleeps.
    do
        local done = false
        local retVal = nil
        local id = LaunchSubScript([[
            local sock = require("socket")
            sock.sleep(0.12)
            return "awake"
        ]], "", "")
        local runningAtStart = IsSubScriptRunning(id)
        launch:RegisterSubScript(id, function(v)
            retVal = v
            done = true
        end)
        local uiTicks = 0
        while not done do
            uiTicks = uiTicks + 1
            if pob and pob.processEvents then pob.processEvents(5) end
            if not done and pob and pob.sleepMs then pob.sleepMs(5) end
            if uiTicks > 600 then break end
        end
        res.uiTicks = uiTicks
        res.nonBlockingUiOk = runningAtStart == true
            and done == true
            and retVal == "awake"
            and uiTicks >= 3
            and IsSubScriptRunning(id) == false
    end

    -- 7. AbortSubScript + IsSubScriptRunning immediate cancellation without firing callbacks.
    do
        local callbackFired = false
        local id = LaunchSubScript([[
            local sock = require("socket")
            sock.sleep(10)
            return "should_not_finish"
        ]], "", "")
        local wasRunning = IsSubScriptRunning(id)
        launch.subScripts[id] = {
            type = "DOWNLOAD",
            callback = function()
                callbackFired = true
            end,
        }
        AbortSubScript(id)
        local runningAfterAbort = IsSubScriptRunning(id)
        launch.subScripts[id] = nil
        -- Pump briefly to prove no late OnSubFinished / OnSubError arrives after abort.
        local t0 = GetTime()
        while (GetTime() - t0) < 60 do
            if pob and pob.processEvents then pob.processEvents(10) end
            if pob and pob.sleepMs then pob.sleepMs(5) end
        end
        res.abortOk = wasRunning == true
            and runningAfterAbort == false
            and callbackFired == false
    end

    res.ok = res.returnValuesOk == true
        and res.shebangOk == true
        and res.funcListSyncOk == true
        and res.subListAsyncOk == true
        and res.onSubErrorOk == true
        and res.nonBlockingUiOk == true
        and res.abortOk == true
    return res
end

-- ============================================================================
-- Headless Selftest 2: pob_selftestNetwork()
-- Spins up an ephemeral-port local loopback HTTP + proxy server in a worker
-- state and verifies DownloadPage GET/POST, delayed non-blocking HTTP, lcurl
-- error :msg()/__tostring, proxy + force-IPv4 propagation, PoEURL resolve +
-- shrink, pob:// URI parsing + build payload decode, and src/LaunchServer.lua.
-- ============================================================================

function pob_selftestNetwork()
    local res = { ok = false }
    if not launch or not launch.DownloadPage then
        res.error = "launch:DownloadPage missing"
        return res
    end

    local savedProxy = launch.proxyURL
    local savedProto = launch.connectionProtocol
    local savedNoSSL = launch.noSSL
    local savedOpenURL = _G.OpenURL
    local savedCopy = _G.Copy

    local bm = main and main.modes and main.modes.BUILD
    local tt = bm and bm.treeTab
    local origSpecCount = tt and #tt.specList or 0
    local origActiveSpec = tt and tt.activeSpec or 1
    local exportInfo = pob_exportTree and pob_exportTree() or nil
    local sampleTreeUrl = (exportInfo and exportInfo.link)
        or "https://www.pathofexile.com/passive-skill-tree/AAAABgAAAAAA"

    local serverPort = nil
    local closedPort = nil
    local serverId = nil

    _G._pob_st_netServerReady = function(p, cp)
        serverPort = tonumber(p)
        closedPort = tonumber(cp)
    end

    local serverScript = [[
        local sampleTreeUrl = ...
        local socket = require("socket")

        -- Grab and immediately close an ephemeral port so tests have a guaranteed-refused port.
        local tmp = assert(socket.bind("127.0.0.1", 0, 1))
        local _, deadPort = tmp:getsockname()
        tmp:close()

        local srv = assert(socket.bind("127.0.0.1", 0, 32))
        local _, port = srv:getsockname()
        _pob_st_netServerReady(port, deadPort)

        local stop = false
        local deadline = os.time() + 15
        while not stop and os.time() < deadline do
            srv:settimeout(0.2)
            local client = srv:accept()
            if client then
                client:settimeout(2)
                local reqLine = client:receive("*l")
                if reqLine then
                    local method, target = reqLine:match("^(%S+)%s+(%S+)")
                    local headers = { }
                    local contentLen = 0
                    while true do
                        local hline = client:receive("*l")
                        if not hline or hline == "" then break end
                        local k, v = hline:match("^([^:]+):%s*(.*)$")
                        if k then
                            local lk = k:lower()
                            headers[lk] = v
                            if lk == "content-length" then
                                contentLen = tonumber(v) or 0
                            end
                        end
                    end
                    local body = ""
                    if contentLen > 0 then
                        body = client:receive(contentLen) or ""
                    end
                    local peerIp = client:getpeername() or ""

                    local status = "200 OK"
                    local extraHeaders = ""
                    local respBody = "ok"

                    if not target then
                        status = "400 Bad Request"
                        respBody = "bad"
                    elseif target:find("/shutdown", 1, true) then
                        respBody = "bye"
                        stop = true
                    elseif target:find("/hello", 1, true) then
                        extraHeaders = "X-PoB-Server: local-ok\r\n"
                        respBody = string.format("method=%s|ua=%s|custom=%s",
                            tostring(method),
                            tostring(headers["user-agent"] or ""),
                            tostring(headers["x-pob-test"] or ""))
                    elseif target:find("/upload", 1, true) then
                        respBody = "posted:" .. body
                    elseif target:find("/slow", 1, true) then
                        socket.sleep(0.12)
                        respBody = "slow-ok"
                    elseif target:find("/status500", 1, true) then
                        status = "500 Internal Server Error"
                        respBody = "fail500"
                    elseif target:find("http://example.invalid/proxy-check", 1, true) then
                        respBody = "proxy-ok|peer=" .. tostring(peerIp)
                    elseif target:find("poeurl.com/st1", 1, true) then
                        status = "302 Found"
                        extraHeaders = "Location: " .. sampleTreeUrl .. "\r\n"
                        respBody = ""
                    elseif target:find("poeurl.com/bad", 1, true) then
                        status = "302 Found"
                        extraHeaders = "Location: http://poeurl.com/\r\n"
                        respBody = ""
                    elseif target:find("shrink.php?url=", 1, true) then
                        respBody = "stShort42"
                    end

                    local rawResp = string.format(
                        "HTTP/1.1 %s\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n%s\r\n%s",
                        status, #respBody, extraHeaders, respBody
                    )
                    client:send(rawResp)
                end
                client:close()
            end
        end
        srv:close()
        return "server-stopped"
    ]]

    local okRun, runErr = pcall(function()
        serverId = LaunchSubScript(serverScript, "", "_pob_st_netServerReady", sampleTreeUrl)
        launch:RegisterSubScript(serverId, function() end)
        if not pumpUntil(function() return serverPort ~= nil end, 3000) then
            res.error = "local loopback server failed to bind"
            return
        end
        res.serverBoundOk = serverPort ~= nil and serverPort > 0

        local baseUrl = "http://127.0.0.1:" .. tostring(serverPort)

        -- 1. Real launch:DownloadPage GET + custom headers + response header capture + User-Agent.
        do
            local done = false
            local resp, err
            launch:DownloadPage(baseUrl .. "/hello", function(r, e)
                resp, err = r, e
                done = true
            end, { header = "X-PoB-Test: header-42" })
            pumpUntil(function() return done end, 3000)
            res.downloadGetOk = done
                and err == nil
                and type(resp) == "table"
                and tostring(resp.body):find("method=GET", 1, true) ~= nil
                and tostring(resp.body):find("ua=Path of Building/", 1, true) ~= nil
                and tostring(resp.body):find("custom=header-42", 1, true) ~= nil
                and tostring(resp.header):lower():find("x%-pob%-server:%s*local%-ok") ~= nil
        end

        -- 2. Real launch:DownloadPage POST + HTTP 500 error mapping.
        do
            local postDone, errDone = false, false
            local postResp, postErr, err500
            launch:DownloadPage(baseUrl .. "/upload", function(r, e)
                postResp, postErr = r, e
                postDone = true
            end, { body = "pobCode=abc123xyz" })
            launch:DownloadPage(baseUrl .. "/status500", function(_, e)
                err500 = e
                errDone = true
            end)
            pumpUntil(function() return postDone and errDone end, 3000)
            res.downloadPostOk = postDone
                and postErr == nil
                and type(postResp) == "table"
                and postResp.body == "posted:pobCode=abc123xyz"
                and errDone
                and err500 == "Response code: 500"
        end

        -- 3. Delayed HTTP endpoint non-blocking UI proof.
        do
            local done = false
            local body, err
            launch:DownloadPage(baseUrl .. "/slow", function(r, e)
                body = r and r.body
                err = e
                done = true
            end)
            local returnedBeforeFinish = (done == false)
            local uiTicks = 0
            while not done do
                uiTicks = uiTicks + 1
                if pob and pob.processEvents then pob.processEvents(5) end
                if not done and pob and pob.sleepMs then pob.sleepMs(5) end
                if uiTicks > 600 then break end
            end
            res.delayedHttpTicks = uiTicks
            res.delayedNonBlockingOk = returnedBeforeFinish
                and done
                and err == nil
                and body == "slow-ok"
                and uiTicks >= 3
        end

        -- 4. lcurl.safe error :msg() & __tostring + DownloadPage connection-refused handling.
        do
            local curl = require("lcurl.safe")
            local easy = curl.easy()
            easy:setopt_url("http://127.0.0.1:" .. tostring(closedPort) .. "/unreachable")
            easy:setopt_connecttimeout(2)
            local okPerf, errObj = easy:perform()
            easy:close()

            local dlDone = false
            local dlErr = nil
            launch:DownloadPage("http://127.0.0.1:" .. tostring(closedPort) .. "/unreachable", function(_, e)
                dlErr = e
                dlDone = true
            end)
            pumpUntil(function() return dlDone end, 4000)

            res.lcurlErrorMsgOk = okPerf == nil
                and errObj ~= nil
                and type(errObj.msg) == "function"
                and type(errObj:msg()) == "string"
                and #errObj:msg() > 0
                and tostring(errObj) == errObj:msg()
                and dlDone
                and type(dlErr) == "string"
                and #dlErr > 0
        end

        -- 4b. Offline TLS CA-init: HTTPS against the plain-HTTP loopback server must fail with
        -- a handshake/SSL-connect error, never CURLE_SSL_CACERT_BADFILE ("SSL CA cert").
        do
            local curl = require("lcurl.safe")
            local easy = curl.easy()
            easy:setopt_url("https://127.0.0.1:" .. tostring(serverPort) .. "/hello")
            easy:setopt_connecttimeout(3)
            easy:setopt_ssl_verifypeer(1)
            local okTls, tlsErr = easy:perform()
            easy:close()
            local mainMsg = tlsErr and tostring(tlsErr) or ""

            local wDone, wErr = false, nil
            launch:DownloadPage("https://127.0.0.1:" .. tostring(serverPort) .. "/hello", function(_, e)
                wErr = e
                wDone = true
            end)
            pumpUntil(function() return wDone end, 5000)
            local workerMsg = type(wErr) == "string" and wErr or ""

            res.tlsCaMainMsg = mainMsg
            res.tlsCaWorkerMsg = workerMsg
            res.tlsCaInitOk = okTls == nil and #mainMsg > 0
                and not mainMsg:find("SSL CA cert", 1, true)
                and wDone and #workerMsg > 0
                and not workerMsg:find("SSL CA cert", 1, true)
        end

        -- 5. Proxy + force-IPv4 option propagation + PoEURL resolve & shrink through local proxy.
        do
            launch.proxyURL = baseUrl
            launch.connectionProtocol = 1 -- CURL_IPRESOLVE_V4

            local proxyDone = false
            local proxyBody, proxyErr
            launch:DownloadPage("http://example.invalid/proxy-check", function(r, e)
                proxyBody = r and r.body
                proxyErr = e
                proxyDone = true
            end)
            pumpUntil(function() return proxyDone end, 3000)
            res.proxyIpv4Ok = proxyDone
                and proxyErr == nil
                and type(proxyBody) == "string"
                and proxyBody:find("proxy-ok|peer=127.0.0.1", 1, true) ~= nil

            -- PoEURL shrink helper (`http://poeurl.com/shrink.php?url=...` routed via local proxy).
            local sh = pob_shrinkPoeUrl(sampleTreeUrl)
            local shSt = nil
            if sh and sh.ok and sh.reqId then
                pumpUntil(function()
                    shSt = pob_getShrinkPoeUrlStatus(sh.reqId)
                    return shSt and shSt.done
                end, 3000)
            end
            res.poeurlShrinkOk = shSt ~= nil
                and shSt.ok == true
                and shSt.shortUrl == "http://poeurl.com/stShort42"

            -- PoEURL resolve helper (`http://poeurl.com/st1` -> 302 -> sampleTreeUrl -> imported spec).
            if tt then
                local rv = pob_resolvePoeUrl("ST PoEURL Spec", "http://poeurl.com/st1")
                local rvSt = nil
                if rv and rv.ok and rv.reqId then
                    pumpUntil(function()
                        rvSt = pob_getPoeUrlStatus(rv.reqId)
                        return rvSt and rvSt.done
                    end, 3000)
                end
                local badRv = pob_resolvePoeUrl("ST Bad", "http://poeurl.com/bad")
                local badSt = nil
                if badRv and badRv.ok and badRv.reqId then
                    pumpUntil(function()
                        badSt = pob_getPoeUrlStatus(badRv.reqId)
                        return badSt and badSt.done
                    end, 3000)
                end
                res.poeurlResolveOk = rvSt ~= nil
                    and rvSt.ok == true
                    and rvSt.resolvedUrl == sampleTreeUrl
                    and #tt.specList == origSpecCount + 1
                    and badSt ~= nil and badSt.ok == false
                -- Clean up temporary spec so active build returns untouched.
                if #tt.specList > origSpecCount and pob_deleteSpec then
                    pob_deleteSpec(#tt.specList)
                end
                if pob_setActiveSpec and tt.activeSpec ~= origActiveSpec then
                    pob_setActiveSpec(origActiveSpec)
                end
            else
                res.poeurlResolveOk = false
            end

            launch.proxyURL = savedProxy
            launch.connectionProtocol = savedProto
        end

        -- 6. pob:// URI parser & build share-code round-trip check.
        do
            local p1 = pob_parsePobUri("pob://pobbin/AbCdEf12")
            local p2 = pob_parsePobUri("POB://Maxroll/MyBuild_9")
            local pBad = pob_parsePobUri("pob://unknownsite/123")
            local xmlNow = pob_getBuildXML and pob_getBuildXML() or nil
            local shareRoundTripOk = false
            if type(xmlNow) == "string" and #xmlNow > 0 and common and common.base64 then
                local code = common.base64.encode(Deflate(xmlNow)):gsub("%+", "-"):gsub("/", "_")
                local decodedXml = decodeBuildPayload(code)
                shareRoundTripOk = type(decodedXml) == "string"
                    and decodedXml:find("<PathOfBuilding", 1, true) ~= nil
            end
            res.pobUriOk = p1.ok == true
                and p1.siteId == "POBBin"
                and p1.downloadUrl == "https://pobb.in/pob/AbCdEf12"
                and p2.ok == true
                and p2.siteId == "Maxroll"
                and p2.downloadUrl == "https://maxroll.gg/poe/api/pob/MyBuild_9"
                and pBad.ok == false
                and shareRoundTripOk
        end

        -- 7. src/LaunchServer.lua localhost TCP OAuth redirect round-trip.
        do
            local serverFile = io.open("LaunchServer.lua", "r")
            if serverFile then
                local launchServerSrc = serverFile:read("*a")
                serverFile:close()

                local capturedAuthUrl = nil
                _G.OpenURL = function(u) capturedAuthUrl = u end
                _G.Copy = function(u) capturedAuthUrl = capturedAuthUrl or u end

                local oauthDone = false
                local oauthCode, oauthErr, oauthState, oauthPort
                local lsId = LaunchSubScript(
                    launchServerSrc,
                    "",
                    "ConPrintf,OpenURL,Copy",
                    "https://www.pathofexile.com/oauth/authorize?client_id=pob&state=st_state_77"
                )
                launch.subScripts[lsId] = {
                    type = "DOWNLOAD",
                    callback = function(c, e, s, p)
                        oauthCode, oauthErr, oauthState, oauthPort = c, e, s, p
                        oauthDone = true
                    end,
                }

                local gotUrl = pumpUntil(function()
                    return capturedAuthUrl ~= nil or oauthDone
                end, 3000)

                if gotUrl and capturedAuthUrl then
                    local boundPort = tonumber(capturedAuthUrl:match("redirect_uri=http://localhost:(%d+)"))
                    if boundPort then
                        local hitDone = false
                        launch:DownloadPage(
                            string.format("http://127.0.0.1:%d/?code=st_code_99&state=st_state_77", boundPort),
                            function() hitDone = true end
                        )
                        pumpUntil(function() return hitDone and oauthDone end, 3000)
                        res.launchServerOk = oauthDone
                            and oauthCode == "st_code_99"
                            and oauthErr == nil
                            and oauthState == "st_state_77"
                            and tonumber(oauthPort) == boundPort
                            and IsSubScriptRunning(lsId) == false
                    end
                end
                if IsSubScriptRunning(lsId) then
                    AbortSubScript(lsId)
                    launch.subScripts[lsId] = nil
                end
                _G.OpenURL = savedOpenURL
                _G.Copy = savedCopy
            end
        end

        -- Shut down the loopback server cleanly.
        if serverPort then
            local shutDone = false
            launch:DownloadPage(baseUrl .. "/shutdown", function() shutDone = true end)
            pumpUntil(function()
                return shutDone and (not serverId or not IsSubScriptRunning(serverId))
            end, 2000)
        end
    end)

    -- Unconditional cleanup on any exit path.
    _G._pob_st_netServerReady = nil
    _G.OpenURL = savedOpenURL
    _G.Copy = savedCopy
    launch.proxyURL = savedProxy
    launch.connectionProtocol = savedProto
    launch.noSSL = savedNoSSL
    if serverId and IsSubScriptRunning(serverId) then
        AbortSubScript(serverId)
        if launch and launch.subScripts then
            launch.subScripts[serverId] = nil
        end
    end
    if tt and #tt.specList > origSpecCount and pob_deleteSpec then
        while #tt.specList > origSpecCount do
            pob_deleteSpec(#tt.specList)
        end
        if pob_setActiveSpec then pob_setActiveSpec(origActiveSpec) end
    end

    if not okRun then
        res.error = tostring(runErr)
        res.ok = false
        return res
    end

    res.ok = res.serverBoundOk == true
        and res.downloadGetOk == true
        and res.downloadPostOk == true
        and res.delayedNonBlockingOk == true
        and res.lcurlErrorMsgOk == true
        and res.tlsCaInitOk == true
        and res.proxyIpv4Ok == true
        and res.poeurlShrinkOk == true
        and res.poeurlResolveOk == true
        and res.pobUriOk == true
        and res.launchServerOk == true
    return res
end

return M
