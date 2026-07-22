# Reference: SimpleGraphic Host-API Contract & Qt Bridge Status

The complete set of engine-provided globals the legacy Lua calls, and each one's
status in the Qt host. Source of truth: `PathOfBuilding-legacy/src/HeadlessWrapper.lua`
(stubs every host global) verified by grep across `src/`. This is **the port
contract** for the host seam. Line numbers are legacy-checkout-relative; trust
symbol names over lines.

Legend: **Bridged** = works. **Stubbed** = intentional no-op (rendering/input,
QML replaces it). **Broken** = bridged but wrong. **Missing** = not present, will
crash if hit.

## Boot / module protocol — all Bridged

- `SetMainObject(obj)` — registers the callback target (`Launch.lua:16`).
- `SetCallback(name,func)` / `GetCallback(name)` — dispatch override table.
- `LoadModule(file, ...)` (133 sites) / `PLoadModule` (8) / `PCall` (39) —
  reimplemented in `pob_host.lua` with `_SRC_DIR` prefix. The engine's module system.
- `arg` (CLI table) — **Stubbed** `{}`; open-on-launch build/URL import dropped
  (`Main.lua:41,46,68-79` reads `--no-jit`, `--no-ssl`, `arg[1]` as file/URL).

## Host→Lua callbacks — partially wired

Defined in `Launch.lua`. `OnInit`/`OnFrame` are **Bridged** (pumped from C++).
`OnKeyDown/OnKeyUp/OnChar/CanExit/OnExit` and the sub-script trio
`OnSubCall/OnSubError/OnSubFinished` are **Missing** (never called from C++).
`OnDock` **does not exist** anywhere (ignore any list that mentions it). Mouse
arrives through key callbacks: `LEFTBUTTON RIGHTBUTTON MIDDLEBUTTON WHEELUP
WHEELDOWN MOUSE4 MOUSE5`; `doubleClick` is a bool 2nd arg to `OnKeyDown`.

## Rendering contract — all Stubbed (permanent, by design)

`RenderInit`, `SetDrawLayer` (99 sites), `SetViewport` (58), `SetDrawColor`
(402 — hottest UI call), `DrawImage` (262; 231 pass nil = solid rect fill),
`DrawImageQuad` (22), `DrawString` (133), `SetClearColor` (0), `GetScreenSize`/
`GetScreenScale` (fake 1920×1080/1), DPI overrides. **`StripEscapes` is Bridged**
(real impl — needed to strip `^n`/`^xRRGGBB` color codes).

**EXCEPTION — must become real, not stubbed:** `DrawStringWidth` (106 sites →
currently returns 1) and `DrawStringCursorIndex` (8 → returns 0). Ported control
layout depends on exact legacy text metrics, which come from bitmap font atlases
(not `QFontMetrics`). The `.tgf`/`.tga` atlases are already bundled in
`runtime/SimpleGraphic/Fonts/`. The `^0`–`^9` palette values are now documented
(sourced from SimpleGraphic `common.cpp`). Phase 1 builds a `TextMetrics` engine +
color-markup parser. **See [[text-rendering]] — this is a whole subsystem, not a
one-liner.**

## Image handles — Stubbed

`NewImageHandle()` (50 sites) + `:Load/:Unload/:IsValid/:ImageSize`. `ImageSize`
returns 1,1 — which is why `pob_getTreeData` resolves sprite UVs from raw pixel
sub-rects in Lua rather than via handles. Tree atlas math depends on real sheet
sizes (`PassiveTree.lua:368/871`, `PassiveTreeView.lua:524/1216`).

## Input / window / clipboard

- `IsKeyDown(name)` (93 sites: CTRL×50, SHIFT×28, ALT×5) — **Stubbed** (nil).
  Some engine paths branch on modifiers during `pob_*`-invoked actions → make real.
- `GetCursorPos` (49) — **Stubbed** (0,0). `SetCursorPos`/`ShowCursor` (0 sites).
- `SetWindowTitle` (4: build-name-in-title, `Main.lua:1725/1727`) — **Stubbed**.
- `Copy`/`Paste` (18/4) — **Bridged** (QClipboard; no-op under `POB_NO_GUI`).
- `SetForeground()` — **Missing**. 1 site (`PoEAPI.lua:144`, after OAuth). Also
  missing from HeadlessWrapper. Add it.

## Filesystem / paths

