# Host Contract — sanctioned `src/` seams and the resync procedure

The Qt port keeps the legacy Lua calc engine (`src/`) **unmodified** except for a
small, explicitly-sanctioned set of "host seams". The rendering strategy is:
marshal Lua data → C++ QObject models → QML-native views (the SimpleGraphic draw
globals stay stubbed). See `port-plan/STATUS.md` (Invariants) and
`port-plan/reference/00-architecture.md`.

## Rule

**Do NOT modify `src/` calc logic.** New host-facing behavior belongs in the
bridge seam (`app/lua/pob_host.lua`, `app/src/LuaEngine.cpp`), never in `src/`.
Prefer adding a `pob_*` global in `pob_host.lua` over editing an engine module.

## The four sanctioned `src/` seams (host contract, not engine logic)

These are the ONLY permitted `src/` edits. Re-apply them on top of any upstream
resync. Do not expand this set without logging a decision in `STATUS.md`.

| File | Seam | Why it can't live in `pob_host.lua` |
|---|---|---|
| `Modules/Build.lua` | `self.viewList` registry (data-driven tab strip) + `sideBarCollapsed` wiring (toggle button, nav divider, `anchorSideBar.shown`) | The QML sidebar reads `main.modes.BUILD.viewList`; the registry must be a field on the build mode object. |
| `Modules/Main.lua` | `sideBarCollapsed` option (init default + `LoadSettings` read + `SaveSettings` write) | Persisted per-user setting; must round-trip through the engine's Settings.xml serializer. |
| `Modules/Data.lua` | `powerStatList`: `TotalDot`→`TotalDotDPS` (label "Total DoT DPS") | Power-report stat id consumed by the tree power view. |
| `Modules/UITheme.lua` | **New file** — sidebar/nav layout constants + colour tokens (`navWidth`, `sideBarWidth`, `navButtonGap`, `colour.sideBarLine`, …) | The theme singleton (`app/src/Theme.cpp`) and the Build.lua viewList loop read these; a Qt-only module, absent from legacy. |

**Legacy per-button side-effects are NOT replicated by the viewList loop.** The
loop's generated button callback is just `self.viewMode = viewId`. Legacy's
individual mode buttons carry extra side-effects (e.g. `modeImport` calls
`importTab:TryFetchCharacterList()`); the Qt host drives view switching through
QML → `LuaEngine::setActiveView`, so those legacy button callbacks never fire.
Any such behavior is re-homed in the corresponding QML view (e.g. import char
fetch → Phase 11), not in the viewList seam.

## Resync procedure (upstream league updates — `Modules/` + `Data/` atomically)

`src/` drifts from the maintained legacy checkout each league. The coupled unit is
**`Modules/` + `Data/` + `Classes/` + the runtime Lua deps they pull in**
(`runtime/lua/*.lua`) — **always move them together**. (Phase 0.4 first tried
Modules/+Data/ alone; that crashed build-mode init because `Classes/ItemDBControl`
iterated `data.powerStatList` with `pairs()` while the resynced `Data.lua` added a
function-valued entry legacy handles with `ipairs` — and the new `Classes/PoEAPI`
needs `runtime/lua/sha2.lua`+`socket.lua`.) Procedure (repeat per upstream sync;
Phase 15 owns the recurring cadence):

1. **Classify** every `Modules/`+`Data/`+`Classes/` file CR-normalized: `changed` /
   `qt-only` / `legacy-only` (`diff -q <(tr -d '\r' <qt) <(tr -d '\r' <legacy)`).
   Most of the "N files differ" is CRLF-only noise — normalize before diffing. Then
   diff `runtime/lua/` too and copy any legacy modules the new code `require`s.
2. **Copy** pure (never-Qt-edited) changed files legacy→qt; **add** legacy-only
   files; **remove** qt-only files superseded upstream (e.g. `Data/ModImplicit.lua`
   was merged into `Data/ModItemExclusive.lua`).
3. **3-way merge every Qt-edited file** so upstream drift and the local change
   combine: the four Modules seams (Build/Main/Data/UITheme) **and** the Suggest
   Path `Classes/` trio (TreeTab/PassiveSpec/PassiveTreeView). Find them with
   `git diff --name-only <port-commit> HEAD -- src/`. Merge:
   `git merge-file -p <qt-current> <pristine-base> <legacy>` **in LF space**
   (git blobs are LF; the worktree is CRLF — merging mismatched EOLs conflicts the
   whole file). Write the result back as CRLF (`sed 's/$/\r/'`).
4. Never let a `.gitattributes` change rewrite the binary `.zip` timeless-jewel
   LUTs (`* text=auto` already treats them as binary — leave it).
5. **Verify:** headless self-test exit 0 + `--capture` all views + the calc-parity
   harness (Phase 0.6) against the chosen baseline.
