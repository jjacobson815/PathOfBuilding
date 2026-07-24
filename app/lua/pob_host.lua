-- pob_host.lua — Qt / LuaJIT host bootstrap for Path of Building
--
-- Provides the "SimpleGraphic" engine globals the calc engine expects, routing
-- the few that matter through the C `pob` bridge table registered by LuaEngine.
-- This mirrors src/HeadlessWrapper.lua (the project's existing headless seam):
-- it defines the globals, loads Launch.lua, then runs one OnInit + OnFrame so
-- the active build mode initialises. The difference is that logging / paths /
-- clipboard / URLs are delegated to Qt instead of being no-ops.

-- Make require() resolve modules in src/, runtime/lua, and the bundled host
-- shims directory (app/lua, exposed as _POB_LUA_DIR) — all incl. subdir init.lua.
package.path = _SRC_DIR .. "/?.lua;" .. _SRC_DIR .. "/?/init.lua;"
             .. _RUNTIME_DIR .. "/lua/?.lua;" .. _RUNTIME_DIR .. "/lua/?/init.lua;"
             .. _POB_LUA_DIR .. "/?.lua;" .. _POB_LUA_DIR .. "/?/init.lua;"
             .. package.path

-- Native C modules. The official PoB runtime ships lua-utf8.dll (and friends)
-- in the runtime ROOT, so that directory must be on cpath; Lua 5.1's C loader
-- strips everything up to the first hyphen when deriving the entry symbol, so
-- require('lua-utf8') -> runtime/lua-utf8.dll -> luaopen_utf8. runtime/lua is
-- kept for any modules placed next to the runtime Lua sources.
package.cpath = _RUNTIME_DIR .. "/?.dll;" .. _RUNTIME_DIR .. "/lua/?.dll;"
             .. _RUNTIME_DIR .. "/lua/?/init.dll;"
             .. package.cpath

-- lcurl.safe and lzip are provided by bundled shims in _POB_LUA_DIR
-- (lcurl/safe.lua, lzip.lua) resolved through the normal require path.
-- 'lua-utf8' loads the real runtime DLL when present; the rename to 'utf8'
-- is kept only as a fallback for sandboxes that build luautf8 under that name.
local l_require = require
function require(name)
    if name == "lua-utf8" then
        local ok, mod = pcall(l_require, "lua-utf8")
        if ok then return mod end
        name = "utf8"
    end
    return l_require(name)
end

-- Engine callback registry (the engine calls runCallback).
local callbackTable = { }
local mainObject
function runCallback(name, ...)
    if callbackTable[name] then
        return callbackTable[name](...)
    elseif mainObject and mainObject[name] then
        return mainObject[name](mainObject, ...)
    end
end
function SetCallback(name, func) callbackTable[name] = func end
function GetCallback(name) return callbackTable[name] end
function SetMainObject(obj)
    mainObject = obj
    pob.setMainObject(obj)
end

-- Logging
function ConPrintf(fmt, ...)
    pob.log(string.format(fmt, ...))
end
function ConPrintTable(tbl, noRecurse) end
function ConExecute(cmd) end
function ConClear() end

-- Rendering (no-ops; QML owns display)
function RenderInit(flag, ...) end
function GetScreenSize() return 1920, 1080 end
function GetScreenScale() return 1 end
function GetVirtualScreenSize() return GetScreenSize() end
function GetDPIScaleOverridePercent() return 1 end
function SetDPIScaleOverridePercent(scale) end
function SetClearColor(r, g, b, a) end
function SetDrawLayer(layer, subLayer) end
function SetViewport(x, y, width, height) end
function SetDrawColor(r, g, b, a) end
function DrawImage(imgHandle, left, top, width, height, tcLeft, tcTop, tcRight, tcBottom) end
function DrawImageQuad(imageHandle, x1, y1, x2, y2, x3, y3, x4, y4, s1, t1, s2, t2, s3, t3, s4, t4) end
function DrawString(left, top, align, height, font, text) end
-- Phase 1.2a: DrawString is a no-op (QML owns rendering), but the two *measure*
-- globals must be REAL — ported control layout math (EditControl caret, ListControl
-- ellipsis, DropDown/Tooltip/GemSelect auto-width: 103 DrawStringWidth + 8
-- DrawStringCursorIndex sites) depends on legacy-exact widths. Backed by the
-- .tgf-driven C++ TextMetrics engine via the pob bridge. `font` nil defaults to
-- FIXED inside TextMetrics.
function DrawStringWidth(height, font, text)
    return pob.stringWidth(height or 0, font, text ~= nil and tostring(text) or "")
end
function DrawStringCursorIndex(height, font, text, cursorX, cursorY)
    return pob.stringCursorIndex(height or 0, font, text ~= nil and tostring(text) or "",
                                 cursorX or 0, cursorY or 0)
end
function StripEscapes(text)
    return text:gsub("%^%d", ""):gsub("%^x%x%x%x%x%x%x", "")
end
function GetAsyncCount() return 0 end

-- Image handles (no-op stubs)
function NewImageHandle()
    return setmetatable({ }, {
        __index = {
            Load = function(self, fileName, ...) self.valid = true end,
            Unload = function(self) self.valid = false end,
            IsValid = function(self) return self.valid end,
            SetLoadingPriority = function(self, pri) end,
            ImageSize = function(self) return 1, 1 end,
        }
    })
end

-- Search handles. Phase 3: implement a real directory iterator backed by the
-- C `pob.listDir` bridge (QDir) so the LIST-mode build scanner (BuildListHelpers
-- .ScanFolder) actually enumerates the builds folder instead of returning nil.
-- The engine's SimpleGraphic NewFileSearch(path, isDir) returns a handle with
-- GetFileName()/GetFileModifiedTime()/NextFile(); we wrap pob.listDir's array.
function NewFileSearch(pattern, isDir)
    if not pattern then return nil end
    local dir, pat = pattern:match("(.*[/\\])([^/\\]*)$")
    if not dir then dir = "."; pat = pattern end
    if pat == "" then pat = "*" end
    local entries = pob.listDir(dir, isDir, pat)
    if not entries or #entries == 0 then
        return nil
    end
    local idx = 1
    local handle = { }
    function handle:GetFileName() return entries[idx] and entries[idx].name or nil end
    function handle:GetFileModifiedTime() return entries[idx] and entries[idx].modified or 0 end
    function handle:NextFile()
        idx = idx + 1
        return idx <= #entries
    end
    return handle
end

-- Window / input
function SetWindowTitle(title) end
function GetCursorPos() return 0, 0 end
function SetCursorPos(x, y) end
function ShowCursor(doShow) end
function IsKeyDown(keyName)
	if pob.isKeyDown then return pob.isKeyDown(keyName) end
	return false
end
function SetForeground() if pob.setForeground then pob.setForeground() end end
function Copy(text) if pob.copy then pob.copy(text) end end
function Paste() if pob.paste then return pob.paste() end end
function Deflate(data) return pob.deflate(data) end
function Inflate(data) return pob.inflate(data) end
function GetTime() return pob.getTime() end
function GetScriptPath() return _SRC_DIR end
function GetRuntimePath() return _RUNTIME_DIR end
function GetUserPath() return _USER_DIR end
function MakeDir(path) return pob.makeDir(path) end
function RemoveDir(path) return pob.removeDir(path) end
function SetWorkDir(path) end
function GetWorkDir() return "." end
function LaunchSubScript(scriptText, funcList, subList, ...) end
function AbortSubScript(ssID) end
function IsSubScriptRunning(ssID) end

-- Module loading (prepends _SRC_DIR)
function LoadModule(fileName, ...)
    if not fileName:match("%.lua") then fileName = fileName .. ".lua" end
    local func, err = loadfile(_SRC_DIR .. "/" .. fileName)
    if func then
        return func(...)
    else
        error("LoadModule() error loading '" .. fileName .. "': " .. err)
    end
end
function PLoadModule(fileName, ...)
    if not fileName:match("%.lua") then fileName = fileName .. ".lua" end
    local func, err = loadfile(_SRC_DIR .. "/" .. fileName)
    if func then
        return PCall(func, ...)
    else
        error("PLoadModule() error loading '" .. fileName .. "': " .. err)
    end
end
function PCall(func, ...)
    local ret = { pcall(func, ...) }
    if ret[1] then
        table.remove(ret, 1)
        return nil, unpack(ret)
    else
        return ret[2]
    end
end

-- Misc
function SpawnProcess(cmdName, args) end
function OpenURL(url) if pob.openURL then pob.openURL(url) end end
function SetProfiling(isEnabled) end
function Restart() end
function Exit() end
function TakeScreenshot() end
-- Part 1.4: real cloud-provider detection (replaces the null stub). Two honest,
-- dependency-free signals: (1) a path-prefix match against the OneDrive* env
-- vars Windows sets for each synced root, which NAMES the provider; (2) the
-- file's Win32 attributes via the pob.fileAttributes bridge, which reveals
-- whether the target is a dehydrated cloud placeholder (FILE_ATTRIBUTE_OFFLINE /
-- RECALL_ON_DATA_ACCESS / RECALL_ON_OPEN) — the exact condition that makes a
-- read fail transiently and trip Main.lua's errorReadingSettings path. Returns
-- (provider, providerRoot, status) matching the 3-value shape Main.lua's
-- OpenCloudErrorPopup consumes as `local provider, _, status = ...`.
function GetCloudProvider(fullPath)
    if not fullPath or fullPath == "" then return nil, nil, nil end
    local provider, providerRoot
    local norm = tostring(fullPath):gsub("\\", "/"):lower()
    for _, var in ipairs({ "OneDriveConsumer", "OneDriveCommercial", "OneDrive" }) do
        local root = os.getenv(var)
        if root and root ~= "" then
            local nroot = root:gsub("\\", "/"):lower():gsub("/+$", "")
            if nroot ~= "" and norm:sub(1, #nroot) == nroot then
                provider = "OneDrive"
                providerRoot = root
                break
            end
        end
    end
    local status = "unknown"
    if pob and pob.fileAttributes then
        local a = pob.fileAttributes(fullPath)
        if a then
            if not a.exists then
                status = "missing"
            elseif a.offline or a.recallOnDataAccess or a.recallOnOpen then
                status = "offline (cloud placeholder not hydrated)"
            else
                status = "online"
            end
        end
    end
    return provider, providerRoot, status
end

-- Helper for the headless selftest: return only the scalar calc-output values
-- the test checks, avoiding conversion of the (possibly circular) full table.
-- Defined as a top-level global (not pob.selftestCalcOutput) because LuaEngine::
-- callGlobal does a single lua_getglobal and cannot resolve dotted names.
function pob_selftestCalcOutput()
    local bm = main.modes.BUILD
    local ct = bm and bm.calcsTab
    if ct and not ct.mainOutput then
        -- Force a build so the output table exists (headless: no displayData, safe)
        ct:BuildOutput()
    end
    local out = ct and ct.mainOutput
    local keys = { "Life", "Mana", "EnergyShield", "DPS", "TotalDPS", "CritChance", "AttackSpeed" }
    local res = { }
    for _, k in ipairs(keys) do
        res[k] = out and out[k] or nil
    end
    return res
end

-- Phase 0d: round-trip check for the zlib bridge. Deflate then Inflate must
-- recover the original string exactly. Returns a table the C++ selftest reads.
function pob_selftestInflate()
    local original = "some test string 12345 !@#$%^&*()"
    local compressed = Deflate(original)
    local roundtrip = Inflate(compressed)
    return {
        ok = (roundtrip == original),
        original = original,
        roundtrip = roundtrip,
        compressedLen = compressed and #compressed or 0,
    }
end

-- Phase 0d: confirm the native-module shims load (lcurl.safe, lzip). Does NOT
-- exercise network/zip — purely a require() success check. Returns booleans.
function pob_selftestRequires()
    local res = { }
    local ok, mod = pcall(require, "lcurl.safe")
    res.lcurl = ok and type(mod) == "table"
    ok, mod = pcall(require, "lzip")
    res.lzip = ok and type(mod) == "table"
    return res
end

-- Phase 2b: build save/load bridge. These are top-level globals (NOT pob.*)
-- because LuaEngine::callGlobal does a single lua_getglobal and cannot resolve
-- dotted names. They wrap the engine's existing Build:SaveDB / Build:LoadDB
-- seam (src/Modules/Build.lua) so the Qt/C++ side can round-trip builds
-- through the exact same xml.lua (common.xml) serialiser the real app uses,
-- preserving .xml / Settings.xml compatibility.
function pob_getBuildXML()
    local bm = main and main.modes and main.modes.BUILD
    if not bm then return nil end
    -- SaveDB composes the full <PathOfBuilding> document via common.xml.
    -- Defensive pcall: Save() walks calc output tables that may be absent in
    -- unusual headless states; we surface nil rather than crashing the bridge.
    local ok, xml = pcall(function() return bm:SaveDB(nil) end)
    if not ok or not xml then return nil end
    return xml
end

function pob_loadBuildXML(xmlText, name)
    if not main then return false end
    if not xmlText then return false end
    -- Mirror src/HeadlessWrapper.lua loadBuildFromXML: re-select BUILD with the
    -- xmlText as the 3rd arg. main:OnFrame always re-runs buildMode:Init when
    -- newMode is set (even if already BUILD), which calls LoadDB(xmlText) and
    -- re-initialises the whole build (tree/items/skills/config).
    main:SetMode("BUILD", false, name or "", xmlText)
    runCallback("OnFrame")
    return true
end

function pob_saveBuild(filename)
    local bm = main and main.modes and main.modes.BUILD
    if not bm or not filename or filename == "" then return false end
    local xmlText = bm:SaveDB(filename)
    if not xmlText then return false end
    local file = io.open(filename, "w+")
    if not file then return false end
    file:write(xmlText)
    file:close()
    return true
end

-- Phase 2b selftest: save the current build to a temp XML string, load it
-- back, and assert the buildName survives the round-trip. Returns a table the
-- C++ selftest reads. Does not crash on failure (surfaces error string).
function pob_selftestSaveLoad()
    local bm = main and main.modes and main.modes.BUILD
    if not bm then
        return { ok = false, error = "no BUILD mode" }
    end
    local before = bm.buildName
    local xml = pob_getBuildXML()
    if not xml then
        return { ok = false, error = "SaveDB returned nil", before = before }
    end
    local okLoad = pcall(function() pob_loadBuildXML(xml, before) end)
    if not okLoad then
        return { ok = false, error = "load failed", before = before, xmlLen = #xml }
    end
    local after = main.modes.BUILD.buildName
    return {
        ok = (after == before),
        before = before,
        after = after,
        xmlLen = #xml,
    }
end

-- Phase 3: LIST-mode (build library) bridge. These are top-level globals (NOT
-- pob.*) because LuaEngine::callGlobal does a single lua_getglobal and cannot
-- resolve dotted names. They wrap the engine's existing BuildList / Build seams
-- (src/Modules/BuildList.lua, src/Classes/BuildListControl.lua, src/Modules/Build.lua)
-- so the Qt/C++ side can browse, open, create, delete, rename, import builds and
-- manage folders through the exact same code paths the real app uses.
--
-- openBuild: load a build .xml by its full file path into BUILD mode. Mirrors
-- BuildListControl:LoadBuild for a file entry (main:SetMode("BUILD", dbFileName,
-- buildName) -> Build:Init -> LoadDBFile).
function pob_openBuild(fullFileName)
    if not main or not fullFileName or fullFileName == "" then return false end
    local buildName = fullFileName:match("([^/\\]+)%.xml$") or "Unnamed build"
    main:SetMode("BUILD", fullFileName, buildName)
    runCallback("OnFrame")
    return true
end

-- createBuild: start a fresh unnamed build (the LIST "New" button behaviour).
function pob_createBuild()
    if not main then return false end
    main:SetMode("BUILD", false, "Unnamed build")
    runCallback("OnFrame")
    return true
end

-- setBuildMode: enter BUILD mode reopening the LAST build the user had open,
-- honoring GetArgs persistence -- the same (dbFileName, buildName) pair the boot
-- path replays from Settings.xml's <Mode> element (Main.lua:LoadSettings ->
-- SetMode -> buildMode:Init). The BUILD mode object (main.modes.BUILD) retains
-- self.dbFileName / self.buildName across a LIST detour, so buildMode:GetArgs()
-- still names the last build after the user toggled LIST and came back. On a
-- genuinely first-ever run (no build ever opened) GetArgs returns nils -> fall
-- back to a fresh "Unnamed build", matching Launch.lua's own no-args boot
-- fallback (Build.lua:84). Driven by LuaEngine::setMode for the BUILD case,
-- which used to hardcode a fresh "Unnamed build" and thus force-discard the
-- last build on every mode-bar toggle back to BUILD.
function pob_setBuildMode()
    if not main then return false end
    local bm = main.modes and main.modes.BUILD
    local dbFileName, buildName
    if bm and bm.GetArgs then
        dbFileName, buildName = bm:GetArgs()
    end
    if buildName then
        -- Reopen the last build. dbFileName may be false for an unsaved build
        -- (buildName set, never written to disk) -> Build:Init keeps it in
        -- memory; a real path -> Build:LoadDBFile reloads it from disk, exactly
        -- as the boot path does. The engine defers the actual swap to the next
        -- OnFrame (SetMode only records self.newMode); LuaEngine::setMode pumps
        -- one OnFrame synchronously after this returns.
        main:SetMode("BUILD", dbFileName, buildName)
    else
        main:SetMode("BUILD", false, "Unnamed build")
    end
    return true
end

-- deleteBuild: remove a build .xml file, then refresh the LIST scan.
function pob_deleteBuild(fullFileName)
    if not fullFileName or fullFileName == "" then return false end
    local ok, msg = os.remove(fullFileName)
    if not ok then
        pob.log("deleteBuild failed: " .. tostring(msg))
        return false
    end
    if main and main.modes.LIST then main.modes.LIST:BuildList() end
    return true
end

-- renameBuild: rename a build .xml file (keeping the .xml extension), then
-- refresh the LIST scan. Mirrors BuildListControl:RenameBuild for a file entry.
function pob_renameBuild(fullFileName, newName)
    if not fullFileName or fullFileName == "" or not newName or newName == "" then
        return false
    end
    local dir = fullFileName:match("(.*[/\\])") or ""
    local newPath = dir .. newName .. ".xml"
    local ok, msg = os.rename(fullFileName, newPath)
    if not ok then
        pob.log("renameBuild failed: " .. tostring(msg))
        return false
    end
    if main and main.modes.LIST then main.modes.LIST:BuildList() end
    return true
end

-- createFolder / deleteFolder: manage build folders under main.buildPath.
function pob_createFolder(name)
    if not main or not name or name == "" then return false end
    local res, msg = MakeDir(main.buildPath .. name)
    if not res then
        pob.log("createFolder failed: " .. tostring(msg))
        return false
    end
    if main.modes.LIST then main.modes.LIST:BuildList() end
    return true
end

function pob_deleteFolder(name)
    if not main or not name or name == "" then return false end
    local res, msg = RemoveDir(main.buildPath .. name)
    if not res then
        pob.log("deleteFolder failed: " .. tostring(msg))
        return false
    end
    if main.modes.LIST then main.modes.LIST:BuildList() end
    return true
end

-- importBuildFromURL: download a PoB share link, inflate+base64-decode the body
-- (the standard pastebin payload), and load it as a new build. Network-dependent;
-- returns false on any failure (no network in the sandbox). Wrapped in pcall so a
-- bad link never crashes the bridge.
function pob_importBuildFromURL(url)
    if not main or not url or url == "" then return false end
    local ok, res = pcall(function()
        local fetchUrl = url
        if buildSites and buildSites.ParseImportLinkFromURI then
            local link = buildSites.ParseImportLinkFromURI(url)
            if link then fetchUrl = link end
        end
        local httpRes = pob.http({ url = fetchUrl, method = "GET", followlocation = 1 })
        if not httpRes or not httpRes.body or httpRes.body == "" then
            return nil, "empty http response"
        end
        local data = httpRes.body:gsub("-", "+"):gsub("_", "/")
        local xmlText = Inflate(common.base64.decode(data))
        if not xmlText then return nil, "inflate/decode failed" end
        main:SetMode("BUILD", false, "Imported Build", xmlText, false, fetchUrl)
        runCallback("OnFrame")
        return true
    end)
    if not ok then
        pob.log("importBuildFromURL error: " .. tostring(res))
        return false
    end
    return res == true
end

-- Phase 3 selftest: switch to LIST mode, read main.modes.LIST.list (the scanned
-- build/folder entries), and return { ok, count, names }. Saves/restores the
-- prior mode so the rest of the headless selftest (which boots into BUILD) stays
-- green. The list may be empty in a fresh sandbox, so we only assert it reads
-- without error and is a table.
function pob_selftestBuildList()
    if not main then return { ok = false, error = "no main" } end
    local prevMode = main.mode
    main:SetMode("LIST")
    runCallback("OnFrame")
    local list = main.modes.LIST and main.modes.LIST.list
    if not list then
        return { ok = false, error = "LIST.list missing" }
    end
    local count = #list
    local names = { }
    for i, entry in ipairs(list) do
        names[i] = entry.buildName or entry.folderName or "?"
    end
    -- Restore the previous mode (BUILD) so subsequent checks remain valid.
    if prevMode and prevMode ~= "LIST" then
        main:SetMode(prevMode, false, "Unnamed build")
        runCallback("OnFrame")
    end
    return { ok = true, count = count, names = names }
end

-- Phase 3 selftest (flow): prove the LIST -> BUILD transition end-to-end through
-- the exact globals the QML buttons invoke. Switches to LIST, then triggers the
-- LIST "New Build" action (pob_createBuild), and asserts the engine lands in
-- BUILD mode with a populated buildName. Restores the prior mode afterwards so
-- the rest of the headless selftest (which boots into BUILD) stays green.
function pob_selftestListFlow()
    if not main then return { ok = false, error = "no main" } end
    local prevMode = main.mode
    -- Enter LIST mode and let OnFrame initialise it.
    main:SetMode("LIST")
    runCallback("OnFrame")
    -- From LIST, perform the "New Build" action (same as the QML createBuild button).
    pob_createBuild()
    runCallback("OnFrame")
    local mode = main.mode
    local buildName = main.modes.BUILD and main.modes.BUILD.buildName
    -- Restore the previous mode so the rest of the selftest stays green.
    if prevMode and prevMode ~= "BUILD" then
        main:SetMode(prevMode, false, "Unnamed build")
        runCallback("OnFrame")
    end
    return {
        ok = (mode == "BUILD" and buildName and buildName ~= ""),
        mode = mode,
        buildName = buildName,
    }
end

-- Part 1.4 selftest: prove the mode bar's BUILD button reopens the LAST build
-- via GetArgs persistence instead of forcing a fresh "Unnamed build" (the bug
-- LuaEngine::setMode used to have). Establishes a distinctively-named build on
-- disk as the "last build", detours to LIST (as the LIST button does), then
-- re-enters BUILD via pob_setBuildMode -- the exact path LuaEngine::setMode
-- ("BUILD") now drives -- and asserts the reopened build carries the same name
-- AND file, reloaded from disk (not a blank Unnamed build). Cleans up the probe
-- file and restores a fresh Unnamed build so later checks stay green. Uses the
-- engine's own ~~sentinel~~ filename convention under buildPath.
function pob_selftestReopenLastBuild()
    if not main then return { ok = false, error = "no main" } end
    local probePath = main.buildPath .. "~~reopen-probe~~.xml"
    MakeDir(main.buildPath)  -- idempotent; buildPath normally already exists
    -- Establish a distinctively-named, on-disk build as the "last build".
    main:SetMode("BUILD", false, "Reopen Probe Build")
    runCallback("OnFrame")
    local bm = main.modes.BUILD
    bm.dbFileName = probePath
    local saved = pob_saveBuild(probePath)
    local wantFile, wantName = bm:GetArgs()   -- GetArgs -> (dbFileName, buildName)
    -- Detour to LIST (mode-bar LIST button).
    main:SetMode("LIST")
    runCallback("OnFrame")
    local inList = main.mode
    -- Re-enter BUILD (mode-bar BUILD button -> LuaEngine::setMode -> this global).
    pob_setBuildMode()
    runCallback("OnFrame")
    local gotMode = main.mode
    local gotName = main.modes.BUILD and main.modes.BUILD.buildName
    local gotFile = main.modes.BUILD and main.modes.BUILD.dbFileName
    -- Restore a clean unnamed build for subsequent checks, THEN delete the probe
    -- file. Order matters: switching away from the probe build shuts it down, and
    -- in devMode buildMode:Shutdown autosaves self.dbFileName (Build.lua:955-965),
    -- which would re-create the probe file after an earlier os.remove. Removing
    -- last guarantees the sandbox is left clean.
    main:SetMode("BUILD", false, "Unnamed build")
    runCallback("OnFrame")
    os.remove(probePath)
    return {
        ok = (saved == true and inList == "LIST" and gotMode == "BUILD"
              and gotName == wantName and gotFile == wantFile),
        saved = saved, inList = inList, gotMode = gotMode,
        wantName = wantName, gotName = gotName,
        wantFile = wantFile, gotFile = gotFile,
    }
end

-- Part 1.4 selftest: cloud robustness. Two assertions, both side-effect-free:
--   (1) GetCloudProvider is a REAL fs-inspecting implementation (not the old
--       null stub) — a missing path reports a different status than an existing
--       one, and the pob.fileAttributes Win32 bridge is present.
--   (2) The errorReadingSettings latch is non-fatal: forcing it, then running a
--       natural LoadSettings against a KNOWN-nonexistent path, CLEARS it (the old
--       one-strike latch early-returned and left it set forever). Uses a scratch
--       userPath so nothing on disk is read/applied, then restores it.
function pob_selftestCloudRobustness()
    local res = { ok = false }
    -- (1) GetCloudProvider real?
    local _, _, statusMissing = GetCloudProvider(_USER_DIR .. "/__pob_no_such_file__.xml")
    local _, _, statusExisting = GetCloudProvider(_SRC_DIR)
    res.statusMissing = tostring(statusMissing)
    res.statusExisting = tostring(statusExisting)
    res.hasFileAttributes = (pob and pob.fileAttributes ~= nil) or false
    res.providerReal = (statusMissing ~= nil and statusExisting ~= nil
                        and statusMissing ~= statusExisting)
    -- (2) latch non-fatal?
    if main then
        local origUserPath = main.userPath
        local origFlag = main.errorReadingSettings
        main.userPath = _USER_DIR .. "/__pob_selftest_missing_dir__/"
        main.errorReadingSettings = true
        main:LoadSettings(true)   -- ignoreBuild: never replays <Mode>
        res.latchCleared = (main.errorReadingSettings == false)
        -- Restore. LoadSettings against the missing scratch path applied nothing.
        main.userPath = origUserPath
        main.errorReadingSettings = origFlag or false
    else
        res.latchCleared = false
    end
    res.ok = not not (res.providerReal and res.hasFileAttributes and res.latchCleared)
    return res
end

-- Part 1.4 selftest: genuine Settings.xml round-trip against the REAL userPath
-- (not a scratch dir — pob_selftestCloudRobustness already covers the latch
-- logic in isolation). Backs up the current on-disk Settings.xml bytes (or
-- records "file did not exist"), writes a distinctive defaultCharLevel via the
-- real main:SaveSettings(), clears the in-memory value (simulating a fresh
-- process that hasn't loaded settings yet), re-reads it via the real
-- main:LoadSettings(), and asserts the value survived the disk round trip.
-- Always restores the exact original file bytes (or removes the file if it
-- didn't exist before) in a pcall'd cleanup so a mid-test error can't leave the
-- user's real settings file holding a test value.
function pob_selftestSettingsRoundTrip()
    local res = { ok = false }
    if not main then res.error = "no main"; return res end
    local path = main.userPath .. "Settings.xml"
    -- Back up whatever is on disk right now (nil = file did not exist).
    local origBytes
    do
        local f = io.open(path, "rb")
        if f then
            origBytes = f:read("*a")
            f:close()
        end
    end
    local origInMemory = main.defaultCharLevel
    local ok, err = pcall(function()
        -- Pick a distinctive value that can't collide with the real setting.
        local probeVal = (origInMemory == 42) and 43 or 42
        main.defaultCharLevel = probeVal
        main:SaveSettings()
        res.saveErrorLatched = main.errorReadingSettings
        -- Simulate "haven't loaded settings yet in this process": clear memory,
        -- then read back from disk via the real LoadSettings path.
        main.defaultCharLevel = nil
        main:LoadSettings(true) -- ignoreBuild: don't replay <Mode> mid-selftest
        res.loadErrorLatched = main.errorReadingSettings
        res.wantVal = probeVal
        res.gotVal = main.defaultCharLevel
        res.roundTripOk = (main.defaultCharLevel == probeVal)
    end)
    res.pcallOk = ok
    if not ok then res.error = tostring(err) end
    -- Cleanup: restore the exact original file bytes (or remove if none existed)
    -- and reload so main's in-memory state matches the real file again.
    pcall(function()
        if origBytes then
            local f = io.open(path, "wb")
            if f then
                f:write(origBytes)
                f:close()
            end
        else
            os.remove(path)
        end
        main.defaultCharLevel = origInMemory
        main:LoadSettings(true)
    end)
    res.ok = not not (ok and res.roundTripOk and not res.saveErrorLatched and not res.loadErrorLatched)
    return res
end

-- Phase 5a: ItemsTab (ITEMS view) bridge. Top-level globals (NOT pob.*) because
-- LuaEngine::callGlobal does a single lua_getglobal and cannot resolve dotted
-- names. Exposes main.modes.BUILD.itemsTab to QML as plain tables (items,
-- equipped slots, tree jewel sockets). Each item carries id/name/baseName/type/
-- rarity/quality/level/modLines/isEquipped/slotName/socketCount.
-- The engine stores item quality in the misspelled field `quality` (Item.lua)
-- and item level in `requirements.level`; both are read defensively.

-- Collect the display strings for an item's mod lines (implicit/enchant/
-- scourge/crucible/explicit), in display order. Each source entry has a
-- `.line` string.
local function pob_itemModLines(item)
    local out = { }
    local function add(list)
        if not list then return end
        for _, m in ipairs(list) do
            if m and m.line then out[#out + 1] = m.line end
        end
    end
    add(item.implicitModLines)
    add(item.enchantModLines)
    add(item.scourgeModLines)
    add(item.crucibleModLines)
    add(item.explicitModLines)
    return out
end

function pob_getItems()
    local it = main and main.modes and main.modes.BUILD and main.modes.BUILD.itemsTab
    if not it then return nil end
    local out = { }
    for _, id in ipairs(it.itemOrderList) do
        local item = it.items[id]
        if item then
            local slot = it:GetEquippedSlotForItem(item)
            out[#out + 1] = {
                id = item.id,
                name = item.name or "?",
                baseName = item.baseName or "",
                type = item.type or "",
                rarity = item.rarity or "UNIQUE",
                quality = item.quality or 0,
                level = (item.requirements and item.requirements.level) or 0,
                modLines = pob_itemModLines(item),
                isEquipped = slot ~= nil,
                slotName = slot and slot.slotName or "",
                socketCount = #(item.sockets or { }),
            }
        end
    end
    return out
end

function pob_getItemSlots()
    local it = main and main.modes and main.modes.BUILD and main.modes.BUILD.itemsTab
    if not it then return nil end
    local out = { }
    for _, slot in ipairs(it.orderedSlots) do
        if not slot.nodeId and slot.selItemId and slot.selItemId ~= 0 then
            local item = it.items[slot.selItemId]
            out[#out + 1] = {
                slotName = slot.slotName,
                selItemId = slot.selItemId,
                itemName = item and item.name or "",
            }
        end
    end
    return out
end

function pob_getJewelSockets()
    local it = main and main.modes and main.modes.BUILD and main.modes.BUILD.itemsTab
    if not it then return nil end
    local out = { }
    for nodeId, slot in pairs(it.sockets) do
        if slot.selItemId and slot.selItemId ~= 0 then
            local item = it.items[slot.selItemId]
            out[#out + 1] = {
                nodeId = nodeId,
                selItemId = slot.selItemId,
                itemName = item and item.name or "",
            }
        end
    end
    return out
end

function pob_addItemFromRaw(raw)
    local it = main and main.modes and main.modes.BUILD and main.modes.BUILD.itemsTab
    if not it or not raw then return nil end
    -- CreateDisplayItemFromRaw returns nil; on success it sets self.displayItem.
    it:CreateDisplayItemFromRaw(raw)
    local item = it.displayItem
    if not item or not item.base then return nil end
    it:AddItem(item, true)
    it:PopulateSlots()
    return item.id
end

function pob_deleteItem(id)
    local it = main and main.modes and main.modes.BUILD and main.modes.BUILD.itemsTab
    if not it or not id then return false end
    local item = it.items[id]
    if item then
        it:DeleteItem(item)
        it:PopulateSlots()
    end
    return true
end

function pob_selftestItems()
    local it = main and main.modes and main.modes.BUILD and main.modes.BUILD.itemsTab
    if not it then return { ok = false, error = "no itemsTab" } end
    local before = #it.itemOrderList
    local raw = "Rarity: Rare\nTest Ring\nGold Ring\nQuality: 0\nSockets: R-B\n"
    -- CreateDisplayItemFromRaw returns nil in all cases; on success it sets
    -- self.displayItem to the parsed item (only if the base resolved).
    it:CreateDisplayItemFromRaw(raw)
    local item = it.displayItem
    if not item or not item.base then
        return { ok = false, error = "item create failed" }
    end
    it:AddItem(item, true)
    local after = #it.itemOrderList
    -- cleanup so the build isn't mutated for later phases
    it:DeleteItem(item)
    return { ok = after == before + 1, before = before, after = after, count = after }
end

-- Phase 5b: SkillsTab (SKILLS view) bridge. Top-level globals (NOT pob.*) because
-- LuaEngine::callGlobal does a single lua_getglobal and cannot resolve dotted names.
-- Exposes main.modes.BUILD.skillsTab (socket groups + active-skill DPS list) to QML.
-- The engine stores socket groups in skillsTab.socketGroupList (a list of tables
-- with label/slot/enabled/gemList/mainActiveSkill/displaySkillList). Gems are plain
-- tables (gemInstance) with nameSpec/level/quality/enabled. The active-skill DPS
-- list is derived by selecting each display skill as the main skill and recalculating
-- (mirroring the CALCS-tab skill selector), then restoring the original selection.

-- Read the socket-group list as plain tables. Each entry carries an `id` (its
-- 1-based index in socketGroupList, stable for the lifetime of the build), the
-- user title (label), the item slot it is socketed in (or ""), whether it is
-- enabled, the list of gems (name/level/quality/enabled), and the index of the
-- active skill within the group (mainActiveSkill).
function pob_getSocketGroups()
    local st = main and main.modes and main.modes.BUILD and main.modes.BUILD.skillsTab
    if not st then return nil end
    local out = { }
    for i, group in ipairs(st.socketGroupList) do
        local gems = { }
        for _, gem in ipairs(group.gemList or {}) do
            gems[#gems + 1] = {
                name = gem.nameSpec or gem.name or "?",
                level = gem.level or 1,
                quality = gem.quality or 0,
                enabled = gem.enabled ~= false,
            }
        end
        out[#out + 1] = {
            id = i,
            label = group.label or "",
            slot = group.slot or "",
            enabled = group.enabled ~= false,
            gems = gems,
            mainActiveSkill = group.mainActiveSkill or 1,
        }
    end
    return out
end

-- Read the active-skill DPS list. For each display skill in each socket group we
-- temporarily select it as the main skill, recalculate, and read the resulting
-- DPS from calcsTab.mainOutput. State (build.mainSocketGroup and each group's
-- mainActiveSkill/mainActiveSkillCalcs) is saved and restored afterwards so the
-- bridge never leaves the build on a different skill than it started on.
function pob_getActiveSkills()
    local bm = main and main.modes and main.modes.BUILD
    local st = bm and bm.skillsTab
    local ct = bm and bm.calcsTab
    if not st or not ct then return nil end
    if not ct.mainOutput then
        pcall(function() ct:BuildOutput() end)
    end
    local out = { }
    local savedMainGroup = bm.mainSocketGroup
    local savedMainActive = { }
    for gi, group in ipairs(st.socketGroupList) do
        savedMainActive[gi] = { group.mainActiveSkill, group.mainActiveSkillCalcs }
        for si, activeSkill in ipairs(group.displaySkillList or {}) do
            local ge = activeSkill.activeEffect
            local name = (ge and ge.grantedEffect and (ge.grantedEffect.name or ge.grantedEffect.id)) or "?"
            -- Select this skill as the main skill and recalc.
            bm.mainSocketGroup = gi
            group.mainActiveSkill = si
            group.mainActiveSkillCalcs = si
            local ok = pcall(function() ct:BuildOutput() end)
            local dps, totalDps, minionDps = 0, 0, 0
            if ok and ct.mainOutput then
                local o = ct.mainOutput
                dps = o.DPS or 0
                totalDps = o.TotalDPS or 0
                minionDps = (o.Minion and o.Minion.TotalDPS) or 0
            end
            out[#out + 1] = {
                name = name,
                dps = dps,
                totalDps = totalDps,
                minionDps = minionDps,
                socketGroupLabel = group.label or "",
                socketGroupIndex = gi,
                displaySkillIndex = si,
                isMain = (gi == savedMainGroup
                          and si == (savedMainActive[gi] and savedMainActive[gi][1] or 1)),
            }
        end
    end
    -- Restore the original main skill selection and recalc once more so the
    -- engine's mainOutput reflects the real main skill again.
    bm.mainSocketGroup = savedMainGroup
    for gi, group in ipairs(st.socketGroupList) do
        if savedMainActive[gi] then
            group.mainActiveSkill = savedMainActive[gi][1]
            group.mainActiveSkillCalcs = savedMainActive[gi][2]
        end
    end
    pcall(function() ct:BuildOutput() end)
    return out
end

-- Create a socket group with a single gem and recalculate. Returns the new
-- group's id (its 1-based index in socketGroupList), or nil on failure.
function pob_addSocketGroupWithGem(label, gemName)
    local bm = main and main.modes and main.modes.BUILD
    local st = bm and bm.skillsTab
    if not st or not gemName or gemName == "" then return nil end
    local group = { label = label or "New Group", enabled = true, gemList = { } }
    table.insert(st.socketGroupList, group)
    table.insert(group.gemList, {
        nameSpec = gemName,
        level = 1,
        quality = 0,
        enabled = true,
        enableGlobal1 = true,
        enableGlobal2 = true,
        count = 1,
        new = true,
    })
    st:ProcessSocketGroup(group)
    bm.buildFlag = true
    pcall(runCallback, "OnFrame")
    return #st.socketGroupList
end

-- Set the active skill for a socket group (by id/index) and recalculate.
-- socketGroupId is the 1-based index in socketGroupList; index is the 1-based
-- display-skill index within the group.
function pob_setActiveSkill(socketGroupId, index)
    local bm = main and main.modes and main.modes.BUILD
    local st = bm and bm.skillsTab
    if not st then return false end
    local group = st.socketGroupList[socketGroupId]
    if not group then return false end
    bm.mainSocketGroup = socketGroupId
    group.mainActiveSkill = index
    group.mainActiveSkillCalcs = index
    bm.modFlag = true
    bm.buildFlag = true
    pcall(runCallback, "OnFrame")
    return true
end

-- Phase 5b selftest: add a socket group with a gem, assert the group count grew
-- by exactly one and the new group contains the gem. ADDITIVE: runs before
-- SELFTEST PASSED.
function pob_selftestSkills()
    local bm = main and main.modes and main.modes.BUILD
    local st = bm and bm.skillsTab
    if not st then return { ok = false, error = "no skillsTab" } end
    local before = #st.socketGroupList
    local id = pob_addSocketGroupWithGem("Test Group", "Fireball")
    local after = #st.socketGroupList
    local grp = id and st.socketGroupList[id]
    local gemOk = grp and #(grp.gemList or {}) > 0
    return {
        ok = (after == before + 1) and (id ~= nil) and gemOk,
        before = before,
        after = after,
        id = id,
        gemOk = gemOk,
    }
end

-- Phase 5c: CalcsTab (CALCS view) bridge. Top-level globals (NOT pob.*) because
-- LuaEngine::callGlobal does a single lua_getglobal and cannot resolve dotted
-- names. Exposes main.modes.BUILD.calcsTab's computed output (summary numbers +
-- the rendered CalcSection list with per-stat values and breakdown keys) to QML.
-- The section stat values are formatted with the engine's own formatCalcStr (the
-- same helper CalcSectionControl:Draw uses) against the CALCS-mode actor
-- (calcsEnv.player / .minion), while the summary numbers come from mainOutput (the
-- MAIN-mode output). Breakdown data lives in actor.breakdown[breakdownKey].
function pob_getCalcOutput()
    local bm = main and main.modes and main.modes.BUILD
    local ct = bm and bm.calcsTab
    if not ct then return nil end
    if not ct.mainOutput then
        pcall(function() ct:BuildOutput() end)
    end
    if not ct.mainOutput then return nil end
    local out = ct.mainOutput

    local summary = {
        life = out.Life,
        mana = out.Mana,
        es = out.EnergyShield,
        totalDps = out.TotalDPS,
        dps = out.DPS,
        critChance = out.CritChance,
        attackSpeed = out.AttackSpeed,
    }

    -- Actor for section stat values (CALCS-mode output).
    local actor = nil
    if ct.calcsEnv then
        actor = ct.input.showMinion and ct.calcsEnv.minion or ct.calcsEnv.player
    end

    local sections = { }
    if ct.sectionList then
        for _, section in ipairs(ct.sectionList) do
            local secLabel = section.id
            if section.subSection and section.subSection[1] and section.subSection[1].label then
                secLabel = section.subSection[1].label
            end
            local stats = { }
            for _, subSec in ipairs(section.subSection or {}) do
                for _, rowData in ipairs(subSec.data or {}) do
                    if type(rowData) == "table" and rowData.label then
                        -- One stat per column that carries a format string.
                        for ci, colData in ipairs(rowData) do
                            if type(colData) == "table" and colData.format then
                                local value = ""
                                if actor and formatCalcStr then
                                    local ok, v = pcall(formatCalcStr, colData.format, actor, colData)
                                    if ok and v then value = tostring(v) end
                                end
                                -- Find a breakdown key among the column's sub-entries.
                                local breakdownKey = nil
                                for _, sub in ipairs(colData) do
                                    if type(sub) == "table" and sub.breakdown then
                                        breakdownKey = sub.breakdown
                                        break
                                    end
                                end
                                stats[#stats + 1] = {
                                    label = rowData.label,
                                    value = value,
                                    statType = rowData.statType or rowData.color or nil,
                                    flag = rowData.flag or nil,
                                    hasBreakdown = breakdownKey ~= nil,
                                    breakdown = breakdownKey,
                                }
                            end
                        end
                    end
                end
            end
            if #stats > 0 then
                sections[#sections + 1] = { label = secLabel, stats = stats }
            end
        end
    end

    return { summary = summary, sections = sections }
end

-- Return the breakdown lines for a stat, addressed by its breakdown key (the
-- `breakdown` field returned by pob_getCalcOutput). Mirrors
-- CalcBreakdownControl:AddBreakdownSection's lookup against actor.breakdown.
-- Returns { lines = {...}, hasTable = bool } or nil when no breakdown exists.
function pob_getCalcBreakdown(sectionLabel, statLabel)
    local bm = main and main.modes and main.modes.BUILD
    local ct = bm and bm.calcsTab
    if not ct or not ct.calcsEnv then return nil end
    local actor = ct.input.showMinion and ct.calcsEnv.minion or ct.calcsEnv.player
    if not actor or not actor.breakdown then return nil end
    local key = statLabel
    local bd
    if key then
        local ns, name = key:match("^(%a+)%.(%a+)$")
        if ns then
            bd = actor.breakdown[ns] and actor.breakdown[ns][name]
        else
            bd = actor.breakdown[key]
        end
    end
    if not bd then return nil end
    local res = { lines = { }, hasTable = false }
    for _, line in ipairs(bd) do
        if type(line) == "string" then
            -- Strip SimpleGraphic colour markup so the QML popup is clean.
            res.lines[#res.lines + 1] = line:gsub("%^x%x%x%x%x%x%x", ""):gsub("%^%d", "")
        end
    end
    if (bd.rowList and #bd.rowList > 0) or (bd.slots and #bd.slots > 0)
       or (bd.reservations and #bd.reservations > 0)
       or (bd.damageTypes and #bd.damageTypes > 0) then
        res.hasTable = true
    end
    return res
end

-- Phase 5c selftest: read the calc output, assert it has a non-nil summary and
-- at least one section with at least one stat. ADDITIVE: runs before
-- SELFTEST PASSED.
function pob_selftestCalcs()
    local d = pob_getCalcOutput()
    if not d then return { ok = false, error = "no calc output" } end
    local statCount = 0
    for _, s in ipairs(d.sections) do statCount = statCount + #s.stats end
    return {
        ok = (statCount > 0 and d.summary ~= nil),
        sections = #d.sections,
        statCount = statCount,
    }
end

-- Phase 5d: CONFIG view (ConfigTab) bridge.
-- Exposes the build's configuration options (src/Modules/ConfigOptions.lua) to
-- QML, and lets the UI write values back into the active config set's input
-- table (build.configTab.configSets[activeConfigSetId].input), mirroring the
-- control callbacks in src/Classes/ConfigTab.lua.
--
-- NOTE: the task spec refers to `build.config[name]`, but the real storage in
-- this engine is `build.configTab.configSets[activeConfigSetId].input[name]`
-- (there is no `build.config` alias). We read/write that table directly.

local _configOptionsCache = nil
local function getConfigVarList()
    if _configOptionsCache then return _configOptionsCache end
    local ok, varList = pcall(LoadModule, "Modules/ConfigOptions")
    if ok and varList then _configOptionsCache = varList end
    return _configOptionsCache
end

-- Return the active config-set input table, or nil if unavailable.
local function getConfigInput()
    local bm = main and main.modes and main.modes.BUILD
    if not bm or not bm.configTab then return nil end
    local ct = bm.configTab
    local setId = ct.activeConfigSetId or 1
    local set = ct.configSets and ct.configSets[setId]
    if not set then return nil end
    return set.input
end

-- Map a ConfigOptions type to the simplified QML vocabulary
-- (boolean|number|list|string) required by the CONFIG view contract.
local function mapConfigType(t)
    if t == "check" then
        return "boolean"
    elseif t == "count" or t == "integer" or t == "countAllowZero" or t == "float" then
        return "number"
    elseif t == "list" then
        return "list"
    elseif t == "text" then
        return "string"
    end
    return t
end

-- Return a flat list of config option descriptors, grouped implicitly by the
-- `section` field. We expose ALL options (including conditional ones) so the
-- QML view can render the full configuration surface; the value is the current
-- build input (or a sensible default when unset).
function pob_getConfigOptions()
    local input = getConfigInput()
    if not input then return nil end
    local varList = getConfigVarList()
    if not varList then return nil end

    local out = { }
    local currentSection = nil
    for _, varData in ipairs(varList) do
        if varData.section then
            currentSection = varData.section
        elseif varData.var then
            local t = varData.type
            local value = input[varData.var]
            if value == nil then
                if t == "check" then
                    value = false
                elseif t == "count" or t == "integer" or t == "countAllowZero" or t == "float" then
                    value = 0
                elseif t == "text" then
                    value = ""
                elseif t == "list" and varData.defaultIndex and varData.list then
                    value = varData.list[varData.defaultIndex].val
                end
            end
            local entry = {
                name = varData.var,
                label = varData.label or varData.var,
                type = mapConfigType(t),
                value = value,
                section = currentSection,
                tooltip = varData.tooltip or nil,
            }
            if t == "list" and varData.list then
                local opts = { }
                for _, o in ipairs(varData.list) do
                    opts[#opts + 1] = { label = o.label, val = o.val }
                end
                entry.options = opts
            end
            out[#out + 1] = entry
        end
    end
    return out
end

-- Write a config value back into the active config set and trigger a rebuild,
-- mirroring ConfigTab's control callbacks (BuildModList + buildFlag + OnFrame).
function pob_setConfigOption(name, value)
    local input = getConfigInput()
    if not input or not name then return false end
    input[name] = value
    local bm = main and main.modes and main.modes.BUILD
    if bm and bm.configTab then
        pcall(function() bm.configTab:BuildModList() end)
    end
    if bm then bm.buildFlag = true end
    pcall(runCallback, "OnFrame")
    return true
end

-- Phase 5d selftest: read the config options, toggle a boolean (check) option,
-- assert the value actually flipped in the build, then toggle it back.
-- ADDITIVE: runs before SELFTEST PASSED.
function pob_selftestConfig()
    local opts = pob_getConfigOptions()
    if not opts then return { ok = false, error = "no config options" } end
    local count = #opts
    local target = nil
    for _, o in ipairs(opts) do
        if o.type == "boolean" then
            target = o
            break
        end
    end
    if not target then
        return { ok = true, count = count, note = "no boolean option to toggle" }
    end
    local before = target.value
    local flipped = not before
    local okSet = pob_setConfigOption(target.name, flipped)
    local opts2 = pob_getConfigOptions()
    local after = nil
    for _, o in ipairs(opts2) do
        if o.name == target.name then after = o.value; break end
    end
    local flippedOk = (after == flipped)
    pob_setConfigOption(target.name, before)
    return {
        ok = (okSet == true and flippedOk == true),
        count = count,
        toggled = target.name,
        before = before,
        after = after,
    }
end

-- Phase 5e: Notes/Import/Compare/Party (utility) tabs bridge.
-- Top-level globals (NOT pob.*) because LuaEngine::callGlobal does
-- a single lua_getglobal and cannot resolve dotted names. Wires the
-- four remaining viewList views (NOTES key=6, IMPORT key=7, PARTY
-- key=8, COMPARE key=9, all group=utility) to the engine's
-- existing tab seams (notesTab / importTab / partyTab / compareTab).
--
-- NOTES: the notes text is stored in the NotesTab's edit control
-- buffer (self.controls.edit.buf). We mirror it onto build.notes (the
-- contract field the C++ NotesController reads) and flag notesTab.modFlag
-- so the build's unsaved state tracks the edit (mirrors NotesTab:Draw).
function pob_getNotes()
    local nt = main and main.modes and main.modes.BUILD and main.modes.BUILD.notesTab
    if not nt or not nt.controls or not nt.controls.edit then return "" end
    return nt.controls.edit.buf or ""
end

function pob_setNotes(text)
    local bm = main and main.modes and main.modes.BUILD
    if not bm or not bm.notesTab or not bm.notesTab.controls or not bm.notesTab.controls.edit then
        return false
    end
    local t = text or ""
    bm.notesTab.controls.edit.buf = t
    bm.notes = t -- contract field for the C++ controller
    bm.notesTab.modFlag = true
    return true
end

-- IMPORT: parse a build share code (base64 with -/_ URL-safe
-- substitutions) and load it as a new build, mirroring the engine's
-- own import path (CompareTab:ImportFromCode / pob_importBuildFromURL).
-- Network pastebin fetch is not exercised headlessly; this only decodes
-- a code the user pasted. Wrapped in pcall so a bad code never
-- crashes the bridge.
function pob_importFromCode(code)
    if not main or not code or code == "" then return false end
    local ok, res = pcall(function()
        local data = code:gsub("-", "+"):gsub("_", "/")
        local xmlText = Inflate(common.base64.decode(data))
        if not xmlText then return false, "decode failed" end
        main:SetMode("BUILD", false, "Imported Build", xmlText, false, "")
        runCallback("OnFrame")
        return true
    end)
    if not ok then
        pob.log("importFromCode error: " .. tostring(res))
        return false
    end
    return res == true
end

-- COMPARE: return the comparison build entries (compareTab.compareEntries)
-- as plain tables { name, buildName, level, class }. Each entry is a
-- lightweight Build wrapper (CompareEntry) carrying buildName,
-- characterLevel and spec.curClassName (its class). Empty in a fresh
-- headless build.
function pob_getCompareEntries()
    local ct = main and main.modes and main.modes.BUILD and main.modes.BUILD.compareTab
    if not ct or not ct.compareEntries then return {} end
    local out = {}
    for i, entry in ipairs(ct.compareEntries) do
        out[#out + 1] = {
            name = entry.label or entry.buildName or ("Build " .. i),
            buildName = entry.buildName or "",
            level = entry.characterLevel or 0,
            class = (entry.spec and entry.spec.curClassName) or "",
        }
    end
    return out
end

-- PARTY: return the party members. In this engine the PartyTab stores
-- imported party buffs in self.actor (Aura/Curse/Warcry/Link) and the
-- enemy mod list; there is no live network party roster. We expose the
-- buff categories that ARE present (Aura/Curse/Warcry/Link) as rows
-- so the QML PARTY view can render without crashing. Empty unless
-- a build code was imported.
function pob_getPartyMembers()
    local pt = main and main.modes and main.modes.BUILD and main.modes.BUILD.partyTab
    if not pt then return {} end
    local out = {}
    local actor = pt.actor
    if actor then
        for _, cat in ipairs({ "Aura", "Curse", "Warcry", "Link" }) do
            local t = actor[cat]
            local count = 0
            if t then
                for _ in pairs(t) do count = count + 1 end
            end
            if count > 0 then
                out[#out + 1] = {
                    name = cat,
                    level = 0,
                    class = "",
                    count = count,
                }
            end
        end
    end
    return out
end

-- Phase 5e selftest: verify notes get/set round-trips; verify
-- import/compare/party accessors return tables (possibly empty).
-- ADDITIVE: runs before SELFTEST PASSED.
function pob_selftestMiscTabs()
    local res = { ok = false }
    -- Notes round-trip
    local before = pob_getNotes()
    local marker = "___pob_selftest_notes_" .. tostring(math.floor(GetTime()))
    pob_setNotes(marker)
    local after = pob_getNotes()
    res.notesOk = (after == marker)
    pob_setNotes(before) -- restore
    -- Import accessor: confirm it is callable and returns a boolean
    -- (false for an invalid code; must not crash).
    local okImport, imp = pcall(function() return pob_importFromCode("not-a-real-code") end)
    res.importOk = okImport and (imp == true or imp == false)
    -- Compare accessor returns a table
    local cmp = pob_getCompareEntries()
    res.compareOk = type(cmp) == "table"
    res.compareCount = #cmp
    -- Party accessor returns a table
    local party = pob_getPartyMembers()
    res.partyOk = type(party) == "table"
    res.partyCount = #party
    res.ok = not not (res.notesOk and res.importOk and res.compareOk and res.partyOk)
    return res
end

-- Boot the engine (same sequence as src/HeadlessWrapper.lua).
-- `arg` is set by the C host (LuaEngine::init) from the process CLI args before
-- this bootstrap runs; keep it if present (engine reads arg[1] for import links),
-- otherwise default to an empty table.
arg = arg or { }
dofile(_SRC_DIR .. "/Launch.lua")
mainObject.continuousIntegrationMode = os.getenv("CI")

-- Surface engine errors (launch:ShowErrMsg is a silent no-op in headless hosts).
if mainObject and mainObject.ShowErrMsg then
    local origShowErr = mainObject.ShowErrMsg
    mainObject.ShowErrMsg = function(self, fmt, ...)
        local ok, msg = pcall(string.format, fmt, ...)
        pob.log("ENGINE ERROR: " .. (ok and msg or fmt))
    end
end

runCallback("OnInit")
runCallback("OnFrame") -- initial frame so the mode initialises
-- Force a clean, fully-initialised build. The engine may have tried to restore a
-- stale last-session build (e.g. ~~temp~~.xml) from Settings.xml, which fails
-- headless and causes buildMode:Init to early-return before populating viewList /
-- calcsTab. Re-selecting BUILD with no dbFileName makes LoadDBFile return nil so
-- Init continues and the bridge/selftest can read the real state.
if main and main.modes and main.modes.BUILD then
    main:SetMode("BUILD", false, "Unnamed build")
    runCallback("OnFrame")
end

-- ===========================================================================
-- Part 1.4 (bullet 5): Toast notification bridge.
--
-- ToastNotification (Modules/ToastNotification.lua) is a plain global table
-- (Main.lua: `ToastNotification = LoadModule(...)`) whose :Render() method
-- draws via stubbed SimpleGraphic globals -- a dead path under invariant #1
-- (QML owns rendering). Per invariant #2 we don't edit that module; instead
-- this wraps its Add/Update/Remove/Clear methods at host-bootstrap time (a
-- host seam) so each mutation also updates a local mirror list and notifies
-- Qt via pob.toastsChanged(), mirroring the pob.cloudErrorPopup pattern
-- above (Lua-initiated push, C++ emits a Qt signal QML listens to).
--
-- MUST run after runCallback("OnInit") above: `ToastNotification` (and
-- `main`) don't exist as globals until launch:OnInit() -> PLoadModule(
-- "Modules/Main") runs, which OnInit triggers, not dofile(Launch.lua) itself
-- (Launch.lua only DEFINES launch:OnInit at dofile time -- see Launch.lua:20
-- vs :71). Installing this wrap any earlier silently no-ops (the `if
-- ToastNotification then` guard below sees nil), which is exactly the bug
-- this comment is here to prevent regressing.
--
-- Deviation from legacy timing (documented): legacy's HIDING state is only
-- reaped by a later :Render() call, which relied on the old 30ms frame-poll.
-- The Qt host is event-driven (no polling OnFrame loop -- see STATUS.md), so
-- a deferred removal could sit forever with nothing to reap it. Remove()
-- here always removes immediately from the Lua-side list/mirror regardless
-- of the `immediate` arg; QML owns any fade-out animation on its own side
-- (Toast.qml), which is purely presentational and doesn't need the Lua
-- model to stay around mid-animation.
local _toastMirror = { }   -- ordered list of {id=, message=}
local _toastIndex = { }    -- id -> mirror entry
local function _toastNotify()
    if pob and pob.toastsChanged then pob.toastsChanged() end
end

if ToastNotification then
    local origToastAdd = ToastNotification.Add
    function ToastNotification:Add(message)
        local id = origToastAdd(self, message)
        local entry = { id = id, message = message }
        _toastMirror[#_toastMirror + 1] = entry
        _toastIndex[id] = entry
        _toastNotify()
        return id
    end

    local origToastUpdate = ToastNotification.Update
    function ToastNotification:Update(id, message)
        local ok = origToastUpdate(self, id, message)
        local entry = _toastIndex[id]
        if entry then entry.message = message end
        _toastNotify()
        return ok
    end

    local origToastRemove = ToastNotification.Remove
    function ToastNotification:Remove(id, immediate)
        local ok = origToastRemove(self, id, true)
        local entry = _toastIndex[id]
        if entry then
            for i, e in ipairs(_toastMirror) do
                if e.id == id then table.remove(_toastMirror, i); break end
            end
            _toastIndex[id] = nil
        end
        _toastNotify()
        return ok
    end

    local origToastClear = ToastNotification.Clear
    function ToastNotification:Clear(immediate)
        origToastClear(self, true)
        _toastMirror = { }
        _toastIndex = { }
        _toastNotify()
    end
end

-- pob_getToasts() -> [{id, message}, ...] in display order (oldest first).
-- Top-level global (NOT pob.*) because LuaEngine::callGlobal does a single
-- lua_getglobal and cannot resolve dotted names.
function pob_getToasts()
    local out = { }
    for i, e in ipairs(_toastMirror) do
        out[i] = { id = e.id, message = e.message }
    end
    return out
end

-- pob_dismissToast(id) -> the QML dismiss-button handoff; mirrors the
-- legacy dismiss callback (ToastNotification.lua:178-184) minus the
-- dismissedIds bookkeeping (no legacy caller polls WasDismissed() from the
-- QML toast stack; TreeTab's suggested-path toasts aren't ported yet).
function pob_dismissToast(id)
    if not id then return false end
    return ToastNotification:Remove(id, true)
end

-- Part 1.4 selftest: add -> list -> update -> dismiss -> clear, asserting
-- the mirror stays consistent with each mutation.
function pob_selftestToast()
    local res = { ok = false }
    local id = ToastNotification:Add("Title\nBody line")
    local afterAdd = pob_getToasts()
    local foundAfterAdd, addedMessage = false, nil
    for _, t in ipairs(afterAdd) do
        if t.id == id then foundAfterAdd = true; addedMessage = t.message end
    end
    res.foundAfterAdd = foundAfterAdd and (addedMessage == "Title\nBody line")

    ToastNotification:Update(id, "Title2\nBody2")
    local afterUpdate = pob_getToasts()
    local updatedOk = false
    for _, t in ipairs(afterUpdate) do
        if t.id == id and t.message == "Title2\nBody2" then updatedOk = true end
    end
    res.updatedOk = updatedOk

    pob_dismissToast(id)
    local afterDismiss = pob_getToasts()
    local dismissedOk = true
    for _, t in ipairs(afterDismiss) do
        if t.id == id then dismissedOk = false end
    end
    res.dismissedOk = dismissedOk

    ToastNotification:Add("Second")
    ToastNotification:Add("Third")
    ToastNotification:Clear()
    res.clearOk = (#pob_getToasts() == 0)

    res.ok = not not (res.foundAfterAdd and res.updatedOk and res.dismissedOk and res.clearOk)
    return res
end

-- Phase 4a: passive-tree data bridge. Top-level globals (NOT pob.*) because
-- Exposes the passive tree to QML as plain tables (nodes, groups, connectors,
-- bounds, assets, assetBasePath). The tree GEOMETRY is global (main.tree[treeVersion])
-- so the full tree renders even with no build loaded; Node `alloc` comes from
-- spec.nodes[id].alloc (the build's live allocation state) when a build exists,
-- otherwise every node is treated as unallocated (full tree, nothing highlighted).
-- Memo for loadSourceSprites (keyed by tree version; persists across calls).
local _sourceSpritesCache = { }
function pob_getTreeData()
local bm = main and main.modes and main.modes.BUILD
local treeVersion = latestTreeVersion
local tree = (main and main.tree and treeVersion and main.tree[treeVersion])
             or (bm and bm.spec and bm.spec.tree)
if not tree then return nil end
local spec = (bm and bm.spec) or { nodes = { } }

local function resolveAsset(assetName, iconKey)
    local asset = tree.assets[assetName]
    if not asset or not asset.filename then return nil end
    local base = asset.filename:match("([^/]+)%?") or asset.filename:match("([^/]+)$")
    local localPath = (_SRC_DIR .. "/TreeData/" .. tree.treeVersion .. "/" .. base):gsub("\\", "/")
    local f = io.open(localPath, "r")
    if not f then return nil end
    f:close()
    local rect
    if asset.coords then
        rect = asset.coords[iconKey]
        if not rect then
            for _, v in pairs(asset.coords) do rect = v; break end
        end
    end
    if not rect then rect = { x = 0, y = 0, w = asset.w or 0, h = asset.h or 0 } end
    if not rect.w or rect.w <= 0 or not rect.h or rect.h <= 0 then return nil end
    return { atlas = "file:///" .. localPath, sx = rect.x, sy = rect.y, sw = rect.w, sh = rect.h }
end

-- Find the first sub-rect table ({ [1]=x, [2]=y, [3]=x+w, [4]=y+h, ... }) inside t.
local function firstRect(t)
    if type(t) ~= "table" then return nil end
    if t[1] ~= nil and t[3] ~= nil then return t end
    for _, v in pairs(t) do
        if type(v) == "table" and v[1] ~= nil and v[3] ~= nil then return v end
    end
    return nil
end

local function nodeSprite(node, alloc)
    local sprites = node.sprites
    if not sprites then return nil end
    -- node.sprites[state] is the DIRECT sub-rect in the sprite sheet, built in
    -- PassiveTree.lua as { handle, width, height, [1]=x, [2]=y, [3]=x+w, [4]=y+h }.
    -- Because NewImageHandle() is a no-op stub (ImageSize returns 1,1), the UV
    -- coords [1..4] are RAW pixel coordinates in the sheet, not normalised UVs.
    -- The sheet file is resolved from tree.skillSprites[state].filename (a CDN
    -- URL); we take its basename and look for a matching local file in
    -- TreeData/<ver>/. This mirrors PassiveTreeView.lua's sprite selection.
    local sp, sheetKey
    if node.type == "Mastery" then
        -- Mastery art lives in node.masterySprites.{inactiveIcon,activeIcon};
        -- each is a spriteMap entry keyed by mastery* state.
        if node.masterySprites then
            local ms = node.masterySprites[alloc and "activeIcon" or "inactiveIcon"]
            sp = firstRect(ms)
            sheetKey = alloc and "masteryActive" or "masteryInactive"
        end
        if not sp then
            -- Mastery nodes without masterySprites carry the art directly in
            -- node.sprites under the "mastery*" keys (or the icon sprite).
            local mk = alloc and "masteryActive" or "masteryInactive"
            if sprites[mk] then
                sp, sheetKey = sprites[mk], mk
            elseif sprites.mastery then
                sp, sheetKey = sprites.mastery, "mastery"
            else
                local fb = alloc and "normalActive" or "normalInactive"
                if sprites[fb] then sp, sheetKey = sprites[fb], fb end
            end
        end
    else
        local state = node.type:lower() .. (alloc and "Active" or "Inactive")
        if sprites[state] then
            sp, sheetKey = sprites[state], state
        else
            -- Special nodes (Socket/ClassStart/AscendClassStart) only carry
            -- normalInactive/normalActive in node.sprites; fall back to those.
            local fb = alloc and "normalActive" or "normalInactive"
            if sprites[fb] then sp, sheetKey = sprites[fb], fb end
        end
    end
    if not sp then return nil end
    local sx, sy = sp[1], sp[2]
    local sw, sh = sp[3] - sp[1], sp[4] - sp[2]
    if not sw or sw <= 0 or not sh or sh <= 0 then return nil end
    -- Resolve the sheet file from the skillSprites table (keyed by state name).
    local sheet = tree.skillSprites and tree.skillSprites[sheetKey]
    local sheetFile = sheet and sheet.filename
    local base
    if sheetFile then
        base = sheetFile:gsub("%?%x+$", ""):match("([^/\\]+)$")
    end
    if not base then
        -- Fallback: map node type to the local sheet shipped in TreeData/<ver>/.
        local t = node.type:lower()
        if t == "mastery" then base = "mastery-3.png"
        elseif t == "jewelsocket" or t == "socket" then base = "jewel-3.png"
        else base = "skills-3.jpg" end
    end
    local localPath = (_SRC_DIR .. "/TreeData/" .. tree.treeVersion .. "/" .. base):gsub("\\", "/")
    local f = io.open(localPath, "r")
    if not f then return nil end
    f:close()
    return { atlas = "file:///" .. localPath, sx = sx, sy = sy, sw = sw, sh = sh }
end

-- Cached load of the shipped source sprites.lua for a tree version. The runtime
-- tree.assets frame entries are scale-keyed stubs with empty coords (the engine
-- does not populate frame atlas geometry), so the genuine sub-rects come from
-- the shipped TreeData/<ver>/sprites.lua `sprites` table. Loaded once per
-- version (the file is large) and memoised; `false` marks a failed load so we
-- don't retry every call.
local function loadSourceSprites()
    local ver = tree.treeVersion
    local cached = _sourceSpritesCache[ver]
    if cached ~= nil then return cached or nil end
    local path = (_SRC_DIR .. "/TreeData/" .. ver .. "/sprites.lua"):gsub("\\", "/")
    local ok, chunk = pcall(loadfile, path)
    local data = ok and chunk and chunk()
    _sourceSpritesCache[ver] = (type(data) == "table" and data.sprites) or false
    return _sourceSpritesCache[ver] or nil
end

-- Resolve the frame-ring overlay for a node (the bronze frame legacy draws over
-- the skill icon: node.sprites=icon, node.overlay=frame). node.overlay already
-- holds the engine-resolved frame NAMES keyed by state (alloc/unalloc, plus
-- Ascend/Blighted variants); we map that name to its sub-rect in the shipped
-- `frame` sprite sheet (frame-3.png). Masteries have no frame ring.
local function nodeFrame(node, alloc)
    if node.type == "Mastery" or not node.overlay then return nil end
    local key = (alloc and "alloc" or "unalloc")
        .. (node.ascendancyName and "Ascend" or "")
        .. (node.isBlighted and "Blighted" or "")
    local frameName = node.overlay[key] or node.overlay[alloc and "alloc" or "unalloc"]
    if not frameName then return nil end
    local sprites = loadSourceSprites()
    local grp = sprites and sprites.frame
    local rect = grp and grp.coords and grp.coords[frameName]
    if not rect or not rect.w or rect.w <= 0 or not rect.h or rect.h <= 0 then return nil end
    local base = grp.filename and (grp.filename:match("([^/]+)%?") or grp.filename:match("([^/]+)$"))
    if not base then return nil end
    local localPath = (_SRC_DIR .. "/TreeData/" .. tree.treeVersion .. "/" .. base):gsub("\\", "/")
    local f = io.open(localPath, "r")
    if not f then return nil end
    f:close()
    return { atlas = "file:///" .. localPath, sx = rect.x, sy = rect.y, sw = rect.w, sh = rect.h }
end

local loadSourceGroupBackground  -- forward declaration; defined below (after resolveGroupBackground)
local function resolveGroupBackground(oo)
    -- Select the PSGroupBackground variant by the group's orbit count `oo`.
    local spriteKey
    if oo and oo[3] then spriteKey = "PSGroupBackground3"
    elseif oo and oo[2] then spriteKey = "PSGroupBackground2"
    else spriteKey = "PSGroupBackground1" end

    -- The runtime tree.assets["PSGroupBackgroundN"] entries are scale-keyed stubs
    -- whose per-scale `coords` are empty (the engine does not populate group
    -- background geometry). Fall back to the genuine data shipped in the source
    -- TreeData/<ver>/sprites.lua (or tree.lua) `groupBackground` asset, which holds
    -- the atlas filename + the PSGroupBackground1/2/3 sub-rects.
    local gb = loadSourceGroupBackground()
    if gb and gb.filename then
        local base = gb.filename:match("([^/]+)%?") or gb.filename:match("([^/]+)$")
        local p = (_SRC_DIR .. "/TreeData/" .. tree.treeVersion .. "/" .. base):gsub("\\", "/")
        local f = io.open(p, "r")
        if not f then
            local rp = (_SRC_DIR .. "/TreeData/" .. base):gsub("\\", "/")
            f = io.open(rp, "r")
            if f then p = rp end
        end
        if f then
            f:close()
            local rect = gb.coords and gb.coords[spriteKey]
            if not rect then for _, v in pairs(gb.coords or { }) do rect = v; break end end
            if rect and rect.w and rect.w > 0 and rect.h and rect.h > 0 then
                -- PSGroupBackground3 is stored as a HALF image; legacy's
                -- DrawAsset(..., isHalf) draws it top-half + vertical mirror.
                -- Flag it so QML mirrors it instead of leaving the cluster
                -- backdrop visibly cut off at its midline.
                return { atlas = "file:///" .. p, sx = rect.x, sy = rect.y, sw = rect.w, sh = rect.h,
                         isHalf = (spriteKey == "PSGroupBackground3") }
            end
        end
    end
    return nil
end

-- Static group-background geometry per tree version. The runtime
-- tree.assets["PSGroupBackgroundN"] entries are scale-keyed stubs with empty
-- coords (the engine does not populate group-background geometry), so we use the
-- genuine sub-rects from the source TreeData/<ver>/sprites.lua `groupBackground`
-- asset (verified data, static per version). Returned in the same
-- { filename, coords } shape resolveGroupBackground already consumes.
local _gbByVersion = {
    ["3_28"] = {
        filename = "group-background-3.png",
        coords = {
            PSGroupBackground1 = { x = 443, y = 444, w = 138, h = 138 },
            PSGroupBackground2 = { x = 723, y = 286, w = 178, h = 178 },
            PSGroupBackground3 = { x = 723, y = 0,   w = 283, h = 143 },
        },
    },
}
function loadSourceGroupBackground()
    return _gbByVersion[tree.treeVersion] or nil
end

local function groupSprite(group)
    return resolveGroupBackground(group.oo)
end

local nodes = { }
local allocCount = 0
for id, node in pairs(tree.nodes) do
    if not node.group or not node.group.isProxy then
        local alloc = spec.nodes[id] and spec.nodes[id].alloc or false
        if alloc then allocCount = allocCount + 1 end
        local sd = node.sd
        if type(sd) ~= "table" then sd = { } end
        nodes[#nodes + 1] = {
            id = id,
            x = node.x,
            y = node.y,
            type = node.type,
            allocated = alloc,
            group = node.group and node.group.id,
            ascendancyName = node.ascendancyName,
            name = node.name or node.dn or "",
            isJewelSocket = node.isJewelSocket or false,
            isMastery = node.type == "Mastery",
            iconSprite = nodeSprite(node, alloc),
            frameSprite = nodeFrame(node, alloc),
            sd = sd,
        }
    end
end

local groups = { }
for id, group in pairs(tree.groups) do
    if not group.isProxy then
        local oo = group.oo or { }
        groups[#groups + 1] = {
            id = id,
            x = group.x,
            y = group.y,
            oo = { not not oo[1], not not oo[2], not not oo[3] },
            ascendancyName = group.ascendancyName,
            isAscendancyStart = group.isAscendancyStart or false,
            sprite = groupSprite(group),
        }
    end
end

local connectors = { }
for _, c in pairs(tree.connectors) do
    local n1 = tree.nodes[c.nodeId1]
    local n2 = tree.nodes[c.nodeId2]
    if n1 and n2 then
        local a1 = spec.nodes[c.nodeId1] and spec.nodes[c.nodeId1].alloc or false
        local a2 = spec.nodes[c.nodeId2] and spec.nodes[c.nodeId2].alloc or false
        local state = (a1 and a2) and "Active" or "Normal"
        connectors[#connectors + 1] = {
            nodeId1 = c.nodeId1,
            nodeId2 = c.nodeId2,
            type = c.type,
            ascendancyName = c.ascendancyName,
            state = state,
            x1 = n1.x, y1 = n1.y,
            x2 = n2.x, y2 = n2.y,
        }
    end
end

local bounds = {
    min_x = tree.min_x, max_x = tree.max_x,
    min_y = tree.min_y, max_y = tree.max_y,
    size = tree.size,
}

local assets = { }
for name, asset in pairs(tree.assets) do
    if asset and asset.filename then
        local base = asset.filename:match("([^/]+)%?") or asset.filename:match("([^/]+)$")
        local localPath = (_SRC_DIR .. "/TreeData/" .. tree.treeVersion .. "/" .. base):gsub("\\", "/")
        assets[name] = {
            filename = "file:///" .. localPath,
            w = asset.w, h = asset.h,
            coords = asset.coords,
        }
    end
end


-- TEMP DEBUG (verify_style): dump tree sizes to a file so the headless
-- self-test can confirm the full node set without qDebug visibility.
return {
    nodes = nodes,
    groups = groups,
    connectors = connectors,
    bounds = bounds,
    assets = assets,
    assetBasePath = "TreeData/" .. tree.treeVersion,
    backgroundUrl = "file:///" .. (_SRC_DIR .. "/TreeData/" .. tree.treeVersion .. "/background-3.png"):gsub("\\", "/"),
    allocCount = allocCount,
    nodeCount = #nodes,
}
end

function pob_selftestTreeRender()
local d = pob_getTreeData()
if not d then return { ok = false, error = "no tree" } end
return {
    ok = #d.nodes > 0 and #d.groups > 0 and #d.connectors > 0
          and d.bounds and d.bounds.size > 0,
    nodeCount = #d.nodes,
    groupCount = #d.groups,
    connectorCount = #d.connectors,
}
end

-- Phase 4b marker (diagnostic)

-- Phase 4b: passive-tree interaction bridge. Top-level globals (NOT pob.*) because
-- LuaEngine::callGlobal does a single lua_getglobal and cannot resolve dotted names.
-- These wrap spec:AllocNode / spec:DeallocNode and trigger a recalc via the engine's
-- buildFlag + OnFrame path (the same path the real UI uses), so calcsTab.mainOutput
-- (Life/Mana/DPS) stays in sync with the allocated tree.

-- Module-level store for the current search-match ids (filled by pob_setTreeSearch).
local treeSearchResults = { }

-- Allocate the node with the given id (a spec.nodes id). Returns a result table the
-- C++/QML side can read, or nil if the spec/node is unavailable.
function pob_allocNode(id)
    local bm = main and main.modes and main.modes.BUILD
    local spec = bm and bm.spec
    if not spec or not spec.nodes[id] then return nil end
    local node = spec.nodes[id]
    if node.alloc then
        return { ok = true, alreadyAlloc = true, used = select(1, spec:CountAllocNodes()) }
    end
    spec:AllocNode(node)
    -- Trigger a recalc through the engine's canonical dirty-flag path. Wrapped in
    -- pcall so a recalc hiccup can never mask the (already applied) allocation.
    bm.buildFlag = true
    pcall(runCallback, "OnFrame")
    return { ok = true, used = select(1, spec:CountAllocNodes()), alloc = node.alloc }
end

-- Deallocate the node with the given id. Cascades to dependents (engine handles it).
function pob_deallocNode(id)
    local bm = main and main.modes and main.modes.BUILD
    local spec = bm and bm.spec
    if not spec or not spec.nodes[id] then return nil end
    local node = spec.nodes[id]
    if not node.alloc then
        return { ok = true, alreadyDealloc = true, used = select(1, spec:CountAllocNodes()) }
    end
    spec:DeallocNode(node)
    bm.buildFlag = true
    pcall(runCallback, "OnFrame")
    return { ok = true, used = select(1, spec:CountAllocNodes()), alloc = node.alloc }
end

-- Convenience toggle: allocate if unallocated, deallocate if allocated.
function pob_toggleNode(id)
    local spec = main and main.modes and main.modes.BUILD and main.modes.BUILD.spec
    if not spec or not spec.nodes[id] then return nil end
    if spec.nodes[id].alloc then
        return pob_deallocNode(id)
    else
        return pob_allocNode(id)
    end
end

-- Tooltip data for a node: name, type, alloc state, and stat-description lines.
function pob_getNodeTooltip(id)
    -- Prefer the build spec's node (carries live alloc state), but fall back to
    -- the global tree's node table: the canvas renders ALL nodes from the global
    -- tree geometry (ascendancy, cluster bases, ...), ~400 of which are absent
    -- from spec.nodes — without this fallback those nodes render but hovering
    -- them shows nothing, which reads as "hover stopped working".
    local spec = main and main.modes and main.modes.BUILD and main.modes.BUILD.spec
    local node = spec and spec.nodes and spec.nodes[id]
    if not node then
        local tree = main and main.tree and latestTreeVersion and main.tree[latestTreeVersion]
        node = tree and tree.nodes and tree.nodes[id]
    end
    if not node then return nil end
    local sd = node.sd
    if type(sd) ~= "table" then sd = { } end
    return { name = node.dn, type = node.type, alloc = node.alloc, sd = sd }
end

-- Set the tree search string; returns the list of matching node ids (substring match
-- on the node display name and stat-description lines). Empty string clears results.
function pob_setTreeSearch(str)
    treeSearchResults = { }
    local spec = main and main.modes and main.modes.BUILD and main.modes.BUILD.spec
    if not spec or not spec.tree then return treeSearchResults end
    if not str or str == "" then return treeSearchResults end
    local s = tostring(str):lower()
    for id, node in pairs(spec.nodes) do
        local dn = node.dn or node.name or ""
        local match = tostring(dn):lower():find(s, 1, true)
        if not match then
            local sd = node.sd
            if type(sd) == "table" then
                for _, line in ipairs(sd) do
                    if tostring(line):lower():find(s, 1, true) then
                        match = true
                        break
                    end
                end
            end
        end
        if match then
            treeSearchResults[#treeSearchResults + 1] = id
        end
    end
    return treeSearchResults
end

-- Return the current search-match id list (module-level store).
function pob_getTreeSearchResults()
    return treeSearchResults
end

-- Phase 4b selftest: allocate a Normal node, assert the used count increased and the
-- node is allocated; deallocate it, assert the count is restored; set a "life" search
-- and assert matches exist, then clear and assert none. ADDITIVE: runs before
-- SELFTEST PASSED.
function pob_selftestTreeInteract()
    local res = { ok = false }
    local spec = main and main.modes and main.modes.BUILD and main.modes.BUILD.spec
    if not spec then
        res.error = "no spec"
        return res
    end
    -- Pick an allocatable, non-ascendancy Normal node that is directly linked to
    -- an already-allocated node, so allocating it adds exactly one node (itself)
    -- and deallocating it restores the original used count. (Allocating a far node
    -- would also allocate its whole path, which DeallocNode only partially unwinds
    -- since the trunk path nodes stay connected to the start.)
    local targetId = nil
    for id, node in pairs(spec.nodes) do
        if node.type == "Normal" and node.path and not node.alloc and not node.ascendancyName then
            local linkedToAlloc = false
            for _, ln in ipairs(node.linked) do
                if ln.alloc then linkedToAlloc = true; break end
            end
            if linkedToAlloc then
                targetId = id
                break
            end
        end
    end
    if not targetId then
        res.error = "no allocatable normal node found"
        return res
    end
    local before = select(1, spec:CountAllocNodes())
    local a = pob_allocNode(targetId)
    if not a or not a.ok then
        res.error = "alloc failed"
        return res
    end
    local after = select(1, spec:CountAllocNodes())
    res.allocOk = (after >= before + 1) and (spec.nodes[targetId].alloc == true)
    local d = pob_deallocNode(targetId)
    if not d or not d.ok then
        res.error = "dealloc failed"
        return res
    end
    local restored = select(1, spec:CountAllocNodes())
    res.deallocOk = (restored == before) and (spec.nodes[targetId].alloc == false)
    pob_setTreeSearch("life")
    local results = pob_getTreeSearchResults()
    res.searchOk = (type(results) == "table" and #results > 0)
    pob_setTreeSearch("")
    res.searchClearOk = (#pob_getTreeSearchResults() == 0)
    res.ok = not not (res.allocOk and res.deallocOk and res.searchOk and res.searchClearOk)
    return res
end

-- ===========================================================================
-- Part 1.4 (bullet 4): Options dialog bridge.
--
-- Three-layer bridge mirroring main:OpenOptionsPopup (Modules/Main.lua ~865):
--   pob_getOptions()    -> flat descriptor list (value + metadata) for every
--                          ~28 setting, tagged `commit` (true = Save-only field,
--                          false = live-preview field).
--   pob_previewOption() -> LIVE-apply a field onto self.* (the fields legacy
--                          mutates as the control changes; Cancel reverts them by
--                          replaying the pre-open snapshot through this same fn).
--   pob_commitOptions() -> the Save-button-only fields (connectionProtocol /
--                          proxy / buildPath) + main:SaveSettings() (immediate
--                          persist to Settings.xml, exactly like the legacy Save
--                          button which called SaveSettings() explicitly).
--
-- The live-vs-commit split is exactly the legacy Save/Cancel handler split
-- (Main.lua:1188 Save / :1213 Cancel): connectionProtocol, proxyType+proxyURL and
-- buildPath are only read out of the controls on Save; everything else is written
-- straight onto self.* by each control's callback (so e.g. the node-power theme
-- previews live) and reverted to `savedState` on Cancel.
-- Top-level globals (NOT pob.*) because LuaEngine::callGlobal does a single
-- lua_getglobal and cannot resolve dotted names.

local o_min = math.min
local o_max = math.max
local function o_round(v, p)
    local mult = 10 ^ (p or 0)
    return math.floor(v * mult + 0.5) / mult
end

-- Split launch.proxyURL "scheme://host:port" into its parts, mirroring the
-- legacy `launch.proxyURL:match("(%w+)://(.+)")`. Defaults to the DropDown's
-- first entry ("http") with an empty URL when no proxy is configured.
local function pob_proxyParts()
    if launch and launch.proxyURL then
        local scheme, url = launch.proxyURL:match("(%w+)://(.+)")
        if scheme then return scheme, url end
    end
    return "http", ""
end

function pob_getOptions()
    if not main then return {} end
    local self = main
    local scheme, purl = pob_proxyParts()
    local buildPathVal = (self.buildPath ~= self.defaultBuildPath) and self.buildPath or ""
    -- Colours are stored on self as "^xRRGGBBAA" markup; the EditControls show
    -- them as "0xRRGGBBAA" (the leading ^ swapped for 0), matching legacy
    -- `tostring(self.colorPositive:gsub('^(^)', '0'))`.
    local function hex(v) return tostring((v or ""):gsub('^(^)', '0')) end
    local dc = defaultColorCodes or {}

    local opts = {
        -- ===== Application options =====
        { key = "connectionProtocol", section = "Application options", type = "dropdown", commit = true,
          label = "Connection Protocol:", value = (launch and launch.connectionProtocol) or 0,
          tooltip = "Changes which protocol is used when downloading updates and importing builds.",
          options = { { label = "Auto", val = 0 }, { label = "IPv4", val = 1 }, { label = "IPv6", val = 2 } } },
        { key = "proxyScheme", section = "Application options", type = "dropdown", commit = true,
          label = "Proxy server:", value = scheme,
          options = { { label = "HTTP", val = "http" }, { label = "SOCKS", val = "socks5" }, { label = "SOCKS5H", val = "socks5h" } } },
        { key = "proxyURL", section = "Application options", type = "text", commit = true,
          label = "", value = purl, maxChars = 0, placeholder = "host:port" },
        { key = "dpiScaleOverridePercent", section = "Application options", type = "dropdown", commit = false,
          label = "UI scaling override:", value = self.dpiScaleOverridePercent or 0,
          tooltip = "Overrides Windows DPI scaling inside Path of Building.\nChoose a percentage between 100% and 250% or revert to the system default.",
          options = { { label = "Use system default", val = 0 }, { label = "100%", val = 100 }, { label = "125%", val = 125 },
                      { label = "150%", val = 150 }, { label = "175%", val = 175 }, { label = "200%", val = 200 },
                      { label = "225%", val = 225 }, { label = "250%", val = 250 } } },
        { key = "buildPath", section = "Application options", type = "text", commit = true,
          label = "Build save path:", value = buildPathVal,
          tooltip = "Overrides the default save location for builds.\nThe default location is: '" .. tostring(self.defaultBuildPath) .. "'" },
        { key = "nodePowerTheme", section = "Application options", type = "dropdown", commit = false,
          label = "Node Power colours:", value = self.nodePowerTheme,
          tooltip = "Changes the colour scheme used for the node power display on the passive tree.",
          options = { { label = "Red & Blue", val = "RED/BLUE" }, { label = "Red & Green", val = "RED/GREEN" }, { label = "Green & Blue", val = "GREEN/BLUE" } } },
        { key = "colorPositive", section = "Application options", type = "color", commit = false,
          label = "Hex colour for positive values:", value = hex(self.colorPositive), maxChars = 8,
          tooltip = "Overrides the default hex colour for positive values in breakdowns.\nExpected format is 0x000000. The default value is " .. hex(dc.POSITIVE) .. ".\nIf updating while inside a build, please re-load the build after saving." },
        { key = "colorNegative", section = "Application options", type = "color", commit = false,
          label = "Hex colour for negative values:", value = hex(self.colorNegative), maxChars = 8,
          tooltip = "Overrides the default hex colour for negative values in breakdowns.\nExpected format is 0x000000. The default value is " .. hex(dc.NEGATIVE) .. ".\nIf updating while inside a build, please re-load the build after saving." },
        { key = "colorHighlight", section = "Application options", type = "color", commit = false,
          label = "Hex colour for highlight nodes:", value = hex(self.colorHighlight), maxChars = 8,
          tooltip = "Overrides the default hex colour for highlighting nodes in passive tree search.\nExpected format is 0x000000. The default value is " .. hex(dc.HIGHLIGHT) .. "\nIf updating while inside a build, please re-load the build after saving." },
        { key = "betaTest", section = "Application options", type = "check", commit = false,
          label = "Opt-in to weekly beta test builds:", value = not not self.betaTest },
        { key = "edgeSearchHighlight", section = "Application options", type = "check", commit = false,
          label = "Show search circles at viewport edge", value = not not self.edgeSearchHighlight },
        { key = "showPublicBuilds", section = "Application options", type = "check", commit = false,
          label = "Show Latest/Trending builds:", value = not not self.showPublicBuilds },
        { key = "showFlavourText", section = "Application options", type = "check", commit = false,
          label = "Styled Tooltips with Flavour Text:", value = not not self.showFlavourText,
          tooltip = "If updating while inside a build, please re-load the build after saving." },
        { key = "showAnimations", section = "Application options", type = "check", commit = false,
          label = "Show Animations:", value = not not self.showAnimations },
        { key = "showAllItemAffixes", section = "Application options", type = "check", commit = false,
          label = "Show all item affixes sliders:", value = not not self.showAllItemAffixes,
          tooltip = "Display all item affix slots as a stacked list instead of hiding them in dropdowns" },
        -- ===== Build-related options =====
        { key = "showThousandsSeparators", section = "Build-related options", type = "check", commit = false,
          label = "Show thousands separators:", value = not not self.showThousandsSeparators },
        { key = "thousandsSeparator", section = "Build-related options", type = "text", commit = false,
          label = "Thousands separator:", value = self.thousandsSeparator or "", maxChars = 1 },
        { key = "decimalSeparator", section = "Build-related options", type = "text", commit = false,
          label = "Decimal separator:", value = self.decimalSeparator or "", maxChars = 1 },
        { key = "showTitlebarName", section = "Build-related options", type = "check", commit = false,
          label = "Show build name in window title:", value = not not self.showTitlebarName },
        { key = "defaultGemQuality", section = "Build-related options", type = "int", commit = false,
          label = "Default gem quality:", value = self.defaultGemQuality or 0, min = 0, max = 23, maxChars = 2,
          tooltip = "Set the default quality that can be overwritten by build-related quality settings in the skill panel." },
        { key = "defaultCharLevel", section = "Build-related options", type = "int", commit = false,
          label = "Default character level:", value = self.defaultCharLevel or 1, min = 1, max = 100, maxChars = 3,
          tooltip = "Set the default level of your builds. If this is higher than 1, manual level mode will be enabled by default in new builds." },
        { key = "defaultItemAffixQuality", section = "Build-related options", type = "slider", commit = false,
          label = "Default item affix quality:", value = self.defaultItemAffixQuality or 0.5, min = 0, max = 1, step = 0.01 },
        { key = "showWarnings", section = "Build-related options", type = "check", commit = false,
          label = "Show build warnings:", value = not not self.showWarnings },
        { key = "slotOnlyTooltips", section = "Build-related options", type = "check", commit = false,
          label = "Show tooltips only for affected slots:", value = not not self.slotOnlyTooltips,
          tooltip = "Shows comparisons in tooltips only for the slot you are currently placing the item in, instead of all slots." },
        { key = "migrateEldritchImplicits", section = "Build-related options", type = "check", commit = false,
          label = "Copy Eldritch Implicits onto Display Item:", value = not not self.migrateEldritchImplicits,
          tooltip = "Apply Eldritch Implicits from current gear when comparing new gear, given the new item doesn't have any influence" },
        { key = "notSupportedModTooltips", section = "Build-related options", type = "check", commit = false,
          label = "Show tooltip for unsupported mods :", value = not not self.notSupportedModTooltips,
          tooltip = "Show (Not supported in PoB yet) next to unsupported mods" },
        { key = "invertSliderScrollDirection", section = "Build-related options", type = "check", commit = false,
          label = "Invert slider scroll direction:", value = not not self.invertSliderScrollDirection,
          tooltip = "Default scroll direction is:\nScroll Up = Move right\nScroll Down = Move left" },
    }
    -- Dev-only toggle (legacy gates this behind launch.devMode).
    if launch and launch.devMode then
        opts[#opts + 1] = { key = "disableDevAutoSave", section = "Build-related options", type = "check", commit = false,
            label = "Disable Dev AutoSave:", value = not not self.disableDevAutoSave,
            tooltip = "Do not Autosave builds while on Dev branch" }
    end
    return opts
end

-- Live-apply a single option onto self.* exactly as the matching legacy control
-- callback does, then return the (possibly clamped/validated) stored value so the
-- QML control can reflect any clamp. Cancel replays this with the snapshot values.
function pob_previewOption(key, value)
    if not main or not key then return value end
    local self = main
    if key == "colorPositive" or key == "colorNegative" or key == "colorHighlight" then
        -- Mirror the EditControl callback: only apply a well-formed 0xRRGGBBAA hex
        -- (string.match(buf, "0x%x+") with #match == 8), otherwise keep the old value.
        local buf = tostring(value)
        local m = buf:match("0x%x+")
        if m and #m == 8 then
            local code = (key == "colorPositive" and "POSITIVE")
                      or (key == "colorNegative" and "NEGATIVE") or "HIGHLIGHT"
            updateColorCode(code, buf)
            self[key] = buf
        end
        return self[key]
    elseif key == "defaultGemQuality" then
        self.defaultGemQuality = o_min(tonumber(value) or 0, 23)
        return self.defaultGemQuality
    elseif key == "defaultCharLevel" then
        self.defaultCharLevel = o_min(o_max(tonumber(value) or 1, 1), 100)
        return self.defaultCharLevel
    elseif key == "defaultItemAffixQuality" then
        self.defaultItemAffixQuality = o_round(tonumber(value) or 0.5, 2)
        return self.defaultItemAffixQuality
    elseif key == "dpiScaleOverridePercent" then
        self.dpiScaleOverridePercent = tonumber(value) or 0
        -- SetDPIScaleOverridePercent is a SimpleGraphic stub under Qt (Qt owns DPI);
        -- call it defensively so this stays faithful if it is ever wired.
        pcall(function() SetDPIScaleOverridePercent(self.dpiScaleOverridePercent) end)
        return self.dpiScaleOverridePercent
    elseif key == "thousandsSeparator" or key == "decimalSeparator" or key == "nodePowerTheme" then
        self[key] = value
        return value
    else
        -- boolean checkbox fields
        self[key] = value and true or false
        return self[key]
    end
end

-- Apply the Save-button-only fields and persist. `t` is a flat map
-- { connectionProtocol, proxyScheme, proxyURL, buildPath }. Mirrors the legacy
-- Save handler (Main.lua:1188) 1:1, minus ClosePopup (QML owns the popup).
function pob_commitOptions(t)
    if not main then return false end
    local self = main
    t = t or {}
    if t.connectionProtocol ~= nil then
        launch.connectionProtocol = tonumber(t.connectionProtocol)
        self.connectionProtocol = launch.connectionProtocol
    end
    local purl = tostring(t.proxyURL or "")
    if purl:match("%w") then
        local scheme = tostring(t.proxyScheme or "http")
        launch.proxyURL = scheme .. "://" .. purl
    else
        launch.proxyURL = nil
    end
    local bpath = tostring(t.buildPath or "")
    if bpath:match("%S") then
        self.buildPath = bpath
        if not self.buildPath:match("[\\/]$") then
            self.buildPath = self.buildPath .. "/"
        end
    else
        self.buildPath = self.defaultBuildPath
    end
    if self.mode == "LIST" and self.modes and self.modes.LIST then
        pcall(function() self.modes.LIST:BuildList() end)
    end
    if not (launch and launch.devMode) then
        pcall(function() main:SetManifestBranch(self.betaTest and "beta" or "master") end)
    end
    pcall(function() SetDPIScaleOverridePercent(self.dpiScaleOverridePercent) end)
    pcall(function() main:SaveSettings() end)
    return true
end

-- Part 1.4 selftest: prove the Options bridge round-trips without touching
-- Settings.xml (avoids clobbering the user's real settings). Asserts:
--   * getOptions yields the full descriptor list with sane metadata;
--   * a live boolean field flips on main via previewOption and reverts cleanly;
--   * the defaultCharLevel numeric clamp [1,100] is enforced by previewOption.
function pob_selftestOptions()
    local res = { ok = false }
    local opts = pob_getOptions()
    if type(opts) ~= "table" or #opts == 0 then
        res.error = "no options"
        return res
    end
    res.count = #opts
    -- sanity: every descriptor has key/type/section
    for _, o in ipairs(opts) do
        if not o.key or not o.type or not o.section then
            res.error = "malformed descriptor"
            return res
        end
    end
    local boolOpt
    for _, o in ipairs(opts) do
        if o.type == "check" and o.commit == false then boolOpt = o; break end
    end
    if not boolOpt then res.error = "no live boolean option"; return res end
    local before = main[boolOpt.key]
    pob_previewOption(boolOpt.key, not before)
    local flipped = main[boolOpt.key]
    pob_previewOption(boolOpt.key, before)
    local reverted = main[boolOpt.key]
    res.boolKey = boolOpt.key
    res.flipOk = (flipped == (not before)) and (reverted == before)
    -- numeric clamp check on defaultCharLevel
    local savedLvl = main.defaultCharLevel
    local hi = pob_previewOption("defaultCharLevel", 9999)
    local lo = pob_previewOption("defaultCharLevel", -5)
    res.clampOk = (hi == 100) and (lo == 1)
    pob_previewOption("defaultCharLevel", savedLvl or 1)
    res.ok = not not (res.flipOk and res.clampOk)
    return res
end

-- ===========================================================================
-- Part 1.4 (bullet 6): About popup content bridge, mirroring
-- main:OpenAboutPopup (Modules/Main.lua:1356)'s changelog.txt/help.txt
-- parsing into TextListControl-shaped row lists ({height, [1]=col0text,
-- [2]=col1text}). A host seam, not a src/ edit -- QML owns rendering
-- (invariant #1), so only the file-parsing algorithm is ported, verbatim,
-- not the popup control tree itself.
--
-- Deviation from legacy: both files live at the repo root and every host
-- binary here always runs with cwd=src/ (invariant #6), so unlike legacy's
-- `launch.devMode and "../changelog.txt" or "changelog.txt"` branch, we
-- always read "../" regardless of devMode. The DEV[..] help-line content
-- gate still honors launch.devMode, matching legacy exactly.
function pob_getAboutContent()
    local textSize, subTitleSize, titleSize, popupWidth = 16, 20, 24, 810
    local changeList = { }
    local changeVersionHeights = { }
    local changelogFile = io.open("../changelog.txt", "r")
    if changelogFile then
        changelogFile:close()
        for line in io.lines("../changelog.txt") do
            local ver, date = line:match("^VERSION%[(.+)%]%[(.+)%]$")
            if ver then
                if #changeList > 0 then
                    table.insert(changeList, { height = textSize / 2 })
                end
                table.insert(changeVersionHeights, #changeList * textSize)
                table.insert(changeList, { height = titleSize, "^7Version " .. ver .. " (" .. date .. ")" })
            elseif line:match("^---") then
                table.insert(changeList, { height = subTitleSize, "^7" .. line })
            else
                table.insert(changeList, { height = textSize, "^7" .. line })
            end
        end
    end

    local helpList = { }
    local helpSections = { }
    local helpSectionHeights = { }
    local helpFile = io.open("../help.txt", "r")
    if helpFile then
        helpFile:close()
        for line in io.lines("../help.txt") do
            local title = line:match("^---%[(.+)%]$")
            if title then
                if #helpList > 0 then
                    table.insert(helpList, { height = textSize / 2 })
                end
                table.insert(helpSections, { title = title, height = #helpList })
                table.insert(helpList, { height = titleSize, "^7" .. title .. " (" .. #helpSections .. ")" })
            else
                local dev = line:match("^DEV%[(.+)%]$")
                if not (dev and not (launch and launch.devMode)) then
                    line = (dev or line)
                    local outdent, indent = line:match("(.*)\t+(.*)")
                    if outdent then
                        local indentLines = main:WrapString(indent, textSize, popupWidth - 190)
                        if #indentLines > 1 then
                            for i, indentLine in ipairs(indentLines) do
                                table.insert(helpList, { height = textSize, (i == 1 and outdent or " "), (dev and "^x8888FF" or "^7") .. indentLine })
                            end
                        else
                            table.insert(helpList, { height = textSize, (dev and "^x8888FF" or "^7") .. outdent, (dev and "^x8888FF" or "^7") .. indent })
                        end
                    else
                        local wrapped = main:WrapString(line, textSize, popupWidth - 135)
                        for i, line2 in ipairs(wrapped) do
                            table.insert(helpList, { height = textSize, (dev and "^x8888FF" or "^7") .. (i > 1 and "    " or "") .. line2 })
                        end
                    end
                end
            end
        end
        local contentsDone = false
        for sectionIndex, sectionValues in ipairs(helpSections) do
            if sectionValues.title == "Contents" then
                table.insert(helpList, (sectionValues.height + sectionIndex), { height = textSize, "^7 " })
                for i, sectionValuesInner in ipairs(helpSections) do
                    table.insert(helpList, (sectionValues.height + i + sectionIndex), { height = textSize, "^7" .. tostring(i) .. ". " .. sectionValuesInner.title })
                end
            end
            helpSections[sectionIndex].height = helpSections[sectionIndex].height + (contentsDone and (#helpSections + 1) or 0)
            helpSectionHeights[sectionIndex] = helpSections[sectionIndex].height * textSize
            if sectionValues.title == "Contents" then
                contentsDone = true
            end
        end
    end

    return {
        changeList = changeList,
        changeVersionHeights = changeVersionHeights,
        helpList = helpList,
        helpSectionHeights = helpSectionHeights,
        helpSections = helpSections,
        versionNumber = (launch and launch.versionNumber) or "",
        versionBranch = (launch and launch.versionBranch) or "",
        devMode = not not (launch and launch.devMode),
    }
end

-- Part 1.4 selftest: assert the About content bridge yields a non-empty,
-- well-formed changelog + help section list (changelog.txt/help.txt ship in
-- the repo root, so this always has real content to parse in dev/CI).
function pob_selftestAboutContent()
    local res = { ok = false }
    local c = pob_getAboutContent()
    if type(c) ~= "table" then res.error = "no content"; return res end
    res.changeCount = #(c.changeList or {})
    res.helpCount = #(c.helpList or {})
    res.helpSectionCount = #(c.helpSections or {})
    res.ok = not not (res.changeCount > 0 and res.helpCount > 0 and res.helpSectionCount > 0)
    return res
end
