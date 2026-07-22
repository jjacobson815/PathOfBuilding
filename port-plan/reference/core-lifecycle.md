# Reference: Core / Lifecycle / Persistence / Networking

Everything that is NOT a tab, NOT the calc engine, NOT a UI control. Paths are
relative to `src/`.

## Entry & crash shell (`Launch.lua`, 409 lines)

`SetMainObject(launch)`; sets JIT opts + GC pause. Host invokes callbacks (mirror
of `HeadlessWrapper.lua`): `OnInit` (reads manifest for version; **devMode** =
manifest without branch+platform; `installed.cfg` → installedMode; loads
`Modules/Main` under PCall), `CanExit`, `OnExit` (`main:Shutdown`), `OnFrame`
(runs `main:OnFrame` under PCall; **crash recovery**: if first-build calc crashes,
force LIST mode), `OnKeyDown/Up/Char` (global hotkeys: F5 restart, Ctrl+U update,
Ctrl+PrintScreen screenshot), sub-script callbacks `OnSubCall/OnSubError/OnSubFinished`.

**`launch:DownloadPage(url, callback, params)`** — THE network primitive. Builds an
`lcurl.safe` script string and runs it via `LaunchSubScript`; honors
`connectionProtocol` (IPv4/6), `proxyURL`, `noSSL`; User-Agent "Path of Building/
<ver>"; callback gets `{header, body}, errMsg`. **`launch:CheckForUpdate`** and
**`launch:ApplyUpdate`** drive the updater. `ShowPrompt`/`ShowErrMsg` — modal prompt
state machine (Enter/Escape dismiss, Ctrl+C copy, F5 restart).

## Application object (`Modules/Main.lua`)

`main = new("ControlHost")`. **CLI** (`arg[1]` = import URI → `pob://` protocol
handler startup path). **Init**: mode registry, popup stack, userPath resolution
(`GetUserPath()` + "/Path of Building/"), ~25 option defaults, `LoadTree(latest)`,
**item DB loaded in a per-frame coroutine** (`onFrameFuncs.LoadItems`, `pairsYield`
yields at >20 ms) — startup is incremental across frames; **the Qt frame loop must
pump `OnFrame` during startup or `uniqueDB.loading` stays true forever**.

**userPath** = `GetUserPath().."/Path of Building/"` (`Main.lua:86-97`) — where every
existing user's `Builds/` tree and `Settings.xml` live (Documents/Path of Building
on Windows). **The Qt host points `GetUserPath` at a temp dir** (`LuaEngine.cpp:39`
`QDir::tempPath()+"/pob-qt"`) → existing users see an EMPTY library + reset
settings + OS-wipeable saves. Fix (Phase 0): return
`QStandardPaths::writableLocation(DocumentsLocation)` — the Documents **parent**
(the engine appends the suffix; returning `Documents/Path of Building` double-
appends). Guard: a stray remote-style `manifest.xml` on the process CWD flips
`devMode` and routes userPath into the *source tree* — pin installed mode. **Policy
decision (SHARE vs SEPARATE):** because both apps run the identical Lua engine,
sharing `Documents/Path of Building` gives lossless round-trip + zero migration, but
requires engine-version lockstep and exposes concurrent-run clobbering; SEPARATE
needs an explicit first-run copy-migration. Recommend SHARE for v1. (Open decision
in STATUS.)

**Settings persistence** (`LoadSettings`/`SaveSettings`/`LoadSharedItems`): parses
`<userPath>Settings.xml` — `<Mode>` (mode + Arg children, replayed via SetMode),
`<Accounts>` (lastAccount/Realm/League + OAuth token/refresh/expiry + per-account
sessionIDs — **plaintext**), `<Misc>` (~29 attrs; attribute-presence based, no schema
version, so a pre-existing legacy file loads unchanged — but `SaveSettings` rewrites
`<Misc>` from a fixed key set, **dropping any key this engine snapshot doesn't
know** → engine-version drift silently strips co-installed newer keys),
`<SharedItems>`. **Cloud-file read failure latches `errorReadingSettings`
permanently** (`Main.lua:482-494`) → early-returns from all load/save for the rest
of the session; the temp-dir bug currently *masks* this, but once userPath points at
real (OneDrive) Documents, one transient dehydrated-file read at startup silently
disables settings persistence, with a popup that no-ops in QML. Make the latch
non-fatal (Phase 1). **`SaveSettings` runs from `main:Shutdown` — which the Qt host
never calls today (`CanExit`/`OnExit` unwired) → settings never save.** Fix in Phase 0.

**Mode switching**: `SetMode` records the target; the swap happens at top of
`OnFrame` (old `Shutdown` → new `Init`). Reentrant: `Build:Init` can call
`CloseBuild → SetMode` mid-Init. Popups API (`OpenPopup/Message/Confirm/NewFolder/
Path/CloudError/Options/Update/About`). File-management helpers (`MoveFolder`/
`CopyFolder` via `NewFileSearch`). `SetManifestBranch` (beta opt-in).

## Build lifecycle & save format (`Modules/Build.lua`)

