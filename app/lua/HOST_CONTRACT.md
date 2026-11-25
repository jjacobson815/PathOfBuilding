# Host Contract — Sanctioned `src/` Seams, Stubs, and Upstream-Sync Procedure

The Qt port keeps the legacy Lua calc engine (`src/`) **unmodified** except for a
small, explicitly-sanctioned set of host seams and documented stock-LuaJIT
compatibility edits. The rendering strategy is: marshal Lua data -> C++ QObject
models -> QML-native views. See `port-plan/STATUS.md` (Invariants) and
`port-plan/reference/00-architecture.md`.

## Rule

**Do NOT modify `src/` calc logic.** New host-facing behavior belongs in the
bridge seam (`app/lua/pob_host.lua`, `app/lua/pob_*.lua`, `app/src/LuaEngine.cpp`),
never in `src/`. Prefer adding a `pob_*` global or module in `app/lua/` over
editing an engine module.

Engine objects constructed in `app/` MUST use the upstream class-rework syntax
`new("X"):X(args)`, never bare `new("X", args)`.

## Permanent Decommission of SimpleGraphic & Legacy Execution Globals (Phase 15.1)

The SimpleGraphic rendering/input/lifecycle globals in `app/lua/pob_host.lua`
are **permanently stubbed**. QML owns all display and window management; these
globals never become real:

- **Rendering & layout stubs (permanent no-ops):** `RenderInit`, `SetClearColor`,
  `SetDrawLayer`, `SetViewport`, `SetDrawColor`, `GetDrawColor`, `DrawImage`,
  `DrawImageQuad`, `DrawString`, `SetWindowTitle`, `GetCursorPos`, `SetCursorPos`,
  `ShowCursor`, `TakeScreenshot`.
  - Any future reuse of legacy `Draw*` code would require full text metrics plus
    the `^0`–`^9` / `^xRRGGBB` colour palette (external sourcing).
  - `NewImageHandle()` is metadata-only (`Load`, `Unload`, `IsValid`,
    `ImageSize` backed by `pob.imageSize` header-only `QImageReader` probe); it
    never holds a GPU texture.
  - `DrawStringWidth` and `DrawStringCursorIndex` are real `.tgf`-backed
    `TextMetrics` calls required for ported control layout math.
- **Legacy execution & lifecycle stubs (permanent no-ops):** `SpawnProcess`,
  `ConExecute`, `Restart`, `Exit`, `SetWorkDir`, `SetProfiling`.
  - No runtime path in `app/` may spawn `Update.exe`, invoke `SpawnProcess`, or
    execute `ConExecute("set vid_mode...")` or similar legacy commands.
  - Automated enforcement: `python tools/audit_host_contract.py`.

## The Four Sanctioned `src/` Seams (Host Contract, Not Engine Logic)

These are the ONLY permitted `src/` feature/host edits. Re-apply them on top of
any upstream resync. Do not expand this set without logging a decision in
`port-plan/STATUS.md`.

| File | Seam | Why it cannot live in `pob_host.lua` |
|---|---|---|
| `src/Modules/Build.lua` | `self.viewList` registry (data-driven tab strip) + `sideBarCollapsed` wiring (toggle button, nav divider, `anchorSideBar.shown`) | The QML sidebar reads `main.modes.BUILD.viewList`; the registry must be a field on the build mode object. |
| `src/Modules/Main.lua` | `sideBarCollapsed` option (init default + `LoadSettings` + `SaveSettings`) + Part 1.4 cloud robustness (`errorReadingSettings` retry-after-hydrate, `OpenPathPopup` / `OpenCloudErrorPopup` `pob.*` handoff) | Persisted per-user setting and startup error popups live inside `Main.lua`'s `Settings.xml` serializer and lifecycle hooks. |
| `src/Modules/Data.lua` | `powerStatList`: `TotalDot` -> `TotalDotDPS` (label `"Total DoT DPS"`) | Power-report stat id consumed by the tree power view. |
| `src/Modules/UITheme.lua` | **New file** — sidebar/nav layout constants + colour tokens (`navWidth`, `sideBarWidth`, `navButtonGap`, `colour.sideBarLine`, ...) | The theme singleton (`app/src/Theme.cpp`) and `Build.lua` `viewList` loop read these; a Qt-only module absent from legacy. |

**Legacy per-button side-effects are NOT replicated by the `viewList` loop.**
The loop's generated button callback is `self.viewMode = viewId`. Legacy's
individual mode buttons carry extra side-effects (e.g. `modeImport` calls
`importTab:TryFetchCharacterList()`); the Qt host drives view switching through
QML -> `LuaEngine::setActiveView`, so those legacy button callbacks never fire.
Any such behavior is re-homed in the corresponding QML view / `pob_*` module,
not in the `viewList` seam.

## Documented Stock-LuaJIT Compatibility Edits in `src/`

Upstream PoB uses SimpleGraphic's patched LuaJIT syntax extensions (`+=`, `..=`,
`?.:`). Because `pob-qt` embeds stock LuaJIT 2.1 (GC64), the following minimal
syntax-only rewrites are permitted in `src/` and must be preserved across syncs:

- `src/Classes/CompareBuySimilar.lua`: standard Lua equivalents for `?.:` (around
  line 80) and `..=` (around lines 205–206).
- `src/Modules/Main.lua`: standard Lua `count = count + 1` in `SaveModCache`
  where upstream uses `+=` (if reintroduced upstream).

Every `.lua` file under `src/` must parse cleanly with stock `luajit -bl`.

## Wave 1 Host Bridge Seams (`app/lua/` + `app/src/`)