- `GetScriptPath`/`GetRuntimePath` — **Bridged** (`_SRC_DIR`/`_RUNTIME_DIR`).
- `GetUserPath` — **Bridged but WRONG value.** `LuaEngine.cpp:39` sets
  `m_userDir = QDir::tempPath()+"/pob-qt"` (a throwaway temp dir). Since the engine
  appends `"/Path of Building/"` (`Main.lua:95`), the effective library/settings
  root is `<temp>/pob-qt/Path of Building/` — so **every existing user sees an empty
  build library and reset settings**. Fix (Phase 0): `QStandardPaths::
  writableLocation(QStandardPaths::DocumentsLocation)` — the Documents **parent**,
  NOT `Documents/Path of Building` (or you double-append). See [[core-lifecycle]].
- `MakeDir` (13, returns `ok,errMsg` — **consumed**) / `RemoveDir` (5) —
  **Broken**: C++ returns nothing. Fix return contract (Phase 0).
- `NewFileSearch(spec[,findDirs])` (21) + handle `:GetFileName/:GetFileModifiedTime/
  :NextFile` — **Bridged** via `pob.listDir` (no `GetFileSize`, unused). Verify
  wildcard semantics incl. `.zip.part*` glob and mtime for the timeless-jewel LUT loader.
- `GetWorkDir` (3) / `SetWorkDir` (0) — **Stubbed**.
- `GetCloudProvider` (1, OneDrive-offline popup) — **Stubbed** (nil,nil,nil).

## Process / OS / console

- `OpenURL` (12) — **Bridged** (QDesktopServices).
- `ConPrintf` (179 — logging backbone) — **Bridged** → `pob.log`. `ConPrintTable`/
  `ConExecute`/`ConClear` — **Stubbed** (`ConExecute` only ever sets `vid_mode 8` /
  `vid_resizable 3`).
- `SpawnProcess` (2), `Restart` (4), `Exit([msg])` (5), `TakeScreenshot` (1),
  `SetProfiling` (4) — **Stubbed** (update system + dev-restart dropped).

## Compression — Bridged (critical)

`Deflate`/`Inflate` (3/10 sites) — real **zlib stream** format (not raw), matching
PoB's import-code wire format. Used for build share-codes and Legion jewel LUTs.
Verify against real codes from all 7 build sites and against the 51.5 MB Glorious
Vanity LUT inflate.

## Sub-script protocol — Stubbed (the biggest gap)

`LaunchSubScript(scriptText, funcList, subList, ...)` runs `scriptText` in an
**isolated Lua state on a worker thread**. `funcList` = comma-separated main-state
globals exposed as **synchronous blocking** calls (e.g.
`"GetScriptPath,GetRuntimePath,GetWorkDir,MakeDir"`). `subList` = globals exposed
as **async fire-and-forget**, delivered to `OnSubCall(name,...)` on the main
thread (e.g. `"ConPrintf,UpdateProgress"`). Completion → `OnSubFinished(id, ret...)`;
error → `OnSubError(id, msg)`. Subscripts `require("lcurl.safe")` for networking.

**6 real launch sites** (all currently dead): `Launch.lua:314` (`launch:DownloadPage`
— the single network primitive every feature uses), `Launch.lua:348` (update check),
`PoEAPI.lua:108` (long-lived OAuth redirect HTTP server), `TreeTab.lua:763` (poeurl
resolve), `BuildSiteTools.lua:46` (build upload), `PoBArchivesProvider.lua:49`.
`AbortSubScript`/`IsSubScriptRunning` — 0 sites (API only). `GetTime` (86 sites,
ms) — **Broken** (epoch vs since-start; functional as deltas). Phase 10 owns this.

## Priority fix list (feeds Phase 0 and Phase 10)

| Fix | Phase | Size |
|---|---|---|
| `MakeDir`/`RemoveDir` return `(ok,errMsg)` | 0 | S |
| Add `SetForeground` | 0 | S |
| `GetTime` → monotonic ms-since-start (`QElapsedTimer`) | 0 | S |
| Wire `CanExit`/`OnExit` (Settings.xml save on quit) | 0 | M |
| Real `IsKeyDown` (modifier state) | 0/1 | S |
| CLI `arg` passthrough (open-on-launch) | 0/11 | S |
| Sub-script protocol (or async `pob.http` shim of DownloadPage) | 10 | L |
