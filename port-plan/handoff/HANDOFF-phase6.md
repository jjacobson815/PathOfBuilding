# Handoff — Phase 6 (Items tab), for the next agent

Read this AFTER `port-plan/STATUS.md` and BEFORE `phases/PHASE-6-items-tab.md`.
The original task prompt still applies in full; this file only says where things
stand and what the last session learned.

## Where things stand (2026-09-29)

| Item | State |
|---|---|
| Branch | `cloud/phase-6`, pushed, based on `origin/dev` @ 83100d2 (Phase 5 merged) |
| Draft PR | https://github.com/jjacobson815/PathOfBuilding/pull/7 (against `dev`); CI green on `6ddfc60`, see the session report for the 6.2 push |
| Part 6.1 | DONE, ticked, committed, pushed (`6ddfc60`) |
| Part 6.2 | DONE in the first Windows session, ticked, committed, pushed; check `items-lists` (44 flags). Drag-drop / tooltips / shared-sets pane NOT eyeballed (no computer-use tools) |
| Part 6.3 | item 1 DONE (editor panel, variants, sockets/links, edit-text popup; check `items-editor`, 25 flags); items 2-4 open (item 4's edit-text half done). Next: 6.3 item 2 |
| Parts 6.4 – 6.5 | NOT STARTED |
| Gate | Windows: `pob-selftest EXIT=0`, `pob-qt --headless EXIT=0` (checks `items-slots`, `items-lists`, `items-editor`) |
| Phase 7 switch | NOT done. STATUS.md must keep "ACTIVE: Phase 6" until 6.5 is ticked |

Continue at **Part 6.3 item 2**. Do not redo 6.1 / 6.2 / 6.3 item 1.

## Setup traps (cost the last session time)

1. Local `dev` may be stale (no Phase 5). Always `git fetch origin` first. If
   `cloud/phase-6` exists on origin, `git checkout -B cloud/phase-6 origin/cloud/phase-6`.
2. A branch created from `origin/dev` tracks `dev`. Run
   `git branch --unset-upstream` and push with `git push -u origin cloud/phase-6`.
3. Gate: `SKIP_DEPS=1 tools/linux-selftest.sh` (plain on a fresh container).
   ~3-5 min. Exit code is the verdict.
4. Visual checks: `apt-get install -y xdotool x11-apps imagemagick`. Recipe that
   worked: host file `/tmp/vis/host.lua` =
   ```lua
   _POB_LUA_DIR=_SRC_DIR.."/../app/lua"
   dofile(_POB_LUA_DIR.."/pob_host.lua")
   local tb = dofile(_SRC_DIR.."/../spec/TestBuilds/3.13/OccVortex.lua")
   pcall(pob_loadBuildXML, tb.xml, "OccVortex")
   ```
   then `cd src; Xvfb :99 -screen 0 1280x800x24 &`, run
   `QT_QPA_PLATFORM=xcb DISPLAY=:99 ../build-linux/pob-qt --src $PWD --runtime ../runtime --host /tmp/vis/host.lua`
   (needs `ninja -C build-linux` after any QML change: QML is in the qrc). It
   opens on Calcs; click Items at (50,115). Check `/tmp/pob-qt-main.log` for
   QML errors first. OccVortex has 22 populated rows incl. 3 jewel sockets.
5. `pkill pob-qt` before rebuilding. Don't `pkill -f` a pattern in your own command.
6. Tooling hiccup seen: the auto-mode classifier sometimes returned "no verdict"
   for Bash / `send_later` for a while. Retry once, then do non-shell work.

## What exists (Part 6.1) — reuse, don't rebuild

- `app/lua/pob_items.lua` (required from `pob_host.lua` after `pob_skills`).
  Skeleton helpers: `ctx()`, `done(extra, emit)`, `fail(msg)`, `tipLines(fn)`,
  `withKeys({SHIFT=..,CTRL=..}, fn)` (temporarily swaps `IsKeyDown`),
  `slotRecord`, `slotOptions`, `syncLoadouts`.
  Functions: `pob_itemsGetState`, item-set ops (`GetSetList/SetActiveSet/NewSet/
  CopySet/RenameSet/DeleteSet/MoveSet/SetTooltip`), `SetWeaponSet`, `Equip`,
  `SetFlaskActive`, `SlotTooltip`, `EquipInSet`, `Undo/Redo`.
  Selftest: `pob_selftestItemsSlots`, helpers `itSnapshot/itRestore/finish`,
  registered in `app/src/selftest_checks.h` after `skills-persist`.
- `app/qml/views/ItemsView.qml`: left column (x 0-424) is the 6.1 UI. The RIGHT
  column (`browserPane`, x 430) is the OLD item list + "Add from text" and is
  what Part 6.2 replaces.
- `_emit` sets: `EMIT = build,items,calcs`; `EMIT_TREE` adds `tree` (use for
  anything that changes jewel sockets: equip, delete, undo).
- The Tree tab's `pob_getSpecList` / `pob_setActiveSpec` + `SpecManagePopup`
  are reused for the Items tab's tree selector.

## Legacy map

`port-plan/handoff/phase6-items-recon.md` (280 lines) is the recon brief for ALL
of Phase 6 with file:line refs (sets, slots, lists, DB coroutine, editor
sections, tooltip/compare, XML). It was written by a subagent from the legacy
code. Trust it, spot-check line numbers. Per the protocol, have a subagent read
legacy code and keep edits in the main session.

## Part 6.2 plan (DONE — kept for reference; what landed is in the phase file's 6.2 session log)

- All-items list (ItemListControl, `itemsTab.itemOrderList`): row text via
  `ItemListControl:GetRowValue` (adds "(Unused)"/"(Used in ...)"), tooltip via
  `AddItemTooltip(tip, item)`, Ctrl+click equip (Shift = slot 2, explicit flags,
  do NOT call `OnSelClick` since it reads `IsKeyDown`), double-click edit
  (opens editor on a copy with the same id: needs 6.3's `SetDisplayItem`, so
  wire the bridge call now and the editor in 6.3), copy, delete with confirm
  message built from `GetEquippedSlotForItem` / `FindEquippedAbyssJewel` /
  `FindSocketedJewel` (ILC:198-232), Delete All / Delete Unused / Sort (lift
  ILC:22-67), reorder = insert/remove + `AddUndoState`.
- Uniques + Rare Templates DB (ItemDBControl): filters by assigning
  `controls.*.selIndex` / `search.buf` then `listBuildFlag = true`. The list
  build is a coroutine driven ONLY from `ItemDBClass:Draw`, which never runs in
  the host, so pump it yourself from a QML Timer in slices and report the
  "Sorting... (N%)" progress (`defaultText`). Stat sort runs calcFunc per
  item x slot. Never mutate DB items: `new("Item", item.raw)` + `NormaliseQuality()`.
- Shared items (`main.sharedItemList`) and shared item sets
  (`main.sharedItemSetList`): lift the drag bodies (ISL:93-106, SISL:80-100);
  add the missing `PopulateSlots` + `SyncLoadouts` on shared-set import.
- Drag-receive onto a slot was deliberately deferred from 6.1 to here.
- Selftest `items-lists`: cover equip via ctrl-click semantics, delete-unused,
  delete-all, sort, DB filter counts, a stat-sort run to completion, shared list.

## Traps (all confirmed, also summarised in STATUS.md Done log)

- Never marshal an Item, slot control, Tooltip or dropdown row holding `modList`
  raw (gigabytes). Return plain tables.
- `IsKeyDown` and `GetCursorPos` are stubs. Pass explicit shift/ctrl args.
- `ItemsTab:UpdateSockets()` runs only from Draw/AddItemTooltip: call it before
  reading sockets. `ItemSlotControl:Populate` order comes from `pairs`
  (unstable): sort by `itemOrderList`.
- `AddItem` pushes NO undo state; callers add one. Selftest fixtures that need
  undo must call `it:AddUndoState()` after adding.
- Undo REPLACES `items` and `itemSets`. Address by id / index, re-read after.
- `CreateDisplayItemFromRaw` runs `CopyAnointsAndEldritchImplicits` (aliases the
  equipped item's mod-line tables) and sets `displayItem`. Not for compare
  hovers. `pob_addItemFromRaw` leaves a stale `displayItem` (fix in 6.3).
- Calc-touched Lua tables, EditControl.text / CheckBox.state binding break,
  COUNT-model repeaters, ConfirmPopup message bound to a selection (Qt 6.4
  crash), no clipboard under offscreen, PopupBase Keys: see the task prompt list.

## Per-part checklist (unchanged)

selftest that FAILS when the key fix is removed -> gate -> Xvfb visual check ->
tick phase file + session log + documented differences -> commit -> push.
Commit trailer lines are in the session's attribution reminder. Watch PR #7.
Stop at a finished part if room runs low and write the exact stop point in
STATUS.md.

## Open items outside Phase 6 (do not start)

- Windows-only: re-baseline `app/tests/capture-baseline/*.png`, HLSL tint path.
- `PopupBase` Keys on a Dialog never fire (separate task).
- Hour-out PR check-in could not be scheduled (tool error); re-arm if available.