`Init(dbFileName, buildName, buildXML, convertBuild, importLink)`: load from XML/
file; version gate → conversion popup; `abortSave` guard (crash safety);
instantiates all tabs + **savers map**; section load loop (Tree deferred, then
PostLoad); first calc `outputRevision=1; calcsTab:BuildOutput()`. `CanExit` →
`OpenSavePopup` (Save/Don't-Save/Cancel for LIST/EXIT/UPDATE). `Shutdown` → devMode
autosave to `~~temp~~.xml`. `GetArgs` → `(dbFileName, buildName)` persisted in
Settings (reopens last build).

**Build XML** (`<PathOfBuilding>` root): `LoadDB`/`SaveDB` — `<Build>` element
first (targetVersion, viewMode, level, class ids, bandit, pantheon, mainSocketGroup,
`<Spectre>`, `<TimelessData>`), then one node per savers entry. `Save` also writes
**denormalized `<PlayerStat>/<MinionStat>/<FullDPSSkill>`** from `calcsTab.mainOutput`
for third-party sites (pobb.in, Maxroll parse these — **saving before a full calc
pass silently breaks ecosystem interop**).

**Share code**: `base64(Deflate(SaveDB)):gsub("+","-"):gsub("/","_")` (URL-safe
base64 + zlib deflate over the build XML). Decode is the inverse. `Inflate`/
`Deflate` are the host zlib bridge (already `pob.inflate`/`pob.deflate`) — verify
wire-format compatibility against real codes from all 7 sites.

## Build List mode (`Modules/BuildList.lua` + `BuildListHelpers.lua`)

`ScanFolder` uses `NewFileSearch(buildPath..subPath.."*.xml")` + dir scan; extracts
`(<Build.->)` header substring for cheap metadata (level/class); `GetFileModifiedTime`
for sort. Ctrl+V paste of copied/cut build/folder; Ctrl+N new; MOUSE4/5 path undo/
redo. Public-builds panel hard-disabled (`if false`).

## Utility modules

- `GameVersions.lua` — pure data (39 tree versions, latest = 3_28). Ports verbatim.
- `Common.lua` — class system, coroutine full-framerate patch + `pairsYield`,
  UTF16↔UTF8, `formatNumSep`, murmurHash2, `HashStats` (trade), table utils,
  `ImportBuild` (unwraps youtube/google redirects), `GetVirtualScreenSize`.
- `BuildSiteTools.lua` — `websiteList` (7 sites: Maxroll, pobb.in, PoeNinja,
  Pastebin, PastebinP, Rentry, poedb.tw); `UploadBuild`/`DownloadBuild`;
  `ParseImportLinkFromURI` (`pob://<siteId>/<code>`).
- `ToastNotification.lua` — queue with show/hide animation; maps to a QML toast
  behind the same `Add/Update/Remove/Clear` API.

## Sub-script inventory (all dead until Phase 10)

`LaunchSubScript(scriptText, funcListCSV, subListCSV, ...)` — isolated worker Lua
state; funcList = sync blocking proxies; subList = async → `OnSubCall`. 6 sites:
`DownloadPage`, update check, **OAuth redirect HTTP server** (`LaunchServer.lua`
run as a subscript — LuaSocket TCP on localhost:49082-84, returns `(code,errMsg,
state,port)`), poeurl resolve, build upload, PoB Archives. Qt options: (a) real
subscript worker-state machine, or (b) shim `launch:DownloadPage` onto async
`pob.http` and reimplement the OAuth server as a `QTcpServer` (leaves the other
raw-LaunchSubScript sites needing per-site shims). See [[host-api-contract]].

## Auto-update system (replace, don't port — Phase 14)

`UpdateCheck.lua` (runs in a subscript; sha1-diffs local vs remote `manifest.xml`,
downloads changed files, supports zip bundles via `lzip`) + `UpdateApply.lua` +
`LaunchInstall.lua` + `manifest.xml` (built by `update_manifest.py` from
`manifest.cfg`) + `Update.exe` + `SpawnProcess`/`Restart`. **Windows/SimpleGraphic-
specific.** Recommend replacing wholesale with an installer-native updater, but
keep `launch.updateAvailable`-style state inert so Main.lua UI (buttons, toasts,
`OpenUpdatePopup` changelog) degrades cleanly. `first.run`/`installed.cfg`/
`manifest.xml` markers also gate devMode and userPath selection — decide their
replacement.

## Risks (see also STATUS open decisions)

- Sub-script is a *semantic contract* (arbitrary Lua source with selective host-
  function granting), used at 6 sites incl. files whose text is read+executed;
  a non-general implementation forces engine-adjacent edits.
- Settings.xml stores OAuth tokens + POESESSID in plaintext — a port is the
  chance/obligation to move to OS keychain (changes LoadSettings/SaveSettings).
- Immediate-mode UI tendrils in "core" (Launch:DrawPopup, Main bottom bar, toasts,
  Build top/side bars draw directly + query `DrawStringWidth`) — these become QML.
- Update-removal has UI tendrils (`updateAvailable`/`updateProgress` drive buttons/
  toasts and the `CanExit("UPDATE")` path).
