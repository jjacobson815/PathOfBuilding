# Reference: Settled Architecture & Invariants

The decisions below are **already made and load-bearing**. Do not relitigate them
inside a phase; treat them as constraints. If a phase seems to require breaking
one, stop and raise it with the user.

## The one-paragraph model

The **LuaJIT calc engine (`src/`) is the product**; the host is plumbing. The
legacy host was SimpleGraphic (Windows-only, immediate-mode drawing). The Qt
host replaces it with **Qt6/QML + C++**. Crucially, the Qt host does **not**
re-implement SimpleGraphic's drawing API. Instead it **marshals Lua data
structures into C++ Qt models** that **QML-native views** render. The engine is
driven by mutating its Lua state through a bridge and reading results back.

```
QML views  ──reads──►  C++ QObject models (QVariant)  ──marshal──►  Lua tables
QML actions ──calls──►  LuaEngine Q_INVOKABLE methods ──mutate───►  main/build/tabs
                        LuaEngine emits granular *Changed signals ◄── after mutation
```

## The two seams (where all host work happens)

1. **`app/lua/pob_host.lua`** (~1,680 lines) — the Lua-side bridge. Defines the
   SimpleGraphic globals the engine expects (most rendering/input ones are
   **intentional no-op stubs**), reimplements `LoadModule`/`require`, and exposes
   `pob_*` top-level global helpers that C++ calls (tree data, items, skills,
   calcs, config, save/load, build library, etc.).
2. **`app/src/LuaEngine.cpp` / `.h`** — the C++ bridge. Embeds LuaJIT, registers
   the `pob` C table (log, paths, clipboard, zlib inflate/deflate, http, makeDir,
   listDir, getTime), and exposes `Q_INVOKABLE` methods + granular `*Changed`
   signals that QML binds to. `callGlobal` does a single `lua_getglobal`, so every
   Lua helper **must be a top-level global** (`pob_selftestCalcOutput`, not
   `pob.selftest.x`).

Everything else in `app/src/*Model.cpp` is a thin `QVariantList` wrapper feeding
one QML view.

## Non-negotiable invariants

1. **Do NOT emulate SimpleGraphic *draw* globals.** `SetDrawLayer`, `SetViewport`,
   `SetDrawColor`, `DrawImage*`, `DrawString`, `NewImageHandle` stay stubbed.
   QML owns all rendering. (Consequence: no legacy `*Control.lua` draw code runs;
   each view is re-authored in QML. This is the whole strategy, not a shortcut.)
   **Exception — the *measure* globals must be real:** `DrawStringWidth` and
   `DrawStringCursorIndex` are NOT stubbable, because ported control layout math
   (caret, ellipsis, dropdown/tooltip auto-width) depends on exact legacy text
   metrics. They need a `.tgf`-backed metrics engine, not `QFontMetrics`. See
   [[text-rendering]].
2. **Do NOT modify `src/` calc logic.** Only `app/` and the bridge seam may
   change. See "The src/ divergence contract" below for the *already-existing*
   exceptions that must be managed, not expanded.
3. **Drive the engine through `build.calcsTab` + `build.buildFlag`, not raw
   `calcs.*`.** One mutation sets `buildFlag`; the host then runs the
   `wipeGlobalCache → outputRevision++ → CalcsTab:BuildOutput() → RefreshStatList`
   sequence. See [[calc-engine-contract]].
4. **Keep LuaJIT** (not PUC Lua). The generated data files and `bit.*` usage
   assume it; GC64 on x64 recommended for the 51.5 MB Glorious Vanity LUT.
5. **Every phase boundary must keep `pob-selftest` green** (exit 0) and must not
   regress any view that rendered at the previous boundary (capture gate).
6. **The engine reads data dirs relative to process CWD = `src/`.** All binaries
   run with cwd `src/` (opens `TreeData/`, `Assets/`, `Data/`, `../manifest.xml`).
   Never change this without updating `pob_host.lua` and the selftest cwd.

## The src/ divergence contract (the "engine unchanged" caveat)

"Engine stays unchanged" is **already violated** in the Qt repo working tree, on
purpose, and these edits are load-bearing for the host:

- `src/Modules/Build.lua` — replaced per-tab ButtonControls with a **data-driven
  `self.viewList` registry** `{id,label,key,group,tab}`. The Qt sidebar and the
  capture harness consume this. **This is the sanctioned host seam for the tab
  strip.**
- `src/Modules/Main.lua` — `sideBarCollapsed` setting persistence.
- `src/Modules/Data.lua` — `TotalDot` → `TotalDotDPS` rename.
- `src/Modules/UITheme.lua` (new) — design-token source consumed by `Theme.cpp`.

**Rule going forward:** treat these four as part of the *host contract*, not the
engine. Prefer moving new host-only logic into `pob_host.lua` rather than adding
new `src/` edits. Any *new* `src/` change must be logged as a decision in
`STATUS.md` with justification. Also note: `src/` in the Qt repo is an **older
upstream snapshot** than this legacy repo (see [[data-and-assets]] and
[[build-test-packaging]] for the resync procedure).

## Known correctness bugs in the current bridge (fix in Phase 0)

- `MakeDir`/`RemoveDir` drop their `(ok, errMsg)` return contract → `pob_createFolder`/
  `pob_deleteFolder` always report failure.
- `SetForeground` is missing entirely → runtime `attempt to call nil` if OAuth
  ever succeeds.
- `GetTime` returns epoch-ms, not ms-since-start (functional today because all
  uses are deltas; fix for exactness).
- Lifecycle callbacks `CanExit`/`OnExit` are never invoked from C++ → **Settings.xml
  is never saved and the unsaved-build prompt never runs** (data-loss gap).
- `LaunchSubScript` is a no-op stub → every engine network path is silently dead.

See [[host-api-contract]] for the full global-by-global status table.

## Cross-cutting architectural debt (address opportunistically per phase)

- Monolithic 104 KB `app/qml/main.qml` (1,791 lines) — split into components in Phase 1.
- Canvas-2D JS tree renderer repaints fully per transform; C++ `hitTest` is a
  linear scan — harden in Phase 4.
- Synchronous libcurl HTTP on the GUI thread — move off-thread in Phase 10.
- Full `QVariant` deep-copy marshalling on every change; `pob_getTreeData`
  re-resolves sprites (with per-asset `io.open`) every call.
- Nothing is version-controlled; demo scaffolding (800 ms rename `QTimer`,
  hardcoded stale log paths, `/workdir` outputs) still in the production path.
