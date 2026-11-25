-- app/lua/pob_update.lua
--
-- Phase 14.2: Async GitHub Releases update notifier & dev-mode selftests.
-- Auto-loaded by app/lua/pob_host.lua via `pcall(require, "pob_update")`.
--
-- Exposes top-level globals for LuaEngine::invoke():
--   pob_checkForUpdates(opts)
--   pob_getUpdateState()
--   pob_dismissUpdate()
--   pob_selftestUpdate()
--   pob_selftestDevMode()

local dkjson = require("dkjson")

-- Ensure SubScriptManager's lazy registration of pob.processEvents / pob.sleepMs
-- on the main Lua state is active when selftests run.
if IsSubScriptRunning then
    IsSubScriptRunning(0)
end

local _state = {
    status = "idle",      -- "idle" | "checking" | "available" | "up_to_date" | "error"
    checking = false,
    available = false,
    dismissed = false,
    currentVersion = "",
    latestVersion = "",
    releaseUrl = "",
    releaseName = "",
    publishedAt = "",
    repo = (type(POB_UPDATE_REPO) == "string" and POB_UPDATE_REPO ~= "")
        and POB_UPDATE_REPO or "jjacobson815/PathOfBuilding",
    error = "",
}

local function currentVersionString()
    local v = launch and launch.versionNumber
    if type(v) ~= "string" or v == "" or v == "?" then
        return "0.0.0"
    end
    return v
end

_state.currentVersion = currentVersionString()

local function emitUpdateSignal()
    if pob and pob.emitSignal then
        pob.emitSignal("update")
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

