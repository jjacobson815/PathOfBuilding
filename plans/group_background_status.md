# Group Backgrounds on the Qt/QML Skill Tree — Status

**Goal:** Draw skill-tree group backgrounds (`PSGroupBackground1/2/3` sprites) in the Qt/QML
canvas so the tree matches the legacy PoB look (dark circular backing behind each node cluster).

**Entry points (per `.clinerules`):** Qt/QML port — `app/src/main.cpp` + host `app/lua/pob_host.lua`,
binary `build-win/pob-qt.exe` (deployed to `dist/pob-qt.exe`).

---

## 1. What is DONE

### 1.1 QML draw loop (correct, in place)
File: [`app/qml/main.qml`](app/qml/main.qml)

A group-background draw loop was inserted into `onPaint`, **before** the connector and node
drawing, so backgrounds sit behind everything (matching legacy). It iterates `treeGroupModel`,
reads `grp.sprite` (`{ atlas, sx, sy, sw, sh }`), fetches the atlas `Image` via
`treeCanvas.getAtlas(gsp.atlas)`, and `ctx.drawImage(...)` at the group position scaled by
`treeView.scale`. The math mirrors the existing node-sprite drawing (`sx`/`sy` helpers,
`scale = treeView.scale`).

This loop is **correct** — it draws nothing only because `grp.sprite` is currently `nil`
(a data-resolution problem in the Lua host, not the QML).

### 1.2 Data investigation (complete)
- [`TreeGroupModel.h`](app/src/TreeGroupModel.h) / `.cpp` expose a `sprite` role returning
  `m.value("sprite")`. The QML `treeGroupModel` is the context property consumed by the loop.
- [`pob_host.lua`](app/lua/pob_host.lua) `pob_getTreeData()` builds the `groups` table and sets
  `sprite = groupSprite(group)` (line ~1327). `groupSprite` → `resolveGroupBackground(group.oo)`.
- **Key finding:** At runtime, `tree.assets["PSGroupBackground3/2/1"]` are *scale-keyed stubs*
  (keys `0.1246 … 0.3835`) with **empty `coords={}`** and a 1×1 placeholder `handle`. The engine
  does not populate group-background geometry into the host's `tree.assets`, so `resolveAsset(...)`
  cannot yield a rect.
- **Genuine geometry lives in source data:** [`src/TreeData/3_28/sprites.lua`](src/TreeData/3_28/sprites.lua)
  has a `groupBackground` asset with the atlas filename `group-background-3.png` and the
  `PSGroupBackground1/2/3` sub-rects:
  - `PSGroupBackground3`: `x=723, y=0,   w=283, h=143`
  - `PSGroupBackground2`: `x=723, y=286, w=178, h=178`
  - `PSGroupBackground1`: `x=443, y=444, w=138, h=138`
  - Atlas file confirmed present at `dist/src/TreeData/3_28/group-background-3.png` (761 KB).
- `treeVersion` is `3_28` (not `3_24`).
- Legacy engine selection confirmed in [`src/Classes/PassiveTreeView.lua`](src/Classes/PassiveTreeView.lua)
  (~line 601): `PSGroupBackground3/2/1` chosen by `group.oo[3]/[2]/[1]`.

### 1.3 Lua host rewrite (in place, but not yet verified working)
[`pob_host.lua`](app/lua/pob_host.lua) `resolveGroupBackground` + `loadSourceGroupBackground`
(lines ~1227–1289) were rewritten to load the genuine `groupBackground` asset from the source
`TreeData/3_28/sprites.lua` (fallback `tree.lua`) via `loadfile` + `pcall`, cache it in `_gbCache`,
and return `{ atlas="file:///.../group-background-3.png", sx, sy, sw, sh }` for the selected
`PSGroupBackgroundN` key.

---

## 2. Current BLOCKER (unresolved)

**The data-resolution code is not confirmed to run, and the capture harness is not re-executing.**

Evidence gathered this session:
- `dist/src/groupbg_debug.txt` exists but is **stale** (timestamp 07:36 PM). It shows
  `treeVersion=3_28`, `groupCount=735`, `withSprite=0`, and the asset dump proving the runtime
  `PSGroupBackgroundN` entries have empty `coords` (consistent with the OLD code that used
  `resolveAsset`, before `loadSourceGroupBackground` existed).
