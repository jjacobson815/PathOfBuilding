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

-- Image handles. QML owns all rendering (invariant #1), so these never hold a
-- texture -- but they are NOT inert: the engine does real arithmetic on
-- ImageSize(), and `Load` is the only place the filename is ever seen.
--
-- ImageSize() used to return a hardcoded `1, 1`. Four sites in src/ consume it
-- (and src/ cannot be changed -- invariant #2):
--
--   PassiveTree.lua:368   sheet.width/height, the DIVISOR that turns sprite-sheet
--                         coords into UVs. With 1 the "UVs" came out as raw
--                         pixels, which pob_getTreeData's nodeSprite() below was
--                         written against; both had to move together.
--   PassiveTree.lua:871   width/height of every tree.assets[] entry -- all 1x1.
--   PassiveTree.lua:956   `size = art.width * 2 * 1.33`, the orbit-arc radius, so
--                         EVERY arc collapsed to 2.66 tree units at the group
--                         centre and connector.vert[state] was garbage.
--   PassiveTreeView.lua:524/:1233  background sizing and DrawAsset.
--
-- So: retain the filename, and measure lazily through pob.imageSize (header-only
-- QImageReader read, memoised C++-side). Lazily because Load is called for every
-- asset of every tree version that gets loaded, while only a fraction are ever
-- measured. 0, 0 on failure -- what legacy SimpleGraphic reports for an invalid
-- handle, and what PassiveTreeView.lua:523/:1232 test for; nil would make their
-- `data.width == 0` comparison silently false and `bg.width > 0` a runtime error.
function NewImageHandle()
    return setmetatable({ }, {
        __index = {
            Load = function(self, fileName, ...)
                self.fileName = fileName
                self.valid = true
                self.w, self.h = nil, nil   -- re-measure on next ImageSize()
            end,
            Unload = function(self)
                self.valid = false
                self.fileName = nil
                self.w, self.h = nil, nil
            end,
            IsValid = function(self) return self.valid end,
            SetLoadingPriority = function(self, pri) end,
            ImageSize = function(self)
                if self.w then return self.w, self.h end
                local w, h = 0, 0
                if self.fileName and pob and pob.imageSize then
                    local rw, rh = pob.imageSize(self.fileName)
                    w, h = tonumber(rw) or 0, tonumber(rh) or 0
                end
                self.w, self.h = w, h
                return w, h
            end,
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
    -- AddItem sets build.buildFlag = true internally but nothing consumed it
    -- before this returned; without this, calc output goes stale (mainOutput
    -- is already non-nil so pob_getCalcOutput's lazy rebuild never fires).
    pob_recalculate()
    return item.id
end

function pob_deleteItem(id)
    local it = main and main.modes and main.modes.BUILD and main.modes.BUILD.itemsTab
    if not it or not id then return false end
    local item = it.items[id]
    if item then
        it:DeleteItem(item)
        it:PopulateSlots()
        pob_recalculate()
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
    pob_recalculate()
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
    pob_recalculate()
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

-- Part 2.2: single recalc-orchestration entry point. Runs the exact legacy
-- dirty-flag sequence buildMode:OnFrame executes when build.buildFlag is set
-- (src/Modules/Build.lua: wipeGlobalCache -> outputRevision++ -> buildFlag =
-- false -> CalcsTab:BuildOutput() -> RefreshStatList). Every mutation seam
-- (tree alloc, item add/delete, config write, skill select, ...) should call
-- this instead of running a full runCallback("OnFrame") (which also
-- reprocesses input events and dropdown state that have nothing to do with
-- recalculating). Idempotent: a no-op fast path when nothing is dirty, so
-- callers can invoke it freely (e.g. after every hover) without paying for
-- redundant BuildOutput passes.
function pob_recalculate()
    local bm = main and main.modes and main.modes.BUILD
    if not bm then return { ok = false, error = "no build" } end
    if not bm.buildFlag then
        return { ok = true, recalculated = false, outputRevision = bm.outputRevision or 0 }
    end
    wipeGlobalCache()
    bm.outputRevision = (bm.outputRevision or 0) + 1
    bm.buildFlag = false
    local ok, err = pcall(function() bm.calcsTab:BuildOutput() end)
    if not ok then
        return { ok = false, error = tostring(err), outputRevision = bm.outputRevision }
    end
    pcall(function() bm:RefreshStatList() end)
    return { ok = true, recalculated = true, outputRevision = bm.outputRevision }
end

-- Lightweight read of the cache-invalidation signal (legacy
-- tooltip:CheckForUpdate(obj, outputRevision) key) without forcing a recalc.
function pob_getOutputRevision()
    local bm = main and main.modes and main.modes.BUILD
    return bm and (bm.outputRevision or 0) or 0
end

-- Part 2.2 selftest: prove pob_recalculate() is a true no-op when nothing is
-- dirty, and does exactly one wipeGlobalCache -> outputRevision++ ->
-- BuildOutput pass when build.buildFlag is set. Only touches the buildFlag
-- dirty bit (normal engine bookkeeping), never the build itself, so nothing
-- needs cleanup afterward.
function pob_selftestRecalc()
    local bm = main and main.modes and main.modes.BUILD
    if not bm then return { ok = false, error = "no build" } end

    local r0 = pob_getOutputRevision()

    local noop = pob_recalculate()
    if not noop.ok or noop.recalculated or noop.outputRevision ~= r0 then
        return { ok = false, error = "expected no-op when clean", r0 = r0, noop = noop }
    end

    bm.buildFlag = true
    local did = pob_recalculate()
    if not did.ok or not did.recalculated or did.outputRevision ~= r0 + 1 then
        return { ok = false, error = "expected a real recalc", r0 = r0, did = did }
    end
    if bm.buildFlag then
        return { ok = false, error = "buildFlag not cleared after recalc" }
    end

    local noop2 = pob_recalculate()
    if not noop2.ok or noop2.recalculated or noop2.outputRevision ~= r0 + 1 then
        return { ok = false, error = "expected second no-op", r0 = r0, noop2 = noop2 }
    end

    return { ok = true, r0 = r0, r1 = did.outputRevision }
end

-- ============================================================================
-- Part 2.3-2.6 shared helper: matchFlags is a PRIVATE local in Modules/Build.lua
-- (not reachable from here), so replicate its small body verbatim. Used by both
-- the sidebar stat serializer (2.3) and the compare-diff serializer (2.4) --
-- both walk the exact same build.displayStats/minionDisplayStats schema
-- (Modules/BuildDisplayStats.lua) that legacy uses for both purposes, per its
-- own header comment ("defines the stats in the side bar, and also which stats
-- show in node/item comparisons"). CalcSections/powerStatList are NOT walked
-- here: CalcSections already has its own live bridge (pob_getCalcOutput, the
-- CALCS-tab section grid), and powerStatList/node-power belongs to Phase 4's
-- PowerReport, not Phase 2.
-- ============================================================================
local function pob_matchFlags(reqFlags, notFlags, flags)
    if type(reqFlags) == "string" then reqFlags = { reqFlags } end
    if reqFlags then
        for _, flag in ipairs(reqFlags) do
            if not flags[flag] then return false end
        end
    end
    if type(notFlags) == "string" then notFlags = { notFlags } end
    if notFlags then
        for _, flag in ipairs(notFlags) do
            if flags[flag] then return false end
        end
    end
    return true
end

-- Part 2.3: Output marshalling. Ports buildMode:AddDisplayStatList's selection
-- logic (Build.lua:1637) to structured data instead of an immediate-mode draw
-- list, reusing bm:FormatStat (Build.lua:1611) verbatim for the value string so
-- sidebar numbers are byte-for-byte legacy (thousands separators, %+ signs,
-- trailing-zero trimming, over-cap suffixes all included). Handles the
-- `childStat` one-level-deep indirection generically, which is how
-- output.MainHand/.OffHand (childStat="Accuracy") and any future nested stat
-- naturally fall out without special-casing them.
local function pob_buildStatRecords(bm, statList, actor)
    local stats = { }
    local skillDPS = nil
    for _, statData in ipairs(statList) do
        if statData.stat and pob_matchFlags(statData.flag, statData.notFlag, actor.mainSkill.skillFlags) then
            local statVal = actor.output[statData.stat]
            if statVal and statData.childStat then
                statVal = statVal[statData.childStat]
            end
            if statVal and ((statData.condFunc and statData.condFunc(statVal, actor.output)) or (not statData.condFunc and statVal ~= 0)) then
                local overCapStatVal = actor.output[statData.overCapStat] or nil
                if statData.stat == "SkillDPS" then
                    skillDPS = { }
                    local sorted = { }
                    for i, sd in ipairs(actor.output.SkillDPS) do sorted[i] = sd end
                    table.sort(sorted, function(a, b) return (a.dps * a.count) > (b.dps * b.count) end)
                    for _, skillData in ipairs(sorted) do
                        skillDPS[#skillDPS + 1] = {
                            name = skillData.name,
                            dps = skillData.dps,
                            count = skillData.count,
                            trigger = skillData.trigger or "",
                            skillPart = skillData.skillPart or "",
                            source = skillData.source or "",
                            dpsStr = bm:FormatStat({ fmt = "1.f" }, skillData.dps * skillData.count, overCapStatVal),
                        }
                    end
                elseif not statData.hideStat then
                    local colorOverride = nil
                    if actor.output[statData.stat.."Warning"] or (statData.warnFunc and statData.warnFunc(statVal, actor.output) and statData.warnColor) then
                        colorOverride = colorCodes.NEGATIVE
                    end
                    stats[#stats + 1] = {
                        stat = statData.stat .. (statData.childStat or ""),
                        label = statData.label,
                        color = statData.color or "",
                        value = type(statVal) == "table" and "" or statVal,
                        valueStr = bm:FormatStat(statData, statVal, overCapStatVal, colorOverride),
                        warning = colorOverride ~= nil,
                    }
                end
            end
        elseif not statData.stat and statData.label and statData.condFunc and statData.condFunc(actor.output) then
            -- The one "labelStat" style entry in displayStats (Chaos Resistance ->
            -- "Immune" under Chaos Inoculation). Mirrors Build.lua:1704-1707.
            stats[#stats + 1] = {
                stat = statData.labelStat or statData.label,
                label = statData.label,
                color = "",
                value = statData.val,
                valueStr = "^7" .. tostring(actor.output[statData.labelStat]) .. "%^x808080 (" .. tostring(statData.val) .. ")",
                warning = false,
            }
        end
    end
    return stats, skillDPS
end

-- Collect the same warning strings buildMode:AddDisplayStatList/InsertItemWarnings
-- feed into self.controls.warnings.lines (Build.lua:1698-1765), as plain data
-- instead of a control's mutable .lines array.
local function pob_collectWarnings(bm, actor)
    local warnings = { }
    local function add(v)
        if not v then return end
        for _, existing in ipairs(warnings) do
            if existing == v then return end
        end
        warnings[#warnings + 1] = v
    end
    for _, statData in ipairs(bm.displayStats) do
        if statData.stat and statData.warnFunc then
            local statVal = actor.output[statData.stat]
            if statVal and ((statData.condFunc and statData.condFunc(statVal, actor.output)) or not statData.condFunc) then
                add(statData.warnFunc(statVal, actor.output))
            end
        end
    end
    for pool, warningFlag in pairs({ ["Life"] = "LifeCostWarningList", ["Mana"] = "ManaCostWarningList", ["Rage"] = "RageCostWarningList", ["Energy Shield"] = "ESCostWarningList" }) do
        if actor.output[warningFlag] then
            local line = "You do not have enough " .. (actor.output.EnergyShieldProtectsMana and pool == "Mana" and "Energy Shield and Mana" or pool) .. " to use: "
            for _, skill in ipairs(actor.output[warningFlag]) do line = line .. skill .. ", " end
            add(line:sub(1, -3))
        end
    end
    for pool, warningFlag in pairs({ ["Unreserved life"] = "LifePercentCostPercentCostWarningList", ["Unreserved Mana"] = "ManaPercentCostPercentCostWarningList" }) do
        if actor.output[warningFlag] then
            local line = "You do not have enough " .. pool .. "% to use: "
            for _, skill in ipairs(actor.output[warningFlag]) do line = line .. skill .. ", " end
            add(line:sub(1, -3))
        end
    end
    if bm.calcsTab.mainEnv.itemWarnings then
        local iw = bm.calcsTab.mainEnv.itemWarnings
        if iw.jewelLimitWarning then
            for _, w in ipairs(iw.jewelLimitWarning) do add("You are exceeding jewel limit with the jewel " .. w) end
        end
        if iw.socketLimitWarning then
            for _, w in ipairs(iw.socketLimitWarning) do add("You have too many gems in your " .. w .. " slot") end
        end
        if iw.missingAnointWarning then
            add("You have eligible items missing an anoint: " .. table.concat(iw.missingAnointWarning, ", "))
        end
    end
    return warnings
end

-- Host-callable entry: the sidebar's data source. Forces a recalc (idempotent
-- no-op if clean) then serializes env.player.output (+ env.minion.output when a
-- minion is active) against the displayStats/minionDisplayStats schema.
function pob_getOutput()
    local bm = main and main.modes and main.modes.BUILD
    local ct = bm and bm.calcsTab
    if not bm or not ct then return nil end
    pob_recalculate()
    if not ct.mainEnv or not ct.mainOutput then return nil end

    local playerStats, playerSkillDPS = pob_buildStatRecords(bm, bm.displayStats, ct.mainEnv.player)
    local result = {
        player = { stats = playerStats, skillDPS = playerSkillDPS or { } },
        warnings = pob_collectWarnings(bm, ct.mainEnv.player),
        outputRevision = bm.outputRevision or 0,
    }
    if ct.mainEnv.minion then
        local minionStats = pob_buildStatRecords(bm, bm.minionDisplayStats, ct.mainEnv.minion)
        result.minion = { stats = minionStats }
    end
    if ct.mainEnv.player.mainSkill and ct.mainEnv.player.mainSkill.skillFlags and ct.mainEnv.player.mainSkill.skillFlags.disable then
        result.disableReason = ct.mainEnv.player.mainSkill.disableReason
    end
    return result
end

-- Part 2.3 selftest: read the sidebar output and assert it has at least one
-- stat and the outputRevision matches the live counter. ADDITIVE.
function pob_selftestOutput()
    local d = pob_getOutput()
    if not d then return { ok = false, error = "no output" } end
    local ok = d.player and d.player.stats and #d.player.stats > 0
    return {
        ok = ok,
        statCount = d.player and #d.player.stats or 0,
        warningCount = d.warnings and #d.warnings or 0,
        outputRevision = d.outputRevision,
    }
end

-- ============================================================================
-- Part 2.4: Comparison-calculator bridge. calcsTab.miscCalculator/.nodeCalculator
-- (CalcsTab.lua:449-450, `{calcFunc, baseOutput}`) are already rebuilt fresh by
-- every CalcsTabClass:BuildOutput() call -- i.e. every pob_recalculate() that
-- actually recalculates (Part 2.2). Reuse those persistent closures directly:
-- re-running calcs.getMiscCalculator/getNodeCalculator per call would pay a
-- full initEnv+perform cost per hover (the SAME cost as a full recalc, ~25-
-- 300ms per Part 2.1's spike) and defeat the entire point of the calculator
-- pattern, whose measured 2-6.7ms/call cost assumes the persistent closure.
--
-- Host-safe override vocabulary (node ids instead of node object refs,
-- raw item text instead of a live Item object -- see calc-engine-contract.md):
--   { addNodes = {id,...}, removeNodes = {id,...},
--     repSlotName = "Weapon 1", repItemRaw = "<raw item text>",
--     toggleFlask = <flaskItemId>, toggleTincture = <tinctureItemId>,
--     useFullDPS = bool }
-- ============================================================================

-- Port of buildMode:CompareStatList (Build.lua:1811) to structured diff
-- records instead of tooltip lines.
local function pob_diffStatList(statList, actor, baseOutput, compareOutput)
    local diffs = { }
    for _, statData in ipairs(statList) do
        if statData.stat and pob_matchFlags(statData.flag, statData.notFlag, actor.mainSkill.skillFlags)
           and not statData.childStat and statData.stat ~= "SkillDPS" then
            local statVal1 = compareOutput[statData.stat] or 0
            local statVal2 = baseOutput[statData.stat] or 0
            local diff = statVal1 - statVal2
            if statData.stat == "FullDPS" and not compareOutput[statData.stat] then
                diff = 0
            end
            if (diff > 0.001 or diff < -0.001) and (not statData.condFunc or statData.condFunc(statVal1, compareOutput) or statData.condFunc(statVal2, baseOutput)) then
                local positive = (statData.lowerIsBetter and diff < 0) or (not statData.lowerIsBetter and diff > 0)
                local val = diff * ((statData.pc or statData.mod) and 100 or 1)
                local valStr = string.format("%+" .. statData.fmt, val)
                local number, suffix = valStr:match("^([%+%-]?%d+%.%d+)(%D*)$")
                if number then
                    valStr = number:gsub("0+$", ""):gsub("%.$", "") .. suffix
                end
                valStr = formatNumSep(valStr)
                local percent = nil
                if statData.compPercent and statVal1 ~= 0 and statVal2 ~= 0 then
                    percent = statVal1 / statVal2 * 100 - 100
                end
                diffs[#diffs + 1] = {
                    stat = statData.stat,
                    label = statData.label,
                    diff = diff,
                    diffStr = valStr,
                    positive = positive,
                    percent = percent,
                }
            end
        end
    end
    return diffs
end

-- Translate a host id list into the node-object set/array the engine expects
-- (CalcSetup.lua:594-630: addNodes is `for node in pairs(t)` object-keyed,
-- removeNodes is checked the same way against env.spec.allocNodes' object keys).
local function pob_nodeSetFromIds(spec, idList)
    local set = { }
    if not idList then return set, false end
    local any = false
    for _, id in ipairs(idList) do
        local node = spec.nodes[tonumber(id) or id]
        if node then
            set[node] = true
            any = true
        end
    end
    return set, any
end

-- The whole comparison surface (calc-engine-contract.md): node hover, item/
-- anoint tooltips, flask/tincture toggles, spec compares. Returns a diffed
-- stat list (player + minion) against the misc calculator's baseline.
function pob_compareOverride(override)
    local bm = main and main.modes and main.modes.BUILD
    local ct = bm and bm.calcsTab
    if not bm or not ct then return nil end
    pob_recalculate()
    if not ct.miscCalculator or not ct.miscCalculator[1] then
        return { ok = false, error = "no misc calculator" }
    end
    local calcFunc, baseOutput = ct.miscCalculator[1], ct.miscCalculator[2]

    override = override or { }
    local luaOverride = { }
    local addSet, hasAdd = pob_nodeSetFromIds(bm.spec, override.addNodes)
    local removeSet, hasRemove = pob_nodeSetFromIds(bm.spec, override.removeNodes)
    if hasAdd then luaOverride.addNodes = addSet end
    if hasRemove then luaOverride.removeNodes = removeSet end

    if override.repSlotName and override.repItemId then
        -- Compare against an item already in the build. Cheaper and lossless vs
        -- round-tripping through raw text, and it cannot perturb any editor state.
        local item = bm.itemsTab.items[override.repItemId]
        if item and item.base then
            luaOverride.repSlotName = override.repSlotName
            luaOverride.repItem = item
        end
    elseif override.repSlotName and override.repItemRaw and override.repItemRaw ~= "" then
        -- Build the candidate item DIRECTLY. This deliberately does NOT go through
        -- itemsTab:CreateDisplayItemFromRaw (ItemsTab.lua:1658), which a previous
        -- revision used and which is wrong here on two counts:
        --   1. It runs CopyAnointsAndEldritchImplicits (ItemsTab.lua:1661) first, so
        --      the item being compared silently inherits the EQUIPPED amulet's anoint
        --      and the equipped Eater/Exarch implicits -- the compare then reports the
        --      diff for an item the user never asked about. (That grafting is correct
        --      and intended on the *editor* path; it must not happen on the *compare*
        --      path.)
        --   2. It ends in SetDisplayItem (ItemsTab.lua:1666), clobbering
        --      itemsTab.displayItem -- i.e. a mere hover-compare would destroy
        --      whatever the user is editing once Phase 6's display-item editor exists.
        local item = new("Item", override.repItemRaw)
        if item and item.base then
            luaOverride.repSlotName = override.repSlotName
            luaOverride.repItem = item
        end
    elseif override.repSlotName then
        -- No repItemRaw: compare "what if this slot were empty".
        luaOverride.repSlotName = override.repSlotName
    end
    -- env.flasks/env.tinctures (CalcSetup.lua:422-423,911,927) are keyed by the
    -- actual flask/tincture Item OBJECT (env.flasks[item] = true), not an id --
    -- resolve the host-safe item id through itemsTab.items before handing it to
    -- the calculator, else this silently inserts a garbage non-object key that
    -- calcs.perform's `for item in pairs(env.flasks) do ... item.baseName ...`
    -- loop would crash on.
    if override.toggleFlask then
        local flaskItem = bm.itemsTab.items[tonumber(override.toggleFlask) or override.toggleFlask]
        if flaskItem then luaOverride.toggleFlask = flaskItem end
    end
    if override.toggleTincture then
        local tinctureItem = bm.itemsTab.items[tonumber(override.toggleTincture) or override.toggleTincture]
        if tinctureItem then luaOverride.toggleTincture = tinctureItem end
    end

    local ok, compareOutput = pcall(calcFunc, luaOverride, override.useFullDPS)
    if not ok or not compareOutput then
        return { ok = false, error = tostring(compareOutput) }
    end

    local diffs = pob_diffStatList(bm.displayStats, ct.mainEnv.player, baseOutput, compareOutput)
    local minionDiffs = nil
    if ct.mainEnv.player.mainSkill and ct.mainEnv.player.mainSkill.minion and baseOutput.Minion and compareOutput.Minion then
        minionDiffs = pob_diffStatList(bm.minionDisplayStats, ct.mainEnv.minion, baseOutput.Minion, compareOutput.Minion)
    end
    return { ok = true, stats = diffs, minionStats = minionDiffs, outputRevision = bm.outputRevision or 0 }
end

-- Node-hover compare (tree heat-map path): a fast add-only calculator, matching
-- calcs.getNodeCalculator's modFunc signature (Calcs.lua:115-120).
function pob_compareNodes(nodeIds)
    local bm = main and main.modes and main.modes.BUILD
    local ct = bm and bm.calcsTab
    if not bm or not ct or not nodeIds or #nodeIds == 0 then return nil end
    pob_recalculate()
    if not ct.nodeCalculator or not ct.nodeCalculator[1] then
        return { ok = false, error = "no node calculator" }
    end
    local calcFunc, baseOutput = ct.nodeCalculator[1], ct.nodeCalculator[2]

    local nodeList = { }
    for _, id in ipairs(nodeIds) do
        local node = bm.spec.nodes[tonumber(id) or id]
        if node then nodeList[#nodeList + 1] = node end
    end
    if #nodeList == 0 then return { ok = false, error = "no valid nodes" } end

    local ok, compareOutput = pcall(calcFunc, nodeList)
    if not ok or not compareOutput then
        return { ok = false, error = tostring(compareOutput) }
    end

    local diffs = pob_diffStatList(bm.displayStats, ct.mainEnv.player, baseOutput, compareOutput)
    return { ok = true, stats = diffs, outputRevision = bm.outputRevision or 0 }
end

-- Part 2.4 selftest: allocate a real allocatable node (found live off the tree,
-- not hardcoded -- ids differ across tree versions), compare it via
-- pob_compareNodes, and assert we get back a non-empty diffed stat list. Then
-- exercise pob_compareOverride's item-replacement path against slot "Weapon 1"
-- with no repItemRaw (the "unequip" comparison), which must simply not crash
-- (empty diff is a legal result when nothing is equipped there). Side-effect-
-- free: never allocates for real, never adds an item.
function pob_selftestCompare()
    local bm = main and main.modes and main.modes.BUILD
    local spec = bm and bm.spec
    if not bm or not spec then return { ok = false, error = "no build" } end

    -- Find an unallocated Normal node directly linked to an allocated one (same
    -- selection rule as pob_selftestTreeInteract, Phase 4b) -- excludes Mastery/
    -- Keystone/ascendancy nodes, which have extra allocation preconditions the
    -- node calculator's plain addNodes path doesn't need to handle here.
    local candidateId = nil
    for id, node in pairs(spec.nodes) do
        if node.type == "Normal" and node.path and not node.alloc and not node.ascendancyName then
            for _, linked in ipairs(node.linked) do
                if linked.alloc then
                    candidateId = id
                    break
                end
            end
        end
        if candidateId then break end
    end
    if not candidateId then
        return { ok = false, error = "no candidate node found" }
    end

    local nodeResult = pob_compareNodes({ candidateId })
    if not nodeResult or not nodeResult.ok then
        return { ok = false, error = "compareNodes failed", detail = nodeResult }
    end

    local overrideResult = pob_compareOverride({ repSlotName = "Weapon 1" })
    if not overrideResult or not overrideResult.ok then
        return { ok = false, error = "compareOverride failed", detail = overrideResult }
    end

    -- A raw-text compare must be side-effect-free on the editor buffer. An earlier
    -- revision routed this through itemsTab:CreateDisplayItemFromRaw, which ends in
    -- SetDisplayItem (ItemsTab.lua:1666) and therefore destroyed whatever the user
    -- was editing on every hover. Pin a sentinel, compare, and assert the sentinel
    -- survived byte-identical.
    local sentinel = { base = false, _pobSelftestSentinel = true }
    local savedDisplayItem = bm.itemsTab.displayItem
    bm.itemsTab.displayItem = sentinel
    local rawResult = pob_compareOverride({
        repSlotName = "Weapon 1",
        repItemRaw = "Rarity: Normal\nDriftwood Wand\nWand",
    })
    local displayItemIntact = rawResult and (bm.itemsTab.displayItem == sentinel)
    bm.itemsTab.displayItem = savedDisplayItem

    if not rawResult or not rawResult.ok then
        return { ok = false, error = "compareOverride(repItemRaw) failed", detail = rawResult }
    end
    if not displayItemIntact then
        return { ok = false, error = "compareOverride clobbered itemsTab.displayItem" }
    end

    return {
        ok = true,
        candidateId = candidateId,
        nodeDiffCount = #nodeResult.stats,
        overrideDiffCount = #overrideResult.stats,
        rawDiffCount = #rawResult.stats,
        displayItemIntact = displayItemIntact,
    }
end

-- ============================================================================
-- Part 2.5: Config usage-set export. env.conditionsUsed/enemyConditionsUsed/
-- minionConditionsUsed/multipliersUsed/enemyMultipliersUsed/perStatsUsed/
-- enemyPerStatsUsed/tagTypesUsed/modsUsed (Calcs.lua:493-501, populated only in
-- MAIN mode) map varName -> array-of-mod-object-refs; the objects are not
-- serializable (Combine/Tabulate closures + item/mod cross-refs) and per
-- calc-engine-contract.md the export is "names only, drop mod refs". skillsUsed
-- (Calcs.lua:481-491) and keystonesAdded (CalcPerform.lua:1103) are already
-- plain varName->true boolean sets, so they pass through unchanged. This drives
-- Config option visibility predicates (ConfigVisibility.lua's ifCond/ifStat/...
-- read mainEnv.conditionsUsed[var] etc. as a simple truthy check) -- Phase 7.
-- ============================================================================
local function pob_namesOnly(setOfArrays)
    local out = { }
    if not setOfArrays then return out end
    for name in pairs(setOfArrays) do
        out[name] = true
    end
    return out
end

function pob_getConfigUsageSets()
    local bm = main and main.modes and main.modes.BUILD
    local env = bm and bm.calcsTab and bm.calcsTab.mainEnv
    if not env then return nil end
    return {
        conditionsUsed = pob_namesOnly(env.conditionsUsed),
        enemyConditionsUsed = pob_namesOnly(env.enemyConditionsUsed),
        minionConditionsUsed = pob_namesOnly(env.minionConditionsUsed),
        multipliersUsed = pob_namesOnly(env.multipliersUsed),
        enemyMultipliersUsed = pob_namesOnly(env.enemyMultipliersUsed),
        perStatsUsed = pob_namesOnly(env.perStatsUsed),
        enemyPerStatsUsed = pob_namesOnly(env.enemyPerStatsUsed),
        tagTypesUsed = pob_namesOnly(env.tagTypesUsed),
        modsUsed = pob_namesOnly(env.modsUsed),
        skillsUsed = env.skillsUsed or { },
        keystonesAdded = env.keystonesAdded or { },
        outputRevision = bm.outputRevision or 0,
    }
end

-- Part 2.5 selftest: force a recalc so mainEnv is fresh, then assert the usage
-- sets are non-empty tables of plain booleans (every build allocates at least
-- one skill/condition) and that a known-always-true condition survived the
-- names-only conversion.
function pob_selftestConfigUsage()
    local bm = main and main.modes and main.modes.BUILD
    if not bm then return { ok = false, error = "no build" } end
    bm.buildFlag = true
    pob_recalculate()
    local sets = pob_getConfigUsageSets()
    if not sets then return { ok = false, error = "no usage sets" } end
    local skillCount = 0
    for _ in pairs(sets.skillsUsed) do skillCount = skillCount + 1 end
    for name, v in pairs(sets.conditionsUsed) do
        if type(name) ~= "string" or type(v) ~= "boolean" then
            return { ok = false, error = "conditionsUsed not a plain name->bool set", key = tostring(name) }
        end
    end
    return {
        ok = skillCount > 0,
        skillCount = skillCount,
        outputRevision = sets.outputRevision,
    }
end

-- ============================================================================
-- Part 2.6: Party/buffExports seam audit. PartyTabClass (Classes/PartyTab.lua,
-- unmodified src/) already constructs a real self.enemyModList = new("ModList")
-- and self.enableExportBuffs = false at init (same construction pattern as
-- skillsTab/configTab/itemsTab), consumed unconditionally every calc pass at
-- CalcSetup.lua:565 (env.enemyDB:AddList(build.partyTab.enemyModList)) and
-- written back at CalcPerform.lua:3640 (env.build.partyTab:setBuffExports(...),
-- itself gated on enableExportBuffs, PartyTab.lua:977). No Qt-host stub is
-- needed -- this selftest exercises both the read seam (a real enemy mod
-- affecting output) and the write-back seam (enableExportBuffs=true forcing
-- setBuffExports to actually run) end-to-end, then restores party state.
-- ============================================================================
function pob_selftestParty()
    local bm = main and main.modes and main.modes.BUILD
    local pt = bm and bm.partyTab
    if not pt or not pt.enemyModList or not pt.setBuffExports then
        return { ok = false, error = "partyTab missing expected seam (enemyModList/setBuffExports)" }
    end

    local savedEnable = pt.enableExportBuffs

    -- Read seam: add a real enemy mod and confirm a recalc completes cleanly
    -- with it applied (CalcSetup.lua:565 consumes it unconditionally).
    pt.enemyModList:NewMod("Accuracy", "BASE", 500, "PartySelftest")
    bm.buildFlag = true
    local readResult = pob_recalculate()

    -- Write-back seam: enable export and force perform to actually call
    -- setBuffExports (gated on enableExportBuffs, PartyTab.lua:977).
    pt.enableExportBuffs = true
    bm.buildFlag = true
    local writeResult = pob_recalculate()

    -- Clean up: remove the probe mod and restore enableExportBuffs so later
    -- phases/selftests see an unmodified party state. Matches PartyTabClass's
    -- own reset pattern (PartyTab.lua:337-338) -- wipe AND replace, not just
    -- wipe, since ModList carries internal lookup-cache state alongside the
    -- mod array.
    wipeTable(pt.enemyModList)
    pt.enemyModList = new("ModList")
    pt.enableExportBuffs = savedEnable
    bm.buildFlag = true
    pob_recalculate()

    return {
        ok = readResult.ok and writeResult.ok,
        readOk = readResult.ok,
        writeOk = writeResult.ok,
        error = (not readResult.ok and readResult.error) or (not writeResult.ok and writeResult.error) or nil,
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

    return { summary = summary, sections = sections, outputRevision = bm.outputRevision or 0 }
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
    pob_recalculate()
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
-- Memo for the group-background resolution below, keyed version -> spriteKey.
-- Must live out here (not inside pob_getTreeData) or it is rebuilt on every call,
-- and loadSourceGroupBackground runs once per GROUP -- thousands of times per call.
local _gbCache = { }
-- Bumped by pob_setTreeSearch so the renderer revision below changes when the
-- search highlight changes. A serial rather than a hash of the match list: the
-- search results are the ONLY thing that call mutates, so "it ran again" is
-- exactly the signal, and re-running the same query is cheap to repaint.
local _treeSearchSerial = 0

-- Folds one ALLOCATED node id into the running checksum that feeds
-- pob_getTreeData().revision. File-scope (not inline) so pob_selftestAllocChecksum
-- below can exercise it directly on the id sets that break the naive versions.
--
-- pairs() order over tree.nodes is arbitrary and may differ between calls, so the
-- accumulator has to be COMMUTATIVE -- but it must not be LINEAR, and a scattered
-- SUM is exactly that: sum((id*K) % M) % M == (K * sum(id)) % M, so the constant
-- factors straight back out and EVERY sum-preserving swap still collides
-- ({100,201} vs {101,200} both hash to 121247005; {5000,5003} vs {5001,5002} both
-- to 833093411). Consecutive ids inside one group make {n,n+3} -> {n+1,n+2} an
-- ordinary edit, not a contrived one. Adding sum(id^2) does not save it either
-- ({1,5,6} vs {2,3,7} agree on both sum and sum-of-squares). So: scatter, xor-FOLD
-- the high half onto the low half to break linearity, then combine with xor --
-- commutative (order-independent) and involutive (an undo returns the revision to
-- its exact prior value). `bit` is a LuaJIT built-in.
local function foldAllocId(acc, id)
    local scattered = (tonumber(id) or 0) * 2654435761 % 4294967296
    return bit.bxor(acc, bit.bxor(scattered, math.floor(scattered / 65536)))
end

-- Sprite-sheet resolution: basename -> on-disk path + PIXEL dimensions.
--
-- File-scope, and memoised on ver/base, because the three call sites below run
-- once per NODE ICON, per NODE FRAME and per GROUP -- ~7,400 io.open probes per
-- pob_getTreeData call for a set of ~15 distinct sheets. Negative results are
-- memoised too (as `false`): 10 of the 449 max-zoom sheet references in the
-- shipped TreeData do not exist on disk, and those must not be re-probed per node.
--
-- Probe order is <ver>/<base> then TreeData/<base>, which is what all three call
-- sites already did. It is NOT the order PassiveTree:LoadImage uses (root first,
-- PassiveTree.lua:849) -- that only matters if a basename exists in both places,
-- and none of the atlas sheets do (the root holds only whole standalone images
-- like PSGroupBackgroundN.png, never a `*-3.*` atlas page). Verified rather than
-- assumed, because now that ImageSize() is real the DENOMINATOR of every UV comes
-- from the file the engine measured and the NUMERATOR from the file we measure;
-- if those two ever diverge, every sprite silently samples the wrong rectangle.
local _sheetCache = { }
local function sheetInfo(ver, base)
    if not ver or not base then return nil end
    local key = ver .. "/" .. base
    local hit = _sheetCache[key]
    if hit ~= nil then
        if hit == false then return nil end
        return hit.path, hit.w, hit.h
    end
    local verPath = ((_SRC_DIR .. "/TreeData/" .. ver .. "/" .. base):gsub("\\", "/"))
    local rootPath = ((_SRC_DIR .. "/TreeData/" .. base):gsub("\\", "/"))
    for _, path in ipairs({ verPath, rootPath }) do
        local f = io.open(path, "r")
        if f then
            f:close()
            local w, h = 0, 0
            if pob and pob.imageSize then
                local rw, rh = pob.imageSize(path)
                w, h = tonumber(rw) or 0, tonumber(rh) or 0
            end
            _sheetCache[key] = { path = path, w = w, h = h }
            return path, w, h
        end
    end
    _sheetCache[key] = false
    return nil
end

function pob_getTreeData()
local bm = main and main.modes and main.modes.BUILD
-- Phase 4: the BUILD'S OWN SPEC TREE FIRST, global latest only as the no-build
-- fallback. This order used to be reversed, and because main.tree[latestTreeVersion]
-- is essentially always present the spec branch was dead code -- so a build sitting
-- on, say, a 3_25 spec rendered 3_28 GEOMETRY with that spec's allocation ids
-- painted over it. Every path below reads tree.treeVersion (the tree object's own
-- version), not this local, so correcting the selection is all that is needed.
local tree = (bm and bm.spec and bm.spec.tree)
             or (main and main.tree and latestTreeVersion and main.tree[latestTreeVersion])
if not tree then return nil end
local spec = (bm and bm.spec) or { nodes = { } }

-- (`resolveAsset` and `firstRect` lived here and are gone: both were dead --
-- resolveAsset had zero callers and read tree.assets, which is STALE on 3_20+
-- (a tree with no assets of its own falls back to TreeData/3_19/Assets.lua, so
-- tree.assets holds 3_19 CDN URLs); firstRect's only caller now selects the
-- sub-rect by key so that the sheet it is paired with matches.)

local function nodeSprite(node, alloc)
    local sprites = node.sprites
    if not sprites then return nil end
    -- node.sprites[state] is a spriteMap entry (PassiveTree.lua:689/:712/:819),
    -- built at PassiveTree.lua:288-297 as
    --     { handle, width = coords.w, height = coords.h,
    --       [1] = coords.x / sheet.width,  [2] = coords.y / sheet.height,
    --       [3] = (coords.x+coords.w) / sheet.width, ... }
    -- so [1..4] are NORMALISED UVs in 0..1 and `width`/`height` are the sub-rect's
    -- size in PIXELS. That distinction is NEW: while ImageSize() was stubbed to
    -- 1x1 the divisor was 1, the "UVs" came out as raw pixels, and this function
    -- was written against exactly that. The two had to move in the same commit --
    -- the moment ImageSize tells the truth, reading [1..4] as pixels samples a
    -- sub-pixel speck out of the top-left corner of every sheet.
    -- The sheet file is resolved from tree.skillSprites[state].filename (a CDN
    -- URL); we take its basename and look for the matching local file. This
    -- mirrors PassiveTreeView.lua's sprite selection.
    local sp, sheetKey
    if node.type == "Mastery" then
        -- Mastery art lives in node.masterySprites.{inactiveIcon,activeIcon};
        -- each is a spriteMap entry keyed by mastery* state.
        if node.masterySprites then
            local ms = node.masterySprites[alloc and "activeIcon" or "inactiveIcon"]
            sheetKey = alloc and "masteryActive" or "masteryInactive"
            if type(ms) == "table" then
                sp = ms[sheetKey]
                if not sp then
                    -- Take whatever state this sprite set DOES carry, and take
                    -- that key as the sheet too. The old code took the first
                    -- sub-rect via firstRect() but kept the fixed sheetKey, so a
                    -- rect from one atlas could be sampled out of another --
                    -- harmless while every coordinate was raw pixels into
                    -- equally-sized sheets, but with real normalised UVs the two
                    -- sheets' dimensions differ and the rect lands elsewhere.
                    for k, v in pairs(ms) do
                        if type(v) == "table" and v[1] ~= nil and v[3] ~= nil then
                            sp, sheetKey = v, k
                            break
                        end
                    end
                end
            end
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
    local localPath, sheetW, sheetH = sheetInfo(tree.treeVersion, base)
    if not localPath or sheetW <= 0 or sheetH <= 0 then return nil end

    -- De-normalise back to sheet pixels, which is what the QML canvas samples in.
    local u0, v0, u1, v1 = tonumber(sp[1]), tonumber(sp[2]), tonumber(sp[3]), tonumber(sp[4])
    if not u0 or not v0 or not u1 or not v1 then return nil end
    -- This guards the ENGINE's division, not ours: PassiveTree.lua builds these as
    -- coords.x / sheet.width, and a sheet whose file is missing measures 0x0, so
    -- the "UV" arrives as inf (or nan for a zero numerator). Every comparison below
    -- is false for both, so an unusable sprite is dropped rather than drawn at an
    -- absurd offset. The bound is 1.001 and not 1 because these are floating-point
    -- quotients: the last sub-rect's right/bottom edge lands on 1.0 give or take
    -- an ulp.
    if not (u0 >= 0 and u0 <= 1 and v0 >= 0 and v0 <= 1
            and u1 > u0 and v1 > v0 and u1 <= 1.001 and v1 <= 1.001) then
        return nil
    end
    -- Prefer the sprite data's own pixel width/height over (u1-u0)*sheetW: it is
    -- the exact integer the atlas was cut with, not a quotient multiplied back out.
    local sw = tonumber(sp.width) or 0
    local sh = tonumber(sp.height) or 0
    if sw <= 0 or sh <= 0 then
        sw, sh = (u1 - u0) * sheetW, (v1 - v0) * sheetH
    end
    if sw <= 0 or sh <= 0 then return nil end
    local sx = math.floor(u0 * sheetW + 0.5)
    local sy = math.floor(v0 * sheetH + 0.5)
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
    -- Memoised: this ran an io.open per NODE for one of ~2 distinct sheets.
    -- `rect` stays in raw pixels -- it comes from the shipped sprites.lua, which
    -- is authored in pixels and is not touched by ImageSize()/UV normalisation.
    local localPath = sheetInfo(tree.treeVersion, base)
    if not localPath then return nil end
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
    local gb = loadSourceGroupBackground(spriteKey)
    if gb and gb.filename then
        local base = gb.filename:match("([^/]+)%?") or gb.filename:match("([^/]+)$")
        -- Memoised, and the same <ver>/<base>-then-TreeData/<base> order this
        -- probe already used: the 3_25+ atlas page lives under <ver>/, the
        -- <=3_24 standalone PSGroupBackgroundN.png at the TreeData root.
        -- Ran once per GROUP before, which is the bulk of the old probe count.
        local p = sheetInfo(tree.treeVersion, base)
        if p then
            -- No "any rect will do" fallback here: loadSourceGroupBackground
            -- only ever returns a table that HAS coords[spriteKey], so picking an
            -- arbitrary sibling rect could never fire and would silently paint the
            -- wrong-size backdrop if it did.
            local rect = gb.coords and gb.coords[spriteKey]
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

-- Group-background geometry, resolved from shipped data for EVERY tree version
-- (this used to be a static table with a single "3_28" entry, so every other
-- version drew no group backdrops at all).
--
-- The runtime tree.assets["PSGroupBackgroundN"] entries cannot be used: their
-- per-scale `coords` are empty (the engine never populates group-background
-- geometry) and their width/height come from the stubbed ImageSize(), so they
-- are all 1x1. Two genuine sources between them cover the whole version range:
--
--   3_25+  TreeData/<ver>/sprites.lua ships a `groupBackground` atlas asset
--          (filename + the PSGroupBackground1/2/3 sub-rects). Reuse the existing
--          loadSourceSprites() memo -- same file, already parsed once per version.
--   <=3_24 No sprites.lua exists. Legacy falls back to the shared
--          TreeData/3_19/Assets.lua table, whose PSGroupBackgroundN entries are
--          scale-keyed CDN URLs that PassiveTree:LoadImage resolves to the
--          STANDALONE TreeData/PSGroupBackgroundN.png at the TreeData root
--          (LoadImage probes "TreeData/<name>" before "TreeData/<ver>/<name>").
--          Those are whole images rather than atlas pages, so the sub-rect is the
--          entire file and the size has to come from the PNG itself.
--
-- Both branches return the same { filename, coords } shape resolveGroupBackground
-- already consumes, and its existing "<ver>/<base> then <root>/<base>" probe
-- locates the standalone files with no further change.

-- (A hand-rolled PNG IHDR reader lived here. It existed ONLY because
-- ImageSize() was stubbed, which made the image handle unusable for sizing
-- the standalone group-background files; sheetInfo() above now measures any
-- format through the real pob.imageSize, so the workaround -- and the
-- byte-built PNG signature constant it needed -- are gone with it.)

function loadSourceGroupBackground(spriteKey)
    local ver = tree.treeVersion
    local byKey = _gbCache[ver]
    if not byKey then byKey = { }; _gbCache[ver] = byKey end
    local cached = byKey[spriteKey]
    if cached ~= nil then return cached or nil end

    -- 3_25+: the atlas asset shipped next to the tree.
    local sprites = loadSourceSprites()
    local gb = sprites and sprites.groupBackground
    if gb and gb.filename and gb.coords and gb.coords[spriteKey] then
        byKey[spriteKey] = gb
        return gb
    end

    -- <=3_24: the standalone root PNG. sheetInfo probes <ver>/<base> then the
    -- TreeData root, and these files only ever exist at the root, so it lands
    -- on the same file PassiveTree:LoadImage would -- now measured for real.
    local base = spriteKey .. ".png"
    local _, w, h = sheetInfo(tree.treeVersion, base)
    if not w or w <= 0 or not h or h <= 0 then
        byKey[spriteKey] = false
        return nil
    end
    local built = { filename = base, coords = { [spriteKey] = { x = 0, y = 0, w = w, h = h } } }
    byKey[spriteKey] = built
    return built
end

local function groupSprite(group)
    return resolveGroupBackground(group.oo)
end

local nodes = { }
local allocCount = 0
-- Checksum of the ALLOCATED node ids, feeding the `revision` returned below.
-- See foldAllocId's note above for why it is an xor-fold and not a sum.
local allocSum = 0
for id, node in pairs(tree.nodes) do
    -- Match PassiveTreeView.lua's clickable/renderable-node predicate. In
    -- particular, neither a node proxy nor a proxy group is a real target;
    -- allowing either here created invisible hit targets over cluster graphs.
    if node.group and node.rsq and not node.isProxy and not node.group.isProxy then
        local alloc = spec.nodes[id] and spec.nodes[id].alloc or false
        if alloc then
            allocCount = allocCount + 1
            allocSum = foldAllocId(allocSum, id)
        end
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
            -- C++ consumes these to reproduce legacy's per-node hit circle
            -- without a QVariantMap scan on every mouse move.
            rsq = node.rsq,
            isProxy = node.isProxy or false,
            hasGroup = node.group ~= nil,
            groupIsProxy = node.group.isProxy or false,
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

local function resolveConnectorAtlas(cType, state)
    local assetName = (cType or "LineConnector") .. (state or "Normal")
    local asset = tree.assets and tree.assets[assetName]
    if asset and asset.handle and asset.handle.fileName then
        local fn = asset.handle.fileName:gsub("\\", "/")
        return "file:///" .. (_SRC_DIR .. "/" .. fn):gsub("\\", "/")
    end
    -- Fallback: probe via sheetInfo
    local p = sheetInfo(tree.treeVersion, assetName .. ".png")
    if p then return "file:///" .. p end
    local p2 = sheetInfo(tree.treeVersion, "line-3.png")
    if p2 then return "file:///" .. p2 end
    return nil
end

local connectors = { }
local function addConnectorRecord(c)
    local n1 = tree.nodes[c.nodeId1]
    local n2 = tree.nodes[c.nodeId2]
    if n1 and n2 then
        local a1 = spec.nodes[c.nodeId1] and spec.nodes[c.nodeId1].alloc or false
        local a2 = spec.nodes[c.nodeId2] and spec.nodes[c.nodeId2].alloc or false
        local state = (a1 and a2) and "Active" or "Normal"
        local vert = c.vert and (c.vert[state] or c.vert["Normal"] or c) or c
        local vertArr = {
            tonumber(vert[1]) or n1.x, tonumber(vert[2]) or n1.y,
            tonumber(vert[3]) or n1.x, tonumber(vert[4]) or n1.y,
            tonumber(vert[5]) or n2.x, tonumber(vert[6]) or n2.y,
            tonumber(vert[7]) or n2.x, tonumber(vert[8]) or n2.y,
        }
        local cTable = c.c or { }
        local uvArr = {
            tonumber(cTable[9]) or 0, tonumber(cTable[10]) or 0,
            tonumber(cTable[11]) or 0, tonumber(cTable[12]) or 0,
            tonumber(cTable[13]) or 0, tonumber(cTable[14]) or 0,
            tonumber(cTable[15]) or 0, tonumber(cTable[16]) or 0,
        }
        local isArc = (c.type and tostring(c.type):sub(1, 5) == "Orbit") or false
        connectors[#connectors + 1] = {
            nodeId1 = c.nodeId1,
            nodeId2 = c.nodeId2,
            type = c.type or "LineConnector",
            ascendancyName = c.ascendancyName,
            state = state,
            isArc = isArc,
            x1 = n1.x, y1 = n1.y,
            x2 = n2.x, y2 = n2.y,
            vert = vertArr,
            uv = uvArr,
            atlas = resolveConnectorAtlas(c.type, state),
        }
    end
end

for _, c in pairs(tree.connectors) do
    addConnectorRecord(c)
end
if spec.subGraphs then
    for _, subGraph in pairs(spec.subGraphs) do
        if subGraph.connectors then
            for _, c in pairs(subGraph.connectors) do
                addConnectorRecord(c)
            end
        end
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
    -- Opaque revision for the renderer's rebuild throttle. Folds every input that
    -- changes what the canvas should draw: the tree version (a spec switch can move
    -- geometry wholesale), the node/alloc counts, the allocated-id checksum (catches
    -- same-count swaps) and the search serial. A ':'-joined string rather than a
    -- packed integer so no component can overflow into another's bits.
    revision = table.concat({
        tostring(tree.treeVersion),
        tostring(#nodes),
        tostring(allocCount),
        string.format("%.0f", allocSum),
        tostring(_treeSearchSerial),
    }, ":"),
}
end

-- Phase 4: the tree the renderer is handed must be the tree the SPEC is on.
-- Guards the regression where pob_getTreeData preferred main.tree[latestTreeVersion]
-- unconditionally, so an older spec silently rendered latest-version geometry.
function pob_selftestTreeVersion()
    local bm = main and main.modes and main.modes.BUILD
    if not bm or not bm.spec then return { ok = false, error = "no build" } end
    local d = pob_getTreeData()
    if not d then return { ok = false, error = "no tree data" } end
    local specVersion = bm.spec.treeVersion or (bm.spec.tree and bm.spec.tree.treeVersion)
    local dataVersion = d.assetBasePath and d.assetBasePath:match("TreeData/(.+)$")
    return {
        ok = (specVersion ~= nil) and (dataVersion == specVersion),
        specVersion = tostring(specVersion),
        dataVersion = tostring(dataVersion),
        latestVersion = tostring(latestTreeVersion),
    }
end

function pob_selftestTreeRender()
local d = pob_getTreeData()
if not d then return { ok = false, error = "no tree" } end

-- Sprite geometry: the direct evidence that the real ImageSize() and the UV
-- consumption landed COHERENTLY, which is the whole risk in that change.
--   * node.sprites[1..4] are NORMALISED UVs (PassiveTree.lua:288-297). Read as
--     raw pixels -- which is what this seam did while ImageSize() was stubbed to
--     1x1 -- every sub-rect collapses to a sub-pixel speck in the top-left corner
--     of its sheet, so `sw >= 1` fails for every sprite on the tree.
--   * De-normalising against the WRONG sheet puts the rect outside that sheet's
--     bounds, so `sx + sw <= atlasW` fails.
-- Both are checked against the atlas each sprite actually names, measured through
-- the same pob.imageSize primitive (memoised C++-side, so this costs ~15 header
-- reads, not one per node).
local checked, bad, badSample = 0, 0, nil
local minW, maxW = math.huge, 0
local function checkSprite(sp)
    if not sp or not sp.atlas then return false end
    local path = sp.atlas:gsub("^file:///", "")
    local aw, ah = 0, 0
    if pob and pob.imageSize then
        local rw, rh = pob.imageSize(path)
        aw, ah = tonumber(rw) or 0, tonumber(rh) or 0
    end
    checked = checked + 1
    local sx, sy = tonumber(sp.sx) or -1, tonumber(sp.sy) or -1
    local sw, sh = tonumber(sp.sw) or 0, tonumber(sp.sh) or 0
    -- +1 of slack on the far edge only: sx/sy are rounded to whole pixels, so a
    -- rect flush against the right or bottom edge can round one pixel past it.
    local okRect = aw > 0 and ah > 0
        and sw >= 1 and sh >= 1
        and sx >= 0 and sy >= 0
        and sx + sw <= aw + 1 and sy + sh <= ah + 1
    if not okRect then
        bad = bad + 1
        if not badSample then
            badSample = string.format("%s [%s,%s %sx%s] in sheet %sx%s",
                tostring(path), tostring(sx), tostring(sy),
                tostring(sw), tostring(sh), tostring(aw), tostring(ah))
        end
    end
    if sw < minW then minW = sw end
    if sw > maxW then maxW = sw end
    return true
end

local iconCount, frameCount, groupCount = 0, 0, 0
for _, n in ipairs(d.nodes) do
    if checkSprite(n.iconSprite) then iconCount = iconCount + 1 end
    if checkSprite(n.frameSprite) then frameCount = frameCount + 1 end
end
for _, g in ipairs(d.groups) do
    if checkSprite(g.sprite) then groupCount = groupCount + 1 end
end
local arcCount, lineCount, badConnectors = 0, 0, 0
for _, c in ipairs(d.connectors) do
    if c.isArc then arcCount = arcCount + 1 else lineCount = lineCount + 1 end
    if not (c.vert and #c.vert == 8 and c.uv and #c.uv == 8) then
        badConnectors = badConnectors + 1
    end
end

return {
    ok = #d.nodes > 0 and #d.groups > 0 and #d.connectors > 0
          and d.bounds and d.bounds.size > 0
          and iconCount > 0 and frameCount > 0 and groupCount > 0
          and bad == 0 and badConnectors == 0 and arcCount > 0,
    nodeCount = #d.nodes,
    groupCount = #d.groups,
    connectorCount = #d.connectors,
    arcCount = arcCount,
    lineCount = lineCount,
    badConnectors = badConnectors,
    spriteIcons = iconCount,
    spriteFrames = frameCount,
    spriteGroupBgs = groupCount,
    spriteChecked = checked,
    spriteBad = bad,
    spriteMinW = minW,
    spriteMaxW = maxW,
    spriteBadSample = badSample,
}
end

-- Phase 4b marker (diagnostic)

-- Phase 4b: passive-tree interaction bridge. Top-level globals (NOT pob.*) because
-- LuaEngine::callGlobal does a single lua_getglobal and cannot resolve dotted names.
-- These wrap spec:AllocNode / spec:DeallocNode and trigger a recalc via
-- pob_recalculate() (Part 2.2's canonical buildFlag-consumer), so calcsTab.mainOutput
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
    -- Legacy PassiveTreeView adds an undo state after every real allocation.
    -- Qt has no legacy Control callback path, so this must live at the bridge
    -- seam or tree edits silently bypass Ctrl+Z.
    spec:AddUndoState()
    -- Trigger a recalc through the engine's canonical dirty-flag path. pob_recalculate
    -- itself pcalls BuildOutput, so a recalc hiccup can never mask the (already
    -- applied) allocation.
    bm.buildFlag = true
    pob_recalculate()
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
    -- Same ordering as legacy (PassiveTreeView.lua:372): snapshot the result
    -- of the cascading deallocation, not merely the clicked node.
    spec:AddUndoState()
    bm.buildFlag = true
    pob_recalculate()
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
    _treeSearchSerial = _treeSearchSerial + 1
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
    -- ALL of them, not just the first two: the first two drive the single-node
    -- SWAP case, and the full list is searched for a sum-preserving PAIR swap
    -- further down. Every candidate is chosen while the tree is untouched, so each
    -- is linked to an ORIGINALLY allocated node and none depends on another being
    -- allocated.
    local cands = { }
    for id, node in pairs(spec.nodes) do
        if node.type == "Normal" and node.path and not node.alloc and not node.ascendancyName then
            local linkedToAlloc = false
            for _, ln in ipairs(node.linked) do
                if ln.alloc then linkedToAlloc = true; break end
            end
            if linkedToAlloc and tonumber(id) then
                cands[#cands + 1] = id
            end
        end
    end
    -- pairs() order is arbitrary; sort so the fixture picks the same nodes on every
    -- run and a failure is reproducible.
    table.sort(cands, function(l, r) return tonumber(l) < tonumber(r) end)
    local targetId, targetId2 = cands[1], cands[2]
    if not targetId then
        res.error = "no allocatable normal node found"
        return res
    end

    -- The renderer rebuild throttle keys off pob_getTreeData().revision, so the
    -- revision has to move for every edit below -- and, just as importantly, has to
    -- come BACK to its old value when an edit is undone.
    local function revision()
        local d = pob_getTreeData()
        return d and d.revision or nil
    end
    -- Earlier selftests intentionally mutate the fixture before arriving here;
    -- their direct engine calls predate this bridge and do not all create undo
    -- snapshots. Start the undo probe from a real current-state baseline, just
    -- as PassiveSpec does after a load, so Undo is asserted against this edit.
    spec:ResetUndo()
    local rev0 = revision()
    local before = select(1, spec:CountAllocNodes())
    local undoBefore = #spec.undo
    local a = pob_allocNode(targetId)
    if not a or not a.ok then
        res.error = "alloc failed"
        return res
    end
    local after = select(1, spec:CountAllocNodes())
    res.allocOk = (after >= before + 1) and (spec.nodes[targetId].alloc == true)
    -- The bridge must add exactly the same post-change undo snapshot that
    -- PassiveTreeView does. Exercise Undo/Redo too: a growing undo array alone
    -- would not prove that Ctrl+Z returns the allocation state to its predecessor.
    res.undoAllocSnapshotOk = (#spec.undo == undoBefore + 1)
    spec:Undo()
    res.undoAllocRestoresOk = (not spec.nodes[targetId].alloc)
                              and (select(1, spec:CountAllocNodes()) == before)
    spec:Redo()
    res.redoAllocRestoresOk = spec.nodes[targetId].alloc
                              and (select(1, spec:CountAllocNodes()) == after)
    local revAlloc = revision()
    local undoBeforeDealloc = #spec.undo
    local d = pob_deallocNode(targetId)
    if not d or not d.ok then
        res.error = "dealloc failed"
        return res
    end
    local restored = select(1, spec:CountAllocNodes())
    res.deallocOk = (restored == before) and (spec.nodes[targetId].alloc == false)
    res.undoDeallocSnapshotOk = (#spec.undo == undoBeforeDealloc + 1)
    local revDealloc = revision()
    res.revAllocOk = (rev0 ~= nil) and (revAlloc ~= nil) and (revAlloc ~= rev0)
    res.revRestoreOk = (revDealloc == rev0)

    -- The case the old `allocCount * 1000003 + nodeCount` signature could not see:
    -- swap one allocated node for another. Node and alloc counts are IDENTICAL
    -- either side of the swap, so anything counting nodes reports "no change" and
    -- the canvas keeps painting the node that is no longer allocated.
    if targetId2 then
        pob_allocNode(targetId)
        local revA = revision()
        local countA = select(1, spec:CountAllocNodes())
        pob_deallocNode(targetId)
        pob_allocNode(targetId2)
        local revB = revision()
        local countB = select(1, spec:CountAllocNodes())
        res.swapCountsEqual = (countA == countB)   -- the collision precondition
        res.revSwapOk = (revA ~= nil) and (revB ~= nil) and (revA ~= revB)
        pob_deallocNode(targetId2)
    else
        -- Only one allocatable node on this tree: nothing to swap, so do not fail
        -- the gate on a case the fixture cannot construct.
        res.swapCountsEqual = true
        res.revSwapOk = true
        res.swapSkipped = true
    end

    -- The harder case, and the one a merely-commutative checksum cannot see: swap
    -- TWO allocated nodes for two others whose ids have the SAME SUM. Any linear
    -- accumulator -- including a sum of ids scattered through a constant, which is
    -- what this checksum used to be -- collides here by construction, because
    -- sum((id*K) % M) % M == (K * sum(id)) % M. A single-node swap does NOT cover
    -- this: it only needs the checksum to be id-sensitive, not non-linear.
    local pairA, pairB = nil, nil
    do
        local n = math.min(#cands, 220)     -- O(n^2) pair scan; 220 -> ~24k pairs
        local bySum = { }
        for i = 1, n - 1 do
            for j = i + 1, n do
                local a, b = cands[i], cands[j]
                local sum = tonumber(a) + tonumber(b)
                local prev = bySum[sum]
                if prev then
                    -- Disjoint pairs only: sharing a node makes the two states
                    -- differ by one id, which is the single-swap case again.
                    if prev[1] ~= a and prev[1] ~= b and prev[2] ~= a and prev[2] ~= b then
                        pairA, pairB = prev, { a, b }
                        break
                    end
                else
                    bySum[sum] = { a, b }
                end
            end
            if pairA then break end
        end
    end
    if pairA then
        local function allocPair(pr)
            local c0 = select(1, spec:CountAllocNodes())
            local okA = pob_allocNode(pr[1])
            local okB = pob_allocNode(pr[2])
            local c1 = select(1, spec:CountAllocNodes())
            return (okA and okA.ok and okB and okB.ok and c1 == c0 + 2) and c1 or nil
        end
        local countA = allocPair(pairA)
        local revA = countA and revision()
        pob_deallocNode(pairA[1]); pob_deallocNode(pairA[2])
        local countB = allocPair(pairB)
        local revB = countB and revision()
        pob_deallocNode(pairB[1]); pob_deallocNode(pairB[2])
        if countA and countB then
            res.swap2SumsEqual = (tonumber(pairA[1]) + tonumber(pairA[2]))
                                 == (tonumber(pairB[1]) + tonumber(pairB[2]))
            res.swap2CountsEqual = (countA == countB)
            res.swap2Ok = (revA ~= nil) and (revB ~= nil) and (revA ~= revB)
            res.swap2Restored = (select(1, spec:CountAllocNodes()) == before)
        else
            -- Allocating a pair did not add exactly two nodes (a path dragged
            -- extra nodes in), so the precondition does not hold on this fixture.
            -- Say so rather than asserting on a state we did not construct.
            res.swap2Skipped = true
        end
    else
        res.swap2Skipped = true
    end
    if res.swap2Skipped then
        res.swap2SumsEqual, res.swap2CountsEqual = true, true
        res.swap2Ok, res.swap2Restored = true, true
    end

    -- Direct, fixture-independent proof of the same property: the id sets below are
    -- sum-preserving (and the third is also sum-of-squares-preserving), so every
    -- linear commutative checksum collides on them. This runs even when the live
    -- tree cannot construct a sum-preserving pair swap.
    local function chk(ids)
        local acc = 0
        for _, id in ipairs(ids) do acc = foldAllocId(acc, id) end
        return acc
    end
    res.checksumNonLinearOk = (chk({ 100, 201 }) ~= chk({ 101, 200 }))
                              and (chk({ 5000, 5003 }) ~= chk({ 5001, 5002 }))
                              and (chk({ 1, 5, 6 }) ~= chk({ 2, 3, 7 }))
    -- ...and still order-independent, which is what pairs() over tree.nodes needs.
    res.checksumCommutativeOk = (chk({ 7, 11, 13 }) == chk({ 13, 7, 11 }))
                                and (chk({ 41, 97, 512 }) == chk({ 512, 41, 97 }))

    pob_setTreeSearch("life")
    local results = pob_getTreeSearchResults()
    res.searchOk = (type(results) == "table" and #results > 0)
    local revSearch = revision()
    -- Search state was entirely absent from the old signature, so a search
    -- highlight never repainted until some unrelated edit moved the counts.
    res.revSearchOk = (revSearch ~= nil) and (revSearch ~= revDealloc)
    pob_setTreeSearch("")
    res.searchClearOk = (#pob_getTreeSearchResults() == 0)
    res.ok = not not (res.allocOk and res.deallocOk and res.searchOk and res.searchClearOk
                      and res.undoAllocSnapshotOk and res.undoAllocRestoresOk
                      and res.redoAllocRestoresOk and res.undoDeallocSnapshotOk
                      and res.revAllocOk and res.revRestoreOk and res.revSwapOk
                      and res.swapCountsEqual and res.revSearchOk
                      and res.swap2Ok and res.swap2SumsEqual and res.swap2CountsEqual
                      and res.swap2Restored
                      and res.checksumNonLinearOk and res.checksumCommutativeOk)
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

-- ============================================================================
-- PHASE 3 -- Build Shell bridge (top bar, side bar state, save/load lifecycle).
--
-- THE ONE THING TO UNDERSTAND ABOUT THIS SECTION: there is no frame loop.
-- The Qt host deliberately removed the 30ms pump (main.cpp), so everything
-- buildMode:OnFrame (Build.lua:1162) used to do EVERY FRAME is dead code here:
--   * self.unsaved            (Build.lua:1254)  -> pob_getUnsaved()
--   * RefreshSkillSelectControls (Build.lua:1237)
--   * class/ascend dropdown resync (Build.lua:1207-1211) -> pob_getClassList()
--   * the Ctrl-key hotkey handler (Build.lua:1173-1204) -> QML Shortcuts
-- Each is ported to an explicit host call below. Do NOT reintroduce a frame
-- pump to "fix" any of them -- that re-creates the GUI freeze Phase 0 removed.
-- ============================================================================

local function pob_buildMode()
    local bm = main and main.modes and main.modes.BUILD
    if not bm or not bm.spec then return nil end
    return bm
end

-- Real unsaved state. Legacy ORs the ten modFlags once per frame into
-- bm.unsaved (Build.lua:1254); with no frame loop that field is permanently
-- stale, which is why SaveLoadModel's isDirty has always been wrong. We compute
-- it on demand AND write it back to bm.unsaved, because unmodified legacy code
-- still reads that field -- buildMode:CanExit (Build.lua:945) and
-- buildMode:Shutdown's dev autosave (Build.lua:958) both branch on it.
function pob_getUnsaved()
    local bm = pob_buildMode()
    if not bm then return { unsaved = false, flags = { } } end
    local flags = {
        build      = bm.modFlag or false,
        notes      = (bm.notesTab and bm.notesTab.modFlag) or false,
        party      = (bm.partyTab and bm.partyTab.modFlag) or false,
        config     = (bm.configTab and bm.configTab.modFlag) or false,
        tree       = (bm.treeTab and bm.treeTab.modFlag) or false,
        treeSearch = (bm.treeTab and bm.treeTab.searchFlag) or false,
        spec       = (bm.spec and bm.spec.modFlag) or false,
        skills     = (bm.skillsTab and bm.skillsTab.modFlag) or false,
        items      = (bm.itemsTab and bm.itemsTab.modFlag) or false,
        calcs      = (bm.calcsTab and bm.calcsTab.modFlag) or false,
    }
    local unsaved = false
    for _, v in pairs(flags) do
        if v then unsaved = true break end
    end
    bm.unsaved = unsaved
    return { unsaved = unsaved, flags = flags }
end

-- Whole top-bar scalar payload in one call.
--
-- EstimatePlayerProgress (Build.lua:890) is NOT a pure getter, which is why it
-- is called exactly once here rather than from any QML binding:
--   * in auto-level mode it MUTATES bm.characterLevel and calls
--     configTab:BuildModList() (Build.lua:901-905);
--   * it appends the three point-overflow strings into
--     bm.controls.warnings.lines via InsertIfNew (Build.lua:916-918) -- a list
--     nothing in the Qt host ever clears, so without the wipe below the
--     warnings would accumulate forever across calls.
-- Legacy clears that same list at the top of RefreshStatList (Build.lua:1770);
-- we do the same, then read the overflow lines straight back out rather than
-- re-deriving the three conditions.
function pob_getShellState()
    local bm = pob_buildMode()
    if not bm then return nil end
    pob_recalculate()

    if bm.controls and bm.controls.warnings then bm.controls.warnings.lines = { } end
    local pointStr, pointTooltip = bm:EstimatePlayerProgress()
    local pointWarnings = { }
    if bm.controls and bm.controls.warnings then
        for _, line in ipairs(bm.controls.warnings.lines) do
            pointWarnings[#pointWarnings + 1] = line
        end
    end

    local used, asc, secondaryAsc = bm.spec:CountAllocNodes()
    local extra = (bm.calcsTab and bm.calcsTab.mainOutput and bm.calcsTab.mainOutput.ExtraPoints) or 0
    local unsaved = pob_getUnsaved()

    return {
        buildName      = bm.buildName or "",
        buildPath      = main.buildPath or "",
        dbFileName     = bm.dbFileName or "",
        dbFileSubPath  = bm.dbFileSubPath or "",
        unsaved        = unsaved.unsaved,
        canSave        = true,
        targetVersion  = bm.targetVersion or "",
        needsConversion = bm.targetVersion == nil,
        level          = bm.characterLevel or 1,
        levelAutoMode  = bm.characterLevelAutoMode or false,
        act            = tostring(bm.Act or ""),
        points = {
            used = used, usedMax = 99 + 23 + extra,
            asc = asc, ascMax = 8,
            secondary = secondaryAsc or 0, secondaryMax = 8,
            str = pointStr, tooltip = pointTooltip,
            warnings = pointWarnings,
        },
        classId                 = bm.spec.curClassId or 0,
        className               = bm.spec.curClassName or "",
        ascendClassId           = bm.spec.curAscendClassId or 0,
        ascendClassName         = bm.spec.curAscendClassName or "",
        secondaryAscendClassId  = bm.spec.curSecondaryAscendClassId or 0,
        sideBarCollapsed        = main.sideBarCollapsed or false,
        showWarnings            = main.showWarnings ~= false,
        devMode                 = (launch and launch.devMode) or false,
        outputRevision          = bm.outputRevision or 0,
    }
end

-- Class / ascendancy dropdown data. Data port of buildMode:UpdateClassDropdowns
-- (Build.lua:1446) + UpdateSecondaryAscendancyDropdown (Build.lua:1115).
-- Both legacy functions pairs()-iterate their source table and then table.sort
-- by label; keeping that trailing sort is load-bearing, because Lua pairs()
-- order is unstable and an unsorted list would reshuffle the dropdown between
-- runs (the same class of bug as the known modeNames() instability).
function pob_getClassList()
    local bm = pob_buildMode()
    if not bm then return nil end
    local treeVersion = bm.spec.treeVersion or latestTreeVersion
    local tree = main.tree and main.tree[treeVersion]
    if not tree then return nil end

    local classes = { }
    for classId, class in pairs(tree.classes) do
        local ascendancies = { }
        for i = 0, #class.classes do
            local ascendClass = class.classes[i]
            if ascendClass then
                ascendancies[#ascendancies + 1] = { ascendClassId = i, label = ascendClass.name }
            end
        end
        classes[#classes + 1] = { classId = classId, label = class.name, ascendancies = ascendancies }
    end
    table.sort(classes, function(a, b) return a.label < b.label end)

    -- Secondary ascendancies: three ids are "legacy" and are hidden unless the
    -- build is currently sitting on one (Build.lua:1120-1127,1138).
    local legacyAlternateAscendancyIds = { Warden = true, Warlock = true, Primalist = true }
    local selection = bm.spec.curSecondaryAscendClassId or 0
    local altAscendancies = bm.spec.tree and bm.spec.tree.alternate_ascendancies
    local secondary = { { ascendClassId = 0, label = "None" } }
    if altAscendancies then
        local sortable = { }
        for ascendClassId, ascendClass in pairs(altAscendancies) do
            if ascendClass and ascendClass.id then
                if not legacyAlternateAscendancyIds[ascendClass.id] or ascendClassId == selection then
                    sortable[#sortable + 1] = { ascendClassId = ascendClassId, label = ascendClass.name }
                end
            end
        end
        table.sort(sortable, function(a, b) return a.label < b.label end)
        for _, entry in ipairs(sortable) do secondary[#secondary + 1] = entry end
    end

    return {
        classes = classes,
        secondaryAscendancies = secondary,
        curClassId = bm.spec.curClassId or 0,
        curAscendClassId = bm.spec.curAscendClassId or 0,
        curSecondaryAscendClassId = selection,
        secondaryEnabled = #secondary > 1,
    }
end

local function pob_applyClass(bm, classId)
    bm.spec:SelectClass(classId)
    bm.spec:AddUndoState()
    bm.buildFlag = true
    pob_recalculate()
end

-- Change class. Ports the classDrop callback (Build.lua:262-285).
--
-- mode = "check"   : apply only if it is free (no allocated nodes, or the new
--                    class start is already connected); otherwise report
--                    needsConfirm and change NOTHING.
--        "force"   : apply, accepting the tree reset (legacy "Continue").
--        "connect" : try spec:ConnectToClass first (legacy "Connect Path");
--                    apply only if that succeeded.
--
-- canConnect is reported as true whenever a confirm is needed, matching legacy,
-- which always offers the button and lets ConnectToClass fail silently. We do
-- NOT probe it up front: ConnectToClass mutates the tree, so a speculative call
-- to find out whether it would work is itself the side effect we are guarding
-- against. The "connect" result reports connected=false if it did not take.
function pob_setClass(classId, mode)
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end
    mode = mode or "check"

    local label = ""
    local treeVersion = bm.spec.treeVersion or latestTreeVersion
    local tree = main.tree and main.tree[treeVersion]
    if tree and tree.classes and tree.classes[classId] then label = tree.classes[classId].name end

    if classId == bm.spec.curClassId then
        return { ok = true, applied = false, needsConfirm = false, label = label }
    end

    if mode == "force" then
        pob_applyClass(bm, classId)
        return { ok = true, applied = true, needsConfirm = false, label = label,
                 outputRevision = bm.outputRevision or 0 }
    elseif mode == "connect" then
        local connected = bm.spec:ConnectToClass(classId) and true or false
        if connected then pob_applyClass(bm, classId) end
        return { ok = true, applied = connected, connected = connected,
                 needsConfirm = false, label = label,
                 outputRevision = bm.outputRevision or 0 }
    end

    if bm.spec:CountAllocNodes() == 0 or bm.spec:IsClassConnected(classId) then
        pob_applyClass(bm, classId)
        return { ok = true, applied = true, needsConfirm = false, label = label,
                 outputRevision = bm.outputRevision or 0 }
    end
    return { ok = true, applied = false, needsConfirm = true, label = label, canConnect = true }
end

function pob_setAscendClass(ascendClassId)
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end
    bm.spec:SelectAscendClass(ascendClassId)
    bm.spec:AddUndoState()
    bm.buildFlag = true
    pob_recalculate()
    return { ok = true, ascendClassId = bm.spec.curAscendClassId or 0,
             outputRevision = bm.outputRevision or 0 }
end

function pob_setSecondaryAscendClass(ascendClassId)
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end
    bm.spec:SelectSecondaryAscendClass(ascendClassId)
    bm.spec:AddUndoState()
    bm.buildFlag = true
    pob_recalculate()
    return { ok = true, secondaryAscendClassId = bm.spec.curSecondaryAscendClassId or 0,
             outputRevision = bm.outputRevision or 0 }
end

-- Level edit. Mirrors the characterLevel EditControl callback (Build.lua:225-232)
-- exactly, including the clamp to 1..100 and the implicit switch to Manual.
function pob_setCharacterLevel(level)
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end
    level = math.min(math.max(tonumber(level) or 1, 1), 100)
    bm.characterLevel = level
    bm.configTab:BuildModList()
    bm.modFlag = true
    bm.buildFlag = true
    bm.characterLevelAutoMode = false
    pob_recalculate()
    return { ok = true, level = bm.characterLevel, auto = false,
             outputRevision = bm.outputRevision or 0 }
end

-- Auto/Manual toggle (Build.lua:218-224). In auto mode the level is re-derived
-- from allocated points by EstimatePlayerProgress, so call that afterwards to
-- settle bm.characterLevel before reporting it.
function pob_setLevelAutoMode(autoMode)
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end
    bm.characterLevelAutoMode = autoMode and true or false
    bm.configTab:BuildModList()
    bm.modFlag = true
    bm.buildFlag = true
    pob_recalculate()
    if bm.characterLevelAutoMode then
        if bm.controls and bm.controls.warnings then bm.controls.warnings.lines = { } end
        bm:EstimatePlayerProgress()
    end
    return { ok = true, auto = bm.characterLevelAutoMode, level = bm.characterLevel or 1,
             outputRevision = bm.outputRevision or 0 }
end

-- Sidebar collapse. Legacy keeps the flag in two places: main.sideBarCollapsed
-- is what Settings.xml persists (Main.lua:107,784), buildMode.sideBarCollapsed
-- is what the layout reads (Build.lua:80,1240). Build:Init copies the former to
-- the latter, so both must be written or the state is lost on the next save.
function pob_setSideBarCollapsed(collapsed)
    collapsed = collapsed and true or false
    main.sideBarCollapsed = collapsed
    local bm = main and main.modes and main.modes.BUILD
    if bm then bm.sideBarCollapsed = collapsed end
    return { ok = true, collapsed = collapsed }
end

-- ---------------------------------------------------------------------------
-- Save / lifecycle
-- ---------------------------------------------------------------------------

-- THE real save. Recalc-gated port of buildMode:SaveDBFile (Build.lua:1994).
--
-- Why this exists when pob_saveBuild already did: buildMode:Save (Build.lua:1036)
-- denormalizes <PlayerStat>/<MinionStat>/<FullDPSSkill> straight out of
-- calcsTab.mainOutput. If buildFlag is dirty those come from the PREVIOUS pass;
-- if mainEnv is nil it throws outright -- and pob_getBuildXML's pcall turned
-- that into a silent nil. Third-party sites that read a PoB export depend on
-- those denormalized stats, so a save that quietly drops them is worse than a
-- save that fails loudly. Hence: recalculate first, and always return a
-- structured {ok=false, error=...} rather than nil.
function pob_saveDBFile(path)
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end

    pob_recalculate()
    local ct = bm.calcsTab
    if not ct or not ct.mainEnv or not ct.mainOutput then
        return { ok = false, error = "no calc output; save aborted" }
    end

    local target = path
    if target == nil or target == "" then target = bm.dbFileName end
    if not target or target == "" then
        return { ok = false, error = "no file name; use Save As" }
    end

    -- Save-As: adopt the new location so subsequent plain Saves go there, and
    -- keep dbFileSubPath consistent with the same slicing legacy uses
    -- (Build.lua:66). Everything is normalised to forward slashes first --
    -- a separator mismatch against main.buildPath silently yields a garbage
    -- subPath, which then corrupts the Save-As folder default.
    if path and path ~= "" and path ~= bm.dbFileName then
        local norm = path:gsub("\\", "/")
        local base = (main.buildPath or ""):gsub("\\", "/")
        local name = norm:match("([^/]+)%.xml$") or norm:match("([^/]+)$") or "Unnamed build"
        bm.dbFileName = norm
        bm.buildName = name
        if #base > 0 and norm:sub(1, #base) == base then
            bm.dbFileSubPath = norm:sub(#base + 1, -#name - 5)
        else
            bm.dbFileSubPath = ""
        end
        target = norm
    end

    local xmlText = bm:SaveDB(target)
    if not xmlText then
        return { ok = false, error = "SaveDB failed to compose XML" }
    end
    local file = io.open(target, "w+")
    if not file then
        return { ok = false, error = "could not open for writing: " .. tostring(target) }
    end
    file:write(xmlText)
    file:close()

    bm.actionOnSave = nil
    bm:ResetModFlags()
    pob_getUnsaved()

    local playerStatCount = select(2, xmlText:gsub("<PlayerStat ", ""))
    local minionStatCount = select(2, xmlText:gsub("<MinionStat ", ""))
    local fullDPSSkillCount = select(2, xmlText:gsub("<FullDPSSkill ", ""))
    return {
        ok = true, path = target, bytes = #xmlText,
        playerStatCount = playerStatCount,
        minionStatCount = minionStatCount,
        fullDPSSkillCount = fullDPSSkillCount,
        outputRevision = bm.outputRevision or 0,
    }
end

-- Keep the Phase-1 name working, routed through the gated path above so no
-- caller can reach the ungated one any more.
function pob_saveBuild(filename)
    local r = pob_saveDBFile(filename)
    return r and r.ok or false
end

-- Save-As support. Legacy filters the typed name through the Lua character
-- class [\/:%*%?"<>|%c] (Build.lua:1362) -- note %c is CONTROL CHARACTERS, not
-- a literal "c" -- and enables the Save button only when io.open(newFileName,
-- "r") returns nil, i.e. it refuses to overwrite (Build.lua:1352-1358).
function pob_sanitizeBuildName(name, subPath)
    -- The backslash MUST be doubled: "\/" is not a valid Lua escape sequence and
    -- fails the whole host bootstrap at load time (silently, as "engine.init
    -- FAILED" with no Lua error surfaced by the capture harness).
    name = tostring(name or ""):gsub('[\\/:%*%?"<>|%c]', "-")
    local base = (main.buildPath or ""):gsub("\\", "/")
    local sub = (subPath or ""):gsub("\\", "/")
    if #sub > 0 and sub:sub(-1) ~= "/" then sub = sub .. "/" end
    local fullPath = base .. sub .. name .. ".xml"
    local exists = false
    if #name > 0 then
        local f = io.open(fullPath, "r")
        if f then exists = true f:close() end
    end
    return {
        name = name,
        valid = name:match("%S") ~= nil,
        exists = exists,
        fullPath = fullPath,
    }
end

function pob_closeBuild()
    local bm = main and main.modes and main.modes.BUILD
    if not bm then return { ok = false, error = "no build" } end
    bm:CloseBuild()
    return { ok = true, mode = main.mode or "LIST" }
end

-- ---------------------------------------------------------------------------
-- Version conversion
--
-- This is the one LIVE HANG in the current shell. Build:Init (Build.lua:104-108)
-- sets self.targetVersion = nil and RETURNS EARLY when a build's targetVersion
-- differs from liveTargetVersion, expecting OpenConversionPopup's SimpleGraphic
-- buttons to drive the recovery. Those controls are inert under QML, so the app
-- lands in a half-initialised BUILD mode that buildMode:OnFrame then refuses to
-- advance (Build.lua:1164-1167) -- with no way out. These two functions are the
-- QML-side replacement for that popup.
-- ---------------------------------------------------------------------------
function pob_getConversionState()
    local bm = main and main.modes and main.modes.BUILD
    if not bm then return { needsConversion = false } end
    local liveDisplay = liveTargetVersion
    if treeVersions and treeVersions[latestTreeVersion] then
        liveDisplay = treeVersions[latestTreeVersion].display or liveTargetVersion
    end
    return {
        needsConversion = (bm.buildName ~= nil and bm.targetVersion == nil),
        buildVersion = bm.dbFileName and "" or "",
        liveVersion = liveTargetVersion or "",
        liveDisplay = liveDisplay or "",
        dbFileName = bm.dbFileName or "",
        buildName = bm.buildName or "",
    }
end

function pob_convertBuild()
    local bm = main and main.modes and main.modes.BUILD
    if not bm then return { ok = false, error = "no build" } end
    if bm.targetVersion ~= nil then
        return { ok = true, converted = false, targetVersion = bm.targetVersion }
    end
    -- Guard the dev autosave: Init returned before setting abortSave, so
    -- Shutdown would otherwise be free to write a half-initialised build over
    -- the user's file (Build.lua:955-969). Legacy has the same hole; we don't.
    bm.abortSave = true
    bm:Shutdown()
    bm:Init(bm.dbFileName, bm.buildName, nil, true)
    if bm.targetVersion == nil then
        return { ok = false, error = "conversion did not take" }
    end
    return { ok = true, converted = true, targetVersion = bm.targetVersion,
             hasSpec = bm.spec ~= nil }
end

-- ---------------------------------------------------------------------------
-- Phase 3 selftests. Every one restores what it touches -- the suite is a
-- single ordered run over one shared engine, and later checks assume earlier
-- ones left state alone.
-- ---------------------------------------------------------------------------

function pob_selftestUnsaved()
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end

    local savedTreeFlag = bm.treeTab.modFlag
    local savedBmFlag = bm.modFlag
    local savedUnsavedField = bm.unsaved

    bm:ResetModFlags()
    local clean = pob_getUnsaved()

    -- Prove the OLD read was wrong: park a deliberately false value in the
    -- OnFrame-owned field and show a real dirty flag does not move it.
    bm.unsaved = false
    bm.treeTab.modFlag = true
    local dirty = pob_getUnsaved()
    local staleFieldWouldHaveLied = (dirty.unsaved == true)

    bm.treeTab.modFlag = savedTreeFlag
    bm.modFlag = savedBmFlag
    bm.unsaved = savedUnsavedField

    return {
        ok = (clean.unsaved == false) and (dirty.unsaved == true)
             and (dirty.flags.tree == true) and staleFieldWouldHaveLied,
        clean = clean.unsaved,
        dirty = dirty.unsaved,
        flagCount = 10,
    }
end

function pob_selftestShellState()
    local d = pob_getShellState()
    if not d then return { ok = false, error = "no shell state" } end
    local cl = pob_getClassList()
    if not cl then return { ok = false, error = "no class list" } end

    -- The points string is the legacy format "%s%3d / %3d   %s%d / %d"; assert
    -- it actually carries the two counts rather than an empty/garbage value.
    local formatOk = d.points.str ~= nil and d.points.str:find("/") ~= nil
    local classOk = cl.curClassId == d.classId
    local sortedOk = true
    for i = 2, #cl.classes do
        if cl.classes[i - 1].label > cl.classes[i].label then sortedOk = false break end
    end

    return {
        ok = formatOk and classOk and sortedOk and d.level >= 1 and d.level <= 100,
        level = d.level,
        classCount = #cl.classes,
        secondaryCount = #cl.secondaryAscendancies,
        pointsStr = d.points.str,
        outputRevision = d.outputRevision,
    }
end

function pob_selftestShellClass()
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end

    local origClassId = bm.spec.curClassId
    local origAscend = bm.spec.curAscendClassId
    local cl = pob_getClassList()
    if not cl then return { ok = false, error = "no class list" } end

    -- Pick some class that is not the current one.
    local otherId = nil
    for _, c in ipairs(cl.classes) do
        if c.classId ~= origClassId then otherId = c.classId break end
    end
    if not otherId then return { ok = false, error = "only one class" } end

    -- Allocate a node so the tree is non-empty and the confirm path is live.
    local candidateId = nil
    for id, node in pairs(bm.spec.nodes) do
        if node.type == "Normal" and node.path and not node.alloc and not node.ascendancyName then
            for _, linked in ipairs(node.linked) do
                if linked.alloc then candidateId = id break end
            end
        end
        if candidateId then break end
    end
    local allocated = false
    if candidateId then
        bm.spec:AllocNode(bm.spec.nodes[candidateId], nil)
        allocated = bm.spec.nodes[candidateId].alloc and true or false
    end

    local before = bm.spec:CountAllocNodes()
    local checkResult = pob_setClass(otherId, "check")
    local unchanged = (bm.spec.curClassId == origClassId)
    -- needsConfirm is only expected when the tree actually has allocations that
    -- the target class start is not already connected to.
    local confirmExpected = allocated and not bm.spec:IsClassConnected(otherId)

    local forceResult = pob_setClass(otherId, "force")
    local switched = (bm.spec.curClassId == otherId)
    local after = bm.spec:CountAllocNodes()

    -- Level clamp + auto mode, on the way back.
    local origLevel = bm.characterLevel
    local origAuto = bm.characterLevelAutoMode
    local clamped = pob_setCharacterLevel(150)
    local clampOk = (clamped.level == 100)

    -- Restore everything.
    pob_setCharacterLevel(origLevel)
    bm.characterLevelAutoMode = origAuto
    pob_setClass(origClassId, "force")
    if allocated and bm.spec.nodes[candidateId] and bm.spec.nodes[candidateId].alloc then
        bm.spec:DeallocNode(bm.spec.nodes[candidateId])
    end
    bm.buildFlag = true
    pob_recalculate()

    return {
        ok = (checkResult.ok and unchanged and switched and clampOk
              and (not confirmExpected or checkResult.needsConfirm == true)),
        needsConfirm = checkResult.needsConfirm or false,
        confirmExpected = confirmExpected,
        switched = switched,
        allocBefore = before,
        allocAfter = after,
        clampOk = clampOk,
        restoredClassId = bm.spec.curClassId,
    }
end

function pob_selftestSaveDBFile()
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end

    local origDbFileName = bm.dbFileName
    local origBuildName = bm.buildName
    local origSubPath = bm.dbFileSubPath

    -- NEVER name a test fixture "~~temp~~": Build:Init unconditionally
    -- os.remove()s that filename (Build.lua:424-431).
    local target = (main.buildPath or "") .. "~~phase3-savegate~~.xml"
    local r = pob_saveDBFile(target)
    if not r or not r.ok then
        bm.dbFileName, bm.buildName, bm.dbFileSubPath = origDbFileName, origBuildName, origSubPath
        return { ok = false, error = "save failed", detail = r }
    end

    local f = io.open(target, "r")
    local contents = f and f:read("*a") or ""
    if f then f:close() end
    os.remove(target)

    local hasPlayerStat = contents:find("<PlayerStat ", 1, true) ~= nil
    local hasBuildAttribs = contents:find("level=", 1, true) ~= nil
                            and contents:find("className=", 1, true) ~= nil
    local cleanAfterSave = (pob_getUnsaved().unsaved == false)

    bm.dbFileName, bm.buildName, bm.dbFileSubPath = origDbFileName, origBuildName, origSubPath

    return {
        ok = hasPlayerStat and hasBuildAttribs and cleanAfterSave and r.bytes > 0,
        bytes = r.bytes,
        playerStatCount = r.playerStatCount,
        fullDPSSkillCount = r.fullDPSSkillCount,
        hasPlayerStat = hasPlayerStat,
        cleanAfterSave = cleanAfterSave,
    }
end

-- Part 3.3: prove the FULL savers registry (Config/Notes/Party/Tree/TreeView/
-- Items/Skills/Calcs/Import + legacy Spec) round-trips REAL per-tab state
-- through SaveDB -> disk-shaped XML text -> LoadDB, not just the buildName
-- string pob_selftestSaveLoad already covers. Build.lua:651-678 (unmodified
-- legacy code) defers Tree/Spec loading until every other section has loaded,
-- then sweeps PostLoad -- this is the load-bearing evidence that sequence
-- actually reconstructs every tab correctly under the Qt host, not just that
-- it doesn't crash. Builds up one real mutation per major saver (a tree
-- alloc, an item, an active-skill socket group, a config option), verifies
-- each survives the round trip, then returns to a fresh Unnamed build so a
-- check appended after this one in the suite doesn't inherit a probe build.
--
-- characterLevel is pinned to a fixed value with auto-mode OFF for the
-- round trip: in auto mode, `buildMode:OnFrame` -> `ProcessControlsInput`
-- (Build.lua:1205) still walks the legacy (Qt-invisible) Control tree every
-- frame, and the point-display control's width function calls
-- EstimatePlayerProgress() (Build.lua:198), which MUTATES characterLevel to
-- match current point requirements as a side effect of what looks like a
-- pure layout query. That's legitimate legacy behaviour (confirmed by
-- instrumenting a real run: 128 calls during one reload's Init/OnFrame), but
-- it means auto-mode level is a derived value that legitimately drifts
-- between "before" and "after" here -- pinning to manual mode makes this a
-- fair test of round-trip fidelity instead of colliding with that feature.
function pob_selftestSaveLoadRoundTrip()
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end

    -- Tree: pick a Normal node directly linked to the trunk, same fixture
    -- pattern as pob_selftestTreeInteract, so allocating it adds exactly one
    -- node (not a whole path) -- a precise, checkable delta.
    local targetId = nil
    for id, node in pairs(bm.spec.nodes) do
        if node.type == "Normal" and node.path and not node.alloc and not node.ascendancyName then
            local linkedToAlloc = false
            for _, ln in ipairs(node.linked) do
                if ln.alloc then linkedToAlloc = true break end
            end
            if linkedToAlloc then targetId = id break end
        end
    end
    if not targetId then return { ok = false, error = "no allocatable node found" } end
    local a = pob_allocNode(targetId)
    if not a or not a.ok then return { ok = false, error = "alloc failed" } end

    local itemId = pob_addItemFromRaw("Rarity: Rare\nRound Trip Ring\nGold Ring\nQuality: 0\nSockets: R-B\n")
    if not itemId then
        pob_deallocNode(targetId)
        return { ok = false, error = "item add failed" }
    end

    -- Active-skill socket group, set as THE main skill and flagged for Full
    -- DPS (SkillsTab.lua:208's includeInFullDPS) so calcsTab.mainOutput.
    -- SkillDPS has something to denormalize into <FullDPSSkill> on save.
    local groupId = pob_addSocketGroupWithGem("Round Trip Group", "Fireball")
    if not groupId then
        pob_deleteItem(itemId)
        pob_deallocNode(targetId)
        return { ok = false, error = "skill add failed" }
    end
    bm.skillsTab.socketGroupList[groupId].includeInFullDPS = true
    bm.mainSocketGroup = groupId
    bm.buildFlag = true
    pob_recalculate()

    bm.characterLevelAutoMode = false
    bm.characterLevel = 90

    local configTarget = nil
    for _, o in ipairs(pob_getConfigOptions() or { }) do
        if o.type == "boolean" then configTarget = o break end
    end
    if configTarget then
        pob_setConfigOption(configTarget.name, not configTarget.value)
    end

    local before = {
        allocUsed = select(1, bm.spec:CountAllocNodes()),
        itemCount = #bm.itemsTab.itemOrderList,
        groupCount = #bm.skillsTab.socketGroupList,
        className = bm.spec.curClassName,
        level = bm.characterLevel,
    }
    if configTarget then
        for _, o in ipairs(pob_getConfigOptions() or { }) do
            if o.name == configTarget.name then before.configVal = o.value break end
        end
    end

    local xmlText = bm:SaveDB(nil)
    if not xmlText then
        return { ok = false, error = "SaveDB returned nil" }
    end
    local hasPlayerStat = xmlText:find("<PlayerStat ", 1, true) ~= nil
    local hasFullDPSSkill = xmlText:find("<FullDPSSkill ", 1, true) ~= nil
    local hasTimelessData = xmlText:find("<TimelessData", 1, true) ~= nil

    local loadOk = pcall(function() pob_loadBuildXML(xmlText, "Round Trip Probe") end)
    if not loadOk then
        return { ok = false, error = "load failed", before = before, xmlLen = #xmlText }
    end

    local bm2 = pob_buildMode()
    local after = nil
    if bm2 then
        after = {
            allocUsed = select(1, bm2.spec:CountAllocNodes()),
            nodeAlloc = bm2.spec.nodes[targetId] and bm2.spec.nodes[targetId].alloc,
            itemCount = #bm2.itemsTab.itemOrderList,
            groupCount = #bm2.skillsTab.socketGroupList,
            className = bm2.spec.curClassName,
            level = bm2.characterLevel,
        }
        if configTarget then
            for _, o in ipairs(pob_getConfigOptions() or { }) do
                if o.name == configTarget.name then after.configVal = o.value break end
            end
        end
    end

    local sectionsOk = after ~= nil
        and after.allocUsed == before.allocUsed
        and after.nodeAlloc == true
        and after.itemCount == before.itemCount
        and after.groupCount == before.groupCount
        and after.className == before.className
        and after.level == before.level
        and (not configTarget or after.configVal == before.configVal)

    -- Clean slate: nothing after this check in the suite should see a
    -- round-tripped probe build (same discipline as pob_selftestReopenLastBuild).
    main:SetMode("BUILD", false, "Unnamed build")
    runCallback("OnFrame")

    return {
        ok = not not (sectionsOk and hasPlayerStat and hasFullDPSSkill and hasTimelessData),
        sectionsOk = sectionsOk,
        hasPlayerStat = hasPlayerStat,
        hasFullDPSSkill = hasFullDPSSkill,
        hasTimelessData = hasTimelessData,
        before = before,
        after = after,
        xmlLen = #xmlText,
    }
end

function pob_selftestSideBar()
    local origMain = main.sideBarCollapsed
    local bm = main and main.modes and main.modes.BUILD
    local origBm = bm and bm.sideBarCollapsed

    pob_setSideBarCollapsed(not origMain)
    local bothFlipped = (main.sideBarCollapsed == (not origMain))
                        and (not bm or bm.sideBarCollapsed == (not origMain))

    pob_setSideBarCollapsed(origMain)
    local restored = (main.sideBarCollapsed == origMain)
    if bm then bm.sideBarCollapsed = origBm end

    return { ok = bothFlipped and restored, bothFlipped = bothFlipped, restored = restored }
end

-- ============================================================================
-- PHASE 3 Part 3.2 -- the main-skill selector stack.
--
-- Data port of buildMode:RefreshSkillSelectControls (Build.lua:1511-1609). That
-- function mutated eight SimpleGraphic DropDown/Edit controls in place and was
-- re-run EVERY FRAME from OnFrame (Build.lua:1237); with no frame loop it is
-- dead code, so this returns the same decisions as a plain table instead.
--
-- TWO INDEPENDENT SELECTIONS EXIST. Legacy parameterises the whole function on
-- a `suffix`: "" for the side bar and "Calcs" for the Calcs tab, reading
-- `mainActiveSkill`/`skillPart`/`skillStageCount`/`skillMineCount`/`skillMinion`/
-- `skillMinionItemSet`/`skillMinionSkill` with that suffix appended. They must
-- never be collapsed into one -- the Calcs tab deliberately lets you inspect a
-- different skill than the side bar is displaying. Every function here takes
-- the same suffix so Phase 8 can reuse them unchanged.
--
-- PERFORMANCE, load-bearing: this must NEVER call pob_getActiveSkills(), which
-- runs one full BuildOutput PER displayed skill (61-470ms, STATUS.md). Legacy
-- reads skillsTab.socketGroupList[i].displayLabel and .displaySkillList
-- directly, and so do we. Note displayLabel is NOT the same field as .label --
-- pob_getSocketGroups() returns .label, so reusing it here would silently show
-- the wrong text on every group.
--
-- displayLabel / displaySkillList are ENGINE WRITE-BACKS populated during a calc
-- pass, so a recalc has to happen before they can be read.
-- ============================================================================

local function pob_mainSkillSrcInstance(bm, suffix)
    local sg = bm.skillsTab.socketGroupList[bm.mainSocketGroup]
    if not sg then return nil end
    local list = sg["displaySkillList" .. suffix]
    if not list then return nil end
    local active = list[sg["mainActiveSkill" .. suffix] or 1]
    if not active or not active.activeEffect then return nil end
    return active.activeEffect.srcInstance, active, sg
end

function pob_getMainSkillControls(suffix)
    suffix = suffix or ""
    local bm = pob_buildMode()
    if not bm or not bm.skillsTab then return nil end
    pob_recalculate()

    local result = {
        noSkills = false,
        mainSocketGroup = bm.mainSocketGroup or 1,
        socketGroups = { },
        skills = { },
        mainActiveSkill = 1,
        skillsEnabled = false,
        parts = { }, partIndex = 1, partsShown = false,
        stages = { shown = false, value = "" },
        mines  = { shown = false, value = "" },
        minion = { shown = false, enabled = false, isItemSet = false,
                   libraryShown = false, selected = nil, list = { } },
        minionSkill = { shown = false, enabled = false, index = 1, list = { } },
        outputRevision = bm.outputRevision or 0,
    }

    -- pairs(), matching legacy (Build.lua:1514) -- socketGroupList is a dense
    -- array so ipairs order is what actually comes out either way.
    for i, socketGroup in pairs(bm.skillsTab.socketGroupList) do
        result.socketGroups[#result.socketGroups + 1] =
            { index = i, label = socketGroup.displayLabel or socketGroup.label or "" }
    end
    table.sort(result.socketGroups, function(a, b) return a.index < b.index end)

    if #result.socketGroups == 0 then
        result.noSkills = true
        result.socketGroups[1] = { index = 1, label = "<No skills added yet>" }
        return result
    end

    local mainSocketGroup = bm.skillsTab.socketGroupList[bm.mainSocketGroup]
    if not mainSocketGroup then return result end
    local displaySkillList = mainSocketGroup["displaySkillList" .. suffix] or { }
    local mainActiveSkill = mainSocketGroup["mainActiveSkill" .. suffix] or 1
    result.mainActiveSkill = mainActiveSkill
    result.skillsEnabled = #displaySkillList > 1

    for i, activeSkill in ipairs(displaySkillList) do
        -- An item-granted skill shows "From <item>" in the item's rarity colour
        -- rather than the gem name (Build.lua:1535-1537).
        local explodeSource = activeSkill.activeEffect.srcInstance.explodeSource
        local explodeSourceName = explodeSource and (explodeSource.name or explodeSource.dn)
        local colourCoded = explodeSourceName
            and ("From " .. (colorCodes[explodeSource.rarity or "NORMAL"] or "") .. explodeSourceName)
        result.skills[#result.skills + 1] = {
            index = i,
            label = colourCoded or activeSkill.activeEffect.grantedEffect.name,
        }
    end

    local activeSkill = displaySkillList[mainActiveSkill]
    local activeEffect = activeSkill and activeSkill.activeEffect
    if not displaySkillList[1] or not activeEffect then return result end

    local grantedEffect = activeEffect.grantedEffect
    local srcInstance = activeEffect.srcInstance

    if grantedEffect.parts and #grantedEffect.parts > 1 then
        result.partsShown = true
        for i, part in ipairs(grantedEffect.parts) do
            result.parts[#result.parts + 1] = { index = i, label = part.name }
        end
        result.partIndex = srcInstance["skillPart" .. suffix] or 1
        local part = grantedEffect.parts[result.partIndex]
        if part and part.stages then
            result.stages.shown = true
            result.stages.value = tostring(srcInstance["skillStageCount" .. suffix]
                or activeSkill.skillData.stagesMax or part.stagesMin or 1)
        end
    end

    if activeSkill.skillFlags.mine then
        result.mines.shown = true
        result.mines.value = tostring(srcInstance["skillMineCount" .. suffix] or "")
    end

    if activeSkill.skillFlags.multiStage
       and not (grantedEffect.parts and #grantedEffect.parts > 1) then
        result.stages.shown = true
        result.stages.value = tostring(srcInstance["skillStageCount" .. suffix]
            or activeSkill.skillData.stagesMax or activeSkill.skillData.stagesMin or 1)
    end

    if not activeSkill.skillFlags.disable
       and (grantedEffect.minionList or activeSkill.minionList[1]) then
        if grantedEffect.minionHasItemSet then
            -- Animate Guardian: the "minion" dropdown lists ITEM SETS, and is
            -- also a drag-equip target (Build.lua:1573-1581).
            result.minion.isItemSet = true
            for _, itemSetId in ipairs(bm.itemsTab.itemSetOrderList) do
                local itemSet = bm.itemsTab.itemSets[itemSetId]
                result.minion.list[#result.minion.list + 1] = {
                    label = itemSet.title or "Default Item Set",
                    itemSetId = itemSetId,
                }
            end
            result.minion.selected = srcInstance["skillMinionItemSet" .. suffix] or 1
        else
            result.minion.libraryShown =
                (grantedEffect.minionList and not grantedEffect.minionList[1]) and true or false
            for _, minionId in ipairs(activeSkill.minionList) do
                result.minion.list[#result.minion.list + 1] = {
                    label = bm.data.minions[minionId].name,
                    minionId = minionId,
                }
            end
            local sel = srcInstance["skillMinion" .. suffix]
            if sel == nil and result.minion.list[1] then sel = result.minion.list[1].minionId end
            result.minion.selected = sel
        end
        result.minion.enabled = #result.minion.list > 1
        result.minion.shown = true

        if activeSkill.minion then
            for _, minionSkill in ipairs(activeSkill.minion.activeSkillList) do
                result.minionSkill.list[#result.minionSkill.list + 1] =
                    minionSkill.activeEffect.grantedEffect.name
            end
            result.minionSkill.index = srcInstance["skillMinionSkill" .. suffix] or 1
            result.minionSkill.shown = true
            result.minionSkill.enabled = #result.minionSkill.list > 1
        else
            -- Legacy appends this as a bare string into the MINION list
            -- (Build.lua:1605), not the minion-skill list.
            result.minion.list[#result.minion.list + 1] = { label = "<No spectres in build>" }
        end
    end

    return result
end

-- --- setters (Build.lua:488-575) -------------------------------------------
-- Each mirrors its legacy callback exactly: mutate, set modFlag + buildFlag,
-- then go through the canonical recalc (invariant #4).

local function pob_mainSkillCommit(bm)
    bm.modFlag = true
    bm.buildFlag = true
    pob_recalculate()
    return { ok = true, outputRevision = bm.outputRevision or 0 }
end

function pob_setMainSocketGroup(index)
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end
    bm.mainSocketGroup = index
    return pob_mainSkillCommit(bm)
end

function pob_setMainActiveSkill(index, suffix)
    suffix = suffix or ""
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end
    local sg = bm.skillsTab.socketGroupList[bm.mainSocketGroup]
    if not sg then return { ok = false, error = "no socket group" } end
    sg["mainActiveSkill" .. suffix] = index
    return pob_mainSkillCommit(bm)
end

function pob_setMainSkillPart(index, suffix)
    suffix = suffix or ""
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end
    local srcInstance = pob_mainSkillSrcInstance(bm, suffix)
    if not srcInstance then return { ok = false, error = "no active skill" } end
    srcInstance["skillPart" .. suffix] = index
    return pob_mainSkillCommit(bm)
end

function pob_setSkillStageCount(count, suffix)
    suffix = suffix or ""
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end
    local srcInstance = pob_mainSkillSrcInstance(bm, suffix)
    if not srcInstance then return { ok = false, error = "no active skill" } end
    srcInstance["skillStageCount" .. suffix] = tonumber(count)
    return pob_mainSkillCommit(bm)
end

function pob_setSkillMineCount(count, suffix)
    suffix = suffix or ""
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end
    local srcInstance = pob_mainSkillSrcInstance(bm, suffix)
    if not srcInstance then return { ok = false, error = "no active skill" } end
    srcInstance["skillMineCount" .. suffix] = tonumber(count)
    return pob_mainSkillCommit(bm)
end

-- value: { minionId = "Metadata/..." } or { itemSetId = 2 }.
function pob_setSkillMinion(value, suffix)
    suffix = suffix or ""
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end
    local srcInstance = pob_mainSkillSrcInstance(bm, suffix)
    if not srcInstance then return { ok = false, error = "no active skill" } end
    if value and value.itemSetId then
        srcInstance["skillMinionItemSet" .. suffix] = value.itemSetId
    elseif value and value.minionId then
        srcInstance["skillMinion" .. suffix] = value.minionId
    else
        return { ok = false, error = "value needs minionId or itemSetId" }
    end
    return pob_mainSkillCommit(bm)
end

function pob_setSkillMinionSkill(index, suffix)
    suffix = suffix or ""
    local bm = pob_buildMode()
    if not bm then return { ok = false, error = "no build" } end
    local srcInstance = pob_mainSkillSrcInstance(bm, suffix)
    if not srcInstance then return { ok = false, error = "no active skill" } end
    srcInstance["skillMinionSkill" .. suffix] = index
    return pob_mainSkillCommit(bm)
end

-- Socket-group tooltip. Wraps skillsTab:AddSocketGroupTooltip with the same
-- line-collector shim technique pob_getAboutContent already uses, so the real
-- legacy tooltip body is reused rather than re-derived.
function pob_getSocketGroupTooltip(index)
    local bm = pob_buildMode()
    if not bm or not bm.skillsTab then return { } end
    local socketGroup = bm.skillsTab.socketGroupList[index]
    if not socketGroup then return { } end
    local lines = { }
    local shim = {
        lines = lines,
        Clear = function(self) for i = #lines, 1, -1 do lines[i] = nil end end,
        CheckForUpdate = function() return true end,
        AddLine = function(self, size, text) lines[#lines + 1] = tostring(text or "") end,
        AddSeparator = function(self) lines[#lines + 1] = "" end,
        SetRecipe = function() end,
    }
    local ok = pcall(function() bm.skillsTab:AddSocketGroupTooltip(shim, socketGroup) end)
    if not ok then return { } end
    return lines
end

-- Selftest: the whole point is to catch the displayLabel-vs-label trap and
-- prove a part change actually reaches srcInstance and bumps the revision.
function pob_selftestMainSkill()
    local bm = pob_buildMode()
    if not bm or not bm.skillsTab then return { ok = false, error = "no build" } end

    -- An earlier check in the suite reopens a probe build, so by the time we
    -- run the socket-group list is usually EMPTY -- which would exercise only
    -- the <No skills added yet> branch and never touch the displayLabel
    -- assertion this check exists for. Add a real group when there is none, and
    -- remove it again afterwards so the next run starts from the same state.
    local addedId = nil
    if #bm.skillsTab.socketGroupList == 0 then
        addedId = pob_addSocketGroupWithGem("Selftest Main Skill", "Fireball")
    end

    local d = pob_getMainSkillControls("")
    if not d then
        if addedId then table.remove(bm.skillsTab.socketGroupList, addedId) end
        return { ok = false, error = "no payload" }
    end

    -- Every reported group label must equal the engine's displayLabel, not the
    -- plain .label pob_getSocketGroups returns.
    local labelsMatch = true
    if not d.noSkills then
        for _, g in ipairs(d.socketGroups) do
            local sg = bm.skillsTab.socketGroupList[g.index]
            local want = sg and (sg.displayLabel or sg.label or "")
            if want ~= g.label then labelsMatch = false break end
        end
    end

    local inRange = d.noSkills
        or (d.mainSocketGroup >= 1 and d.mainSocketGroup <= #bm.skillsTab.socketGroupList)

    -- The two selections must stay independent: writing the Calcs suffix must
    -- not disturb the side bar's mainActiveSkill.
    local independent = true
    local sg = bm.skillsTab.socketGroupList[bm.mainSocketGroup]
    if sg then
        local savedPlain = sg.mainActiveSkill
        local savedCalcs = sg.mainActiveSkillCalcs
        sg.mainActiveSkillCalcs = (savedPlain or 1) + 1
        independent = (sg.mainActiveSkill == savedPlain)
        sg.mainActiveSkill = savedPlain
        sg.mainActiveSkillCalcs = savedCalcs
    end

    -- Prove a setter actually reaches the engine: flip the active skill and
    -- confirm the payload follows, then put it back.
    local setterOk = true
    if not d.noSkills and #d.skills > 0 then
        local orig = d.mainActiveSkill
        pob_setMainActiveSkill(1, "")
        local after = pob_getMainSkillControls("")
        setterOk = after and after.mainActiveSkill == 1
        pob_setMainActiveSkill(orig, "")
    end

    local result = {
        ok = labelsMatch and inRange and independent and setterOk,
        noSkills = d.noSkills,
        groupCount = #d.socketGroups,
        skillCount = #d.skills,
        labelsMatch = labelsMatch,
        independent = independent,
        setterOk = setterOk,
        partsShown = d.partsShown,
        minionShown = d.minion.shown,
        outputRevision = d.outputRevision,
    }

    if addedId then
        table.remove(bm.skillsTab.socketGroupList, addedId)
        bm.mainSocketGroup = 1
        bm.buildFlag = true
        pob_recalculate()
    end
    return result
end