-- Parse a semver string like "v2.45.0", "2.45", "v2.45.0-beta.1+build123".
-- Returns { major, minor, patch, pre = { ... } } or nil if invalid.
local function parseSemver(ver)
    if type(ver) ~= "string" then
        return nil
    end
    local s = ver:match("^%s*[vV]?(.-)%s*$")
    if not s or s == "" then
        return nil
    end
    -- Strip build metadata (+...)
    s = s:gsub("%+.*$", "")
    local core, preStr = s:match("^([^%-]+)%-(.+)$")
    if not core then
        core = s
    end
    local maj, min, pat = core:match("^(%d+)%.(%d+)%.(%d+)$")
    if not maj then
        maj, min = core:match("^(%d+)%.(%d+)$")
        pat = min and "0" or nil
    end
    if not maj then
        maj = core:match("^(%d+)$")
        if maj then
            min, pat = "0", "0"
        end
    end
    if not maj then
        return nil
    end
    local pre = nil
    if preStr and preStr ~= "" then
        pre = { }
        for part in preStr:gmatch("[^%.]+") do
            local num = part:match("^%d+$") and tonumber(part) or nil
            pre[#pre + 1] = num or part
        end
    end
    return {
        major = tonumber(maj),
        minor = tonumber(min),
        patch = tonumber(pat),
        pre = pre,
    }
end

-- Compare two semver strings: returns 1 if latest > current, 0 if equal, -1 if latest < current,
-- or nil if either version cannot be parsed.
local function compareSemver(latest, current)
    local a = parseSemver(latest)
    local b = parseSemver(current)
    if not a or not b then
        return nil
    end
    if a.major ~= b.major then
        return (a.major > b.major) and 1 or -1
    end
    if a.minor ~= b.minor then
        return (a.minor > b.minor) and 1 or -1
    end
    if a.patch ~= b.patch then
        return (a.patch > b.patch) and 1 or -1
    end
    if not a.pre and not b.pre then
        return 0
    end
    -- A normal version has higher precedence than a pre-release version.
    if not a.pre and b.pre then
        return 1
    end
    if a.pre and not b.pre then
        return -1
    end
    local n = math.max(#a.pre, #b.pre)
    for i = 1, n do
        local pa = a.pre[i]
        local pb = b.pre[i]
        if pa == nil and pb == nil then
            return 0
        elseif pa == nil then
            return -1
        elseif pb == nil then
            return 1
        end
        local ta, tb = type(pa), type(pb)
        if ta == tb then
            if pa ~= pb then
                return (pa > pb) and 1 or -1
            end
        else
            -- Numeric identifiers always have lower precedence than non-numeric identifiers.
            return (ta == "number") and -1 or 1
        end
    end
    return 0
end

local function buildUpdateUrl(overrideUrl)
    if type(overrideUrl) == "string" and overrideUrl ~= "" then
        return overrideUrl
    end
    local repo = (type(POB_UPDATE_REPO) == "string" and POB_UPDATE_REPO ~= "")
        and POB_UPDATE_REPO or _state.repo
    _state.repo = repo
    return "https://api.github.com/repos/" .. repo .. "/releases/latest"
end

function pob_getUpdateState()
    _state.currentVersion = currentVersionString()
    if type(POB_UPDATE_REPO) == "string" and POB_UPDATE_REPO ~= "" then
        _state.repo = POB_UPDATE_REPO
    end
    return {
        status = _state.status,
        checking = _state.checking,
        available = _state.available,
        dismissed = _state.dismissed,
        currentVersion = _state.currentVersion,
        latestVersion = _state.latestVersion,
        releaseUrl = _state.releaseUrl,
        releaseName = _state.releaseName,
        publishedAt = _state.publishedAt,
        repo = _state.repo,
        error = _state.error,
    }
end

function pob_dismissUpdate()
    _state.dismissed = true
    return { ok = true, _emit = { "update" } }
end

function pob_checkForUpdates(opts)
    local force = false
    local overrideUrl = nil
    if type(opts) == "table" then
        force = opts.force == true
        if type(opts.url) == "string" and opts.url ~= "" then
            overrideUrl = opts.url
        end
    elseif type(opts) == "string" and opts ~= "" then
        overrideUrl = opts
    end

    if _state.checking then
        return { ok = true, checking = true, _emit = { "update" } }
    end

    if not LaunchSubScript or not launch or not launch.RegisterSubScript then
        _state.status = "error"
        _state.checking = false
        _state.error = "SubScript host unavailable"
        return { ok = false, checking = false, error = _state.error, _emit = { "update" } }
    end

    local targetUrl = buildUpdateUrl(overrideUrl)
    _state.currentVersion = currentVersionString()
    _state.checking = true
    _state.status = "checking"
    _state.error = ""
    if force then
        _state.dismissed = false
    end

    local proxy = launch.proxyURL
    local ipresolve = launch.connectionProtocol
    local noSSL = launch.noSSL and true or false

    local workerScript = [[
        local url, proxy, ipresolve, noSSL = ...
        if not pob or not pob.http then
            return false, 0, "", "pob.http unavailable in worker"
        end
        local opts = {
            url = url,
            useragent = "PathOfBuilding-Qt",
            httpheader = { "Accept: application/vnd.github+json" },
            followlocation = true,
            timeout = 10,
            connecttimeout = 5,
        }
        if type(proxy) == "string" and proxy ~= "" then
            opts.proxy = proxy
        end
        if ipresolve == 1 or ipresolve == 2 then
            opts.ipresolve = ipresolve
        end
        if noSSL then
            opts.ssl_verifypeer = 0
            opts.ssl_verifyhost = 0
        end
        local resp, err = pob.http(opts)
        if not resp then
            return false, 0, "", tostring(err or "HTTP request failed")
        end
        return true, tonumber(resp.code) or 0, tostring(resp.body or ""), tostring(resp.error or "")
    ]]

    local ssId = LaunchSubScript(workerScript, "", "", targetUrl, proxy, ipresolve, noSSL)
    if not ssId or ssId == 0 then
        _state.checking = false
        _state.status = "error"
        _state.error = "Failed to launch update check subscript"
        return { ok = false, checking = false, error = _state.error, _emit = { "update" } }
    end

    launch:RegisterSubScript(ssId, function(ok, statusCode, body, err)
        _state.checking = false
        _state.currentVersion = currentVersionString()
        if not ok then
            _state.status = "error"
            _state.error = (type(err) == "string" and err ~= "") and err or "Update check failed"
            emitUpdateSignal()
            return
        end

        local code = tonumber(statusCode) or 0
        if code < 200 or code >= 300 then
            local apiMsg = nil
            if type(body) == "string" and body ~= "" then
                local parsedErr = dkjson.decode(body)
                if type(parsedErr) == "table" and type(parsedErr.message) == "string" then
                    apiMsg = parsedErr.message
                end
            end
            _state.status = "error"
            _state.error = apiMsg and ("HTTP " .. tostring(code) .. ": " .. apiMsg)
                or ("HTTP " .. tostring(code))
            emitUpdateSignal()
            return
        end

        local data, _, decErr = dkjson.decode(tostring(body or ""))
        if type(data) ~= "table" then
            _state.status = "error"
            _state.error = "Invalid JSON response" .. (decErr and (": " .. tostring(decErr)) or "")
            emitUpdateSignal()
            return
        end

        local tagName = type(data.tag_name) == "string" and data.tag_name or ""
        if tagName == "" then
            _state.status = "error"
            _state.error = "Release response missing tag_name"
            emitUpdateSignal()
            return
        end

        local htmlUrl = type(data.html_url) == "string" and data.html_url or ""
        if htmlUrl == "" then
            htmlUrl = "https://github.com/" .. _state.repo .. "/releases/latest"
        end
        local releaseName = type(data.name) == "string" and data.name or tagName
        local publishedAt = type(data.published_at) == "string" and data.published_at or ""

        _state.latestVersion = tagName
        _state.releaseUrl = htmlUrl
        _state.releaseName = releaseName
        _state.publishedAt = publishedAt
        _state.error = ""

        local cmp = compareSemver(tagName, _state.currentVersion)
        if cmp == nil then
            -- Fallback: if current version is unknown/unparseable, treat non-empty different tag as available
            if _state.currentVersion == "0.0.0" then
                _state.available = true
                _state.status = "available"
            else
                _state.status = "error"
                _state.error = "Unparseable version: " .. tostring(tagName) .. " vs " .. tostring(_state.currentVersion)
            end
        elseif cmp > 0 then
            _state.available = true
            _state.status = "available"
            _state.dismissed = false
        else
            _state.available = false
            _state.status = "up_to_date"
        end
        emitUpdateSignal()
    end)

    return { ok = true, checking = true, _emit = { "update" } }
end

-- ============================================================================
-- Headless Selftests
-- ============================================================================

function pob_selftestUpdate()
    local res = { ok = false }

    -- 1. Semver comparison checks
    local semverOk = compareSemver("v2.45.1", "2.45.0") == 1
        and compareSemver("v2.45.0", "2.45.0") == 0
        and compareSemver("2.44.9", "v2.45.0") == -1
        and compareSemver("v3.0.0", "2.99.99") == 1
        and compareSemver("v2.45.0", "2.45.0-beta.1") == 1
        and compareSemver("2.45.0-beta.1", "2.45.0-beta.2") == -1
    res.semverOk = semverOk

    -- Save current state so selftest leaves clean state afterwards
    local savedState = { }
    for k, v in pairs(_state) do
        savedState[k] = v
    end

    -- 2. Dismiss check
    _state.available = true
    _state.dismissed = false
    local dRes = pob_dismissUpdate()
    local dismissOk = type(dRes) == "table" and dRes.ok == true
        and _state.dismissed == true
        and pob_getUpdateState().dismissed == true
    res.dismissOk = dismissOk

    -- 3. End-to-end async check against local loopback HTTP server
    local asyncLoopbackOk = false
    local serverPort = nil
    local serverId = nil

    _G._pob_st_updateServerReady = function(p)
        serverPort = tonumber(p)
    end

    local serverScript = [[
        local socket = require("socket")
        local srv = assert(socket.bind("127.0.0.1", 0, 8))
        local _, port = srv:getsockname()
        _pob_st_updateServerReady(port)

        local stop = false
        local deadline = os.time() + 10
        while not stop and os.time() < deadline do
            srv:settimeout(0.2)
            local client = srv:accept()
            if client then
                client:settimeout(2)
                local reqLine = client:receive("*l")
                if reqLine then
                    while true do
                        local hline = client:receive("*l")
                        if not hline or hline == "" then break end
                    end
                    local body = '{"tag_name":"v99.1.0","html_url":"https://github.com/jjacobson815/PathOfBuilding/releases/tag/v99.1.0","name":"PoB Qt v99.1.0","published_at":"2026-11-24T00:00:00Z"}'
                    local resp = string.format(
                        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
                        #body, body
                    )
                    client:send(resp)
                    stop = true
                end
                client:close()
            end
        end
        srv:close()
        return "done"
    ]]

    local okRun, runErr = pcall(function()
        serverId = LaunchSubScript(serverScript, "", "_pob_st_updateServerReady")
        if serverId and launch and launch.RegisterSubScript then
            launch:RegisterSubScript(serverId, function() end)
        end
        if not pumpUntil(function() return serverPort ~= nil end, 3000) then
            res.error = "update loopback server failed to bind"
            return
        end

        _state.checking = false
        _state.status = "idle"
        _state.available = false
        _state.dismissed = false

        local testUrl = "http://127.0.0.1:" .. tostring(serverPort) .. "/releases/latest"
        local startRes = pob_checkForUpdates({ force = true, url = testUrl })
        local finished = pumpUntil(function() return _state.checking == false end, 5000)
        local st = pob_getUpdateState()

        asyncLoopbackOk = type(startRes) == "table"
            and startRes.ok == true
            and startRes.checking == true
            and finished == true
            and st.status == "available"
            and st.available == true
            and st.dismissed == false
            and st.latestVersion == "v99.1.0"
            and st.releaseName == "PoB Qt v99.1.0"
            and st.releaseUrl == "https://github.com/jjacobson815/PathOfBuilding/releases/tag/v99.1.0"
            and st.error == ""
    end)

    _G._pob_st_updateServerReady = nil
    if serverId and IsSubScriptRunning and IsSubScriptRunning(serverId) and AbortSubScript then
        AbortSubScript(serverId)
    end

    -- Restore original state
    for k, v in pairs(savedState) do
        _state[k] = v
    end

    if not okRun then
        res.error = tostring(runErr)
    end
    res.asyncLoopbackOk = asyncLoopbackOk
    res.ok = semverOk and dismissOk and asyncLoopbackOk
    return res
end

function pob_selftestDevMode()
    local res = { ok = false }
    local devModeTypeOk = type(_POB_DEV_MODE) == "boolean"
    local updateRepoOk = type(POB_UPDATE_REPO) == "string" and #POB_UPDATE_REPO > 0

    local legacyInertOk = false
    if launch and type(launch.CheckForUpdate) == "function" and type(launch.ApplyUpdate) == "function" then
        launch:CheckForUpdate()
        launch:ApplyUpdate()
        legacyInertOk = launch.updateCheckRunning == false
            and launch.updateAvailable == nil
            and launch.doRestart == nil
    end

    local devModeLaunchOk = true
    if _POB_DEV_MODE == true then
        devModeLaunchOk = (launch ~= nil and launch.devMode == true)
    end

    res.devModeTypeOk = devModeTypeOk
    res.updateRepoOk = updateRepoOk
    res.legacyInertOk = legacyInertOk
    res.devModeLaunchOk = devModeLaunchOk
    res.ok = devModeTypeOk and updateRepoOk and legacyInertOk and devModeLaunchOk
    return res
end

return {
    compareSemver = compareSemver,
    parseSemver = parseSemver,
}