- **`SubScriptManager` (`app/src/SubScriptManager.h/.cpp`):** Manages isolated
  worker-thread LuaJIT states backing `LaunchSubScript`, `AbortSubScript`, and
  `IsSubScriptRunning` via `pob.launchSubScript`, `pob.abortSubScript`, and
  `pob.isSubScriptRunning`, plus URI scheme registration/parsing.
- **`pob.emitSignal(...)` (`LuaEngine::l_pob_emitSignal` -> `LuaEngine::emitNamedSignal`):**
  Emits named Qt signals on the UI thread (`build`, `tree`, `items`, `skills`,
  `config`, `notes`, `party`, `compare`, `network`, `import`, `buildList`,
  `mode`, `calcs`). `LuaEngine::invoke()` also emits collected signals in fixed
  order with `calcs` last.
- **Optional Wave 1 Lua Modules (`app/lua/pob_host.lua`):**
  - `pob_network` (Phase 10): async network / subscript hooks.
  - `pob_import` (Phase 11): import / export tab async hooks.
  Loaded via guarded `pcall(require, ...)` in `pob_host.lua` so missing modules
  do not block boot while real load errors are logged via `pob.log`.

## Wave 2 Host Bridge Seams (`app/lua/` + `app/src/`)

- **Compare Tab Filter (`LuaEngine::viewList()` / `LuaEngine::setActiveView()`):**
  Filters `id == "COMPARE"` out of `main.modes.BUILD.viewList` in C++ (returning
  8 BUILD views: `TREE`, `SKILLS`, `ITEMS`, `CALCS`, `CONFIG`, `NOTES`, `IMPORT`,
  `PARTY`) so Phase 13 stays dropped with zero `src/Modules/Build.lua` edits.
- **Dev Mode & Update Repo Globals (`LuaEngine::init()` / `app/src/main.cpp`):**
  - `--dev` CLI flag or `POB_DEV_MODE=1` env sets `_POB_DEV_MODE` (boolean),
    wired into `launch.devMode` in `pob_host.lua` prior to `Modules/Main` init
    (for ModCache regen / engine dev checks). UI-only dev controls (`~~temp~~.xml`
    autosave, JSON import, `devModeAlt`) are dropped for v1.
  - `POB_UPDATE_REPO` env (or compile-time macro, default
    `"jjacobson815/PathOfBuilding"`) configures the Phase 14.2 GitHub Releases
    notifier target.
- **Phase 14.2 Update Notifier (`app/lua/pob_update.lua`):**
  Loaded via guarded `pcall(require, "pob_update")` in `pob_host.lua`; uses
  `SubScriptManager`/`pob.http` and emits `LuaEngine::updateChanged()` via
  `"update"` in `pob.emitSignal` / `invoke()` `_emit`. Legacy
  `launch.CheckForUpdate` and `launch.ApplyUpdate` are overridden to inert
  no-ops in `pob_host.lua` before `OnInit`.
- **Phase 15.2 Split Tree Payload (`pob_getTreeData` / `pob_getTreeDynamicState`):**
  Splits static tree topology (keyed by `topologyKey` covering tree version,
  spec, `_treeSpecSerial`, cluster `subGraphs`, `hashOverrides`, and
  class/ascendancy) from dynamic allocation state so `TreeViewController` +
  `TreeScene` perform in-place allocation updates without re-marshalling the
  full static tree on every click. `pob_getTreeData()` (no-arg) remains
  backwards-compatible.

## Upstream-Sync Procedure (Ongoing Per-League Cadence — Phase 15.4)

`src/` drifts from maintained upstream each league. The coupled unit is
**`src/Modules/` + `src/Data/` + `src/Classes/` + `runtime/lua/`** — always
move them together.

Use `tools/upstream_sync.py` to automate classification, 3-way merging, and
syntax verification:

```bash
python tools/upstream_sync.py --dry-run --upstream origin/dev
python tools/upstream_sync.py --apply --upstream origin/dev
```

1. **Classify CR-normalized:** Normalize `\r\n` -> `\n` before diffing
   `src/Modules/`, `src/Data/`, `src/Classes/`, and `runtime/lua/` against the
   upstream ref (`unchanged`, `crlf_only`, `changed`, `qt_only`, `upstream_only`).
2. **Copy / add / remove pure files:** Copy never-Qt-edited `changed` files from
   upstream, add `upstream_only` files (and any `runtime/lua/*.lua` modules
   newly `require`d), and remove `qt_only` files superseded upstream.
3. **3-way merge Qt-edited files in LF space:** For the 4 sanctioned `src/`
   seams and documented stock-LuaJIT compat files, run
   `git merge-file -p <qt-current-lf> <merge-base-lf> <upstream-lf>` in LF space
   and write the result back with CRLF (`\r\n`) line endings.
4. **Preserve binary `.gitattributes`:** Never rewrite binary `.zip`
   timeless-jewel LUTs (`* text=auto` already treats them as binary).
5. **Syntax & contract check:** Run `luajit -bl` across `src/` Lua files and
   `python tools/audit_host_contract.py` (must exit 0).
6. **ModCache & verification gates:** Regenerate ModCache, then run
   `pob-selftest`, `pob-qt --headless`, and `tools/qt_calc_parity.lua`.

### `src/Export/` Data-Refresh Note

When a league update ships new game data:
1. Run the legacy `src/Export/` pipeline + `bun_extract_file` against
   `Content.ggpk`.
2. Copy the regenerated `src/Data/` and `src/TreeData/` assets into the
   repository.
3. Regenerate ModCache and run the calc-parity harness (`tools/qt_calc_parity.lua`)
   and `pob-selftest` before committing.