- `dist/src/gb_load.txt` was **never created**, even though the deployed
  [`dist/lua/pob_host.lua`](dist/lua/pob_host.lua) contains the `io.open(_SRC_DIR.."/gb_load.txt","w")`
  write at the top of `loadSourceGroupBackground`. This is contradictory: if `groupbg_debug.txt`
  (written *after* the groups loop) was produced by the current code, `loadSourceGroupBackground`
  must have been called and `gb_load.txt` must exist. Therefore `groupbg_debug.txt` is from a
  prior run and the current code path was never exercised.
- A fresh capture run (`dist\pob-qt.exe --capture captures`, Fusion style, `PATH` set for Qt DLLs)
  returned exit 0 but **did not update `captures/_status.log` or any PNG** (tree.png still 06:50 PM).
  So the capture harness did **not** execute its body this run.

**Most likely root cause of the capture no-op:** `runCapture` in [`main.cpp`](app/src/main.cpp)
requires `engine.viewList()` (from `main.modes.BUILD.viewList`) to be non-empty; if no build is
loaded, it logs "ERROR viewList empty" and returns 1. The 17:30 successful capture implies a build
*was* loaded then. The 23:45 run likely had no build loaded (or the harness exited before the
first `capLog`). Need to confirm how a build gets loaded for capture (see `main.cpp` lines 500–560
and the `--capture` arg handling at 180–210).

---

## 3. What is LEFT

1. **Get `grp.sprite` populated (the actual fix).**
   - Confirm `loadSourceGroupBackground()` executes and returns the cached `groupBackground`
     (verify by re-running with a working capture and reading `gb_load.txt`).
   - If `loadfile` on `sprites.lua` is problematic, fall back to a direct, robust parse or a
     version-keyed hardcoded table of the known `PSGroupBackground1/2/3` rects + atlas filename
     (data is static per `treeVersion`).
   - Ensure `resolveGroupBackground` returns a valid `{ atlas, sx, sy, sw, sh }` for every group.

2. **Make the capture actually run.**
   - Determine why the 23:45 `--capture` run produced no `_status.log`. Likely need a build loaded
     first (investigate `main.cpp` pre-capture setup / a default build, or run the app normally to
     load a build, then capture). The 17:30 run is the reference that worked.

3. **Re-capture + verify.**
   - Overwrite `captures/tree.png` AND save `skill_tree/new_groups.png`.
   - Compare vs `skill_tree/legacy.png` (or `import/legacy.png`) via
     [`tools/screenshot_diff.py`](tools/screenshot_diff.py) and/or visual inspection.
   - Confirm dark circular group backgrounds now appear behind clusters.

4. **Clean up debug code.**
   - Remove the `groupbg_debug.txt` dump block and the `gb_load.txt` write from
     [`pob_host.lua`](app/lua/pob_host.lua) once verified.

5. **Update wiki + complete.**
   - Update [`.obsidian-vault/01_Wiki/01_Modules/Core Controllers.md`](.obsidian-vault/01_Wiki/01_Modules/Core Controllers.md)
     to document the new group-background draw step; bump its YAML `last_modified` (per `.clinerules`).
   - Call `attempt_completion` with a concise summary (files + lines changed, how backgrounds are
     drawn) and the verification result.

---

## 4. Files touched (so far)
- [`app/qml/main.qml`](app/qml/main.qml) — group-background draw loop (DONE, correct).
- [`app/lua/pob_host.lua`](app/lua/pob_host.lua) — `resolveGroupBackground` + `loadSourceGroupBackground`
  rewrite + temporary debug writes (DONE, needs verification + cleanup).

## 5. Verified reference data (do not re-derive)
`treeVersion = 3_28`; atlas `group-background-3.png` (present in `dist/src/TreeData/3_28/`);
rects: `PSGroupBackground3 {723,0,283,143}`, `PSGroupBackground2 {723,286,178,178}`,
`PSGroupBackground1 {443,444,138,138}`.
