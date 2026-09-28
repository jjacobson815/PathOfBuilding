# Phase 5 — Skills Tab

**Status:** DONE (2026-09-28, cloud session, branch `cloud/phase-5`)
**Goal:** Port the skills/gems tab: skill sets, the socket-group list with its
keyboard semantics, the group detail panel, and the dynamic gem rows built on
GemSelectControl (fuzzy matching + live DPS-sorted candidates + compare tooltips).
**Depends on:** Phase 1 (components incl. EditControl/DropDownControl), Phase 2
(GemSelect live compares), Phase 3 (shell main-skill selectors reference this data).
**References to load:** [[tabs-catalog]] (Skills tab), [[control-library]]
(GemSelectControl, SkillListControl), [[calc-engine-contract]] (gem DPS compares).

## Part 5.1 — Skill sets & socket-group list

- [x] Skill sets: dropdown + Manage popup (generic set-manager: new/copy/delete/
  rename/reorder). (S)
- [x] Socket-group list (SkillListControl): add/delete/reorder with link-color gem
  string rendering (R-G-B letters) + slot icons; **keyboard semantics**: Ctrl+C/V
  copy/paste socket groups as text (round-trip the "Label:/Slot:/Name lvl/q
  DISABLED count" format), Ctrl+click enable/disable, Ctrl+right-click include/
  exclude FullDPS, right-click set-as-main. Reorder fixes `mainSocketGroup` + calcs
  indices. (M)

## Part 5.2 — Group detail & gem options

- [x] Group detail panel: label edit, "Socketed in" slot dropdown (with equipped-
  item tooltip), Enabled checkbox, Include-in-FullDPS checkbox, source Count edit,
  **Imbued Support gem selector** (per-slot ExtraSupport + clear; hidden for item-
  provided groups), source note for item/node/explode-provided groups. (M)
- [x] Gem options panel: sort-by-DPS checkbox + sort-stat dropdown (FullDPS/
  CombinedDPS/Hit/Average/DoT/Bleed/Ignite/Poison/EHP), default gem level dropdown
  (normalMax/corruptedMax/awakenedMax/characterLevel/levelOne), default gem quality,
  show-support-gems dropdown (All/Non-Exceptional/Exceptional), show-legacy-gems. (S)

## Part 5.3 — Gem rows (GemSelectControl)

- [x] Dynamic gem rows (one per gem, created on demand): delete X, **GemSelect**
  (fuzzy/abbreviation match `FindSkillGem`, sorted-by-DPS dropdown with gem
  tooltips, `:tag`/`:-tag` filters, S/A overlay filters, ENTER/ESC commit/revert,
  supporting-gem cross-highlight), level edit (+N from supports), quality edit
  (tooltip: quality stat lines + "setting to 20 gives you" diff), enabled checkbox
  (enable/disable diff tooltip), count edit (DPS-mult tooltip), error label
  (unrecognized/ambiguous/unsupported), per-Vaal enableGlobal1/2 checkboxes,
  tab-group nav, horizontal scrollbar. (L — GemSelect live compares depend on the
  Phase 2 calculator bridge + the async-calc decision.)
- [x] Socket-group tooltip builder (`AddSocketGroupTooltip`) reused by side bar +
  Calcs tab. (S)

## Part 5.4 — Persistence

- [x] `<Skills>` XML round-trip: attribs (activeSkillSet, defaultGemLevel/Quality,
  sortGemsByDPS[Field], showSupportGemTypes, showLegacyGems); `<SkillSet>` →
  `<Skill>` groups → `<Gem>` with full attribs (nameSpec, skillId, gemId/variantId,
  level, quality, enabled, enableGlobal1/2, count, and every `skillPart`/`stageCount`/
  `mineCount`/`minion`/`minionItemSet`/`minionSkill` + their `*Calcs` variants).
  Support **legacy flat `<Skill>`** and legacy gem-name matching. (M)
- [x] Undo state deep-copies all sets and preserves main-group selection for both
  side bar and Calcs. (S)

## Acceptance gate

- Open a build → socket groups, gems, links, and per-gem levels/qualities match
  legacy; main-skill selector in the shell reflects the same data.
- Type a gem abbreviation → correct fuzzy match; DPS-sorted order matches legacy;
  hover shows correct "selecting this gives you:" diff.
- Copy a socket group as text and paste into a fresh group → identical group.
- Save → `<Skills>` round-trips through legacy PoB (incl. variantId, `*Calcs` fields).
- `pob-selftest` skills check green; capture diff clean.

## Notes

- GemSelect's live DPS ordering runs the calc engine per candidate (memoized on
  outputRevision) — this is the first heavy hover-compare consumer; if it's janky,
  the Phase 2 threading decision needs revisiting, not a GemSelect hack.
- Two independent main-skill selections exist (side bar plain fields + Calcs
  `*Calcs` fields) — keep them separate.

## Session log — 2026-09-28 (cloud, Linux)

Bridge: `app/lua/pob_skills.lua` (required at the end of `pob_host.lua`). It
drives the LIVE `skillsTab`: `SetDisplayGroup(sg)` then the legacy control
closures (`changeFunc`/`selFunc`/`gemChangeFunc`/`tooltipFunc`), lifting code
only where legacy hit-tests the cursor or draws. Recon brief of the legacy tab
(file:line for every feature) was done by a subagent.

**Part 5.1 — DONE.**
- Skill sets: `pob_skillsGetSetList/SetActiveSet/NewSet/CopySet/RenameSet/
  DeleteSet/MoveSet` (copy lifted from SkillSetListControl.lua:14-32; move =
  modFlag only, like legacy). UI: dropdown (enabled with > 1 set) + generic
  `components/SetManagePopup.qml` (Copy/Delete left, New/Rename right, F2,
  Delete key, double-click activates; Up/Down instead of drag, as in
  SpecManagePopup). Phases 6/7 can reuse it for item/config sets.
- Socket-group list: `components/SocketGroupList.qml`. Row text = live
  `SkillListControl:GetRowValue` (link colours, (Active)/(Disabled)/(FullDPS));
  slot icon = lifted GetRowIcon map. Click selects, Ctrl+click enable/disable,
  right-click main, Ctrl+right-click FullDPS, drag reorder (live
  `OnOrderChange` fixes mainSocketGroup + calcs skill_number), Up/Down/Home/End,
  Ctrl+C copy, Delete/Backspace delete (confirm when the group has gems,
  message for item groups), New / Delete All / Delete buttons, row tooltip =
  `AddSocketGroupTooltip`. Ctrl+V paste, Ctrl+Z / Ctrl+Y undo/redo in the tab.
- Selftest `skills-list` (23 flags): paste, copy text format + round trip,
  link colours, icon, toggles, main, reorder fix-up, delete shift, undo/redo,
  set new/select/copy/rename/move/delete. Confirmed it fails with the
  OnOrderChange call removed (5 flags go false).
- Checked by driving pob-qt under Xvfb with xdotool: hover tooltip, right-click,
  Ctrl+click, drag, Manage popup Copy -> Save, set dropdown, Ctrl+C/V/Z.
- Fixed along the way:
  - `BuildModel` and `SocketGroupModel` marshalled the raw `socketGroupList`;
    on a calculated build that walks the calc env through each group and ran
    to ~8 GB (pob-qt hung on any build with skills). Both now read
    `pob_getSocketGroups()`.
  - Old `SkillModel` (only used by the old Skills view; ran one BuildOutput
    per skill on every skillsChanged) is no longer instantiated.
  - `TextInputPopup` content overflowed its dialog (width -> implicitWidth).
  - A ConfirmPopup whose `message` is BOUND to a changing selection crashed
    Qt 6.4's layout engine; SetManagePopup sets it when opening instead.
  - Qt's offscreen clipboard segfaults on setText: selftests must not call the
    real `Copy` (pob_skillsCopyGroup has a noClipboard flag).

**Part 5.2 — DONE.**
- Detail panel (legacy geometry, 20px right of the list): label edit, "Socketed
  in" (row tooltip = the live `groupSlot.tooltipFunc` -> AddItemTooltip incl.
  "Removing this item..."), Enabled, Include in Full DPS (shown as
  `includeInFullDPS and enabled`), Count + source note for item/node/explode
  groups (gem rows hidden for them, slot locked), Imbued Support.
  All calls go through the live closures (`groupLabel.changeFunc`,
  `groupSlot.selFunc` incl. the imbued migration, ...). Text edits apply 300 ms
  after the last keystroke or on Enter/blur (legacy: every keystroke).
- Imbued support: `pob_skillsSetImbued` = set `sg.imbuedSupport`,
  `RebuildImbuedSupportBySlot`, then undo (legacy pushes undo BEFORE the
  change). One per slot: another group in the slot locks the selector.
- `components/GemSelect.qml` (built here for the imbued selector; the gem rows
  in 5.3 reuse it). List, matching tiers, :tag/:-tag, S/A filter, DPS sort and
  check/"+" markers come from the live GemSelectControl (`UpdateSortCache`,
  `BuildList`); row hover = lifted Draw tooltip ("Selecting this gem will give
  you:"). Enter = selection else top match; Esc reverts; focus-out keeps an
  exact match else clears. Deviation: no live preview while typing/arrowing.
  First open on OccVortex: 1.5 s (one calc per support that can apply, as in
  legacy); later opens ~5 ms (sortCache keyed on outputRevision).
- Gem Options section: sort-by-DPS + stat, default level (row tooltip =
  description), default quality (clamped 23), show support gems, legacy gems.
  No undo / modFlag / recalc, like legacy.
- Selftest `skills-detail` (22 flags). Confirmed failing with
  RebuildImbuedSupportBySlot removed.
- Shared-component fixes: `CheckBox` label right-aligned (TTF overran into the
  box); `DropDownControl` row tooltips were inside the clipped ListView and
  never showed (also the Tree tab's spec dropdown) — now one tooltip outside
  the list, hidden only by the row that owns it.

**Part 5.3 — DONE.**
- Gem rows in SkillsView (legacy columns: x 0 delete, 22 name, 324 level,
  386 quality, 464 enabled, 502 count, 564 error; headers 18px above; Vaal
  "Enable <effect>:" boxes on a 2nd line, next row 24px lower). The blank last
  row adds a gem. Rows are a COUNT model, so a refresh updates them in place
  and a focused field keeps focus while typing.
- Bridge: `pob_skillsSetGem` (the slot's `gemChangeFunc`; "" = legacy's
  focus-lost delete), `DeleteGem` (`delete.onClick`), `SetGemLevel/Quality/
  Count` (`changeFunc`, clamped by ProcessSocketGroup), `SetGemEnabled`
  (lifted with a nil guard: legacy errors on an unresolved gem),
  `SetGemGlobal`, `GemQualityTooltip` / `GemEnabledTooltip` (the slots'
  `tooltipFunc`). Count tooltip is the static legacy text.
- Supporting-gem cross-highlight: `links` per row from the live
  `GemSelectControl:CheckSupporting`, shown while a gem name is hovered.
- "+N from supports": legacy draws no badge; it is in the gem tooltip
  ("Level: 21 (+1)") and the group tooltip, both from the live builders.
- Tab / Shift+Tab walk name -> level -> quality -> count -> next row
  (`activeFocusOnTab` added to EditControl and GemSelect).
- Horizontal (and, when short, vertical) scrollbar like legacy; the page no
  longer pans by dragging.
- Socket-group tooltip builder: `pob_skillsGroupTooltip` (list rows) and the
  existing `pob_getSocketGroupTooltip` (side bar) both call the live
  `SkillsTab:AddSocketGroupTooltip`; the Calcs tab (Phase 8) can reuse either.
- Selftest `skills-gems` (16 flags). Confirmed failing with legacy's missing
  nil check restored.
- Shared fix: `Tooltip` now shows itself in the window's popup overlay
  (mapping coordinates from where it is declared), so no `clip: true`
  ancestor cuts it and it draws above popups. Checked: tree node tooltip,
  popup button tooltip, dropdown rows, all Skills tooltips. Capture diff of
  the other views: only the checkbox-label alignment (and ~115 px noise).

**Part 5.4 — DONE.**
- `<Skills>` save/load is legacy's own `SkillsTab:Save/Load` (a standard
  saver; the host's `bm:SaveDB` already includes it). Selftest
  `skills-persist` (18 flags) proves it through the port:
  - writer: every `skillPart/StageCount/MineCount/Minion/MinionItemSet/
    MinionSkill` field and its `*Calcs` twin, `variantId` of a transfigured gem,
    `<SkillSet title>`;
  - reader: live `LoadSkill` reads all of them back (fed a hand-made node,
    because the calc pass clears values that do not apply to the gem);
  - round trip: 2 sets (titles, active set), group attribs incl. imbued
    support, gem attribs, tab options;
  - a real build (`spec/TestBuilds/3.13/OccVortex.xml`) load -> save -> load ->
    save gives the same `<Skills>`, apart from two UPSTREAM quirks that mean
    the same thing (`includeInFullDPS="nil"` -> `"false"`, Explode group
    `mainActiveSkill="nil"` -> `"1"`);
  - legacy flat `<Skill>` (no `<SkillSet>`; `active=`; skillId-only and
    name-only gems; group-level skillPart) loads into set 1.
- Undo: `CreateUndoState` copies every set (checked by mutating after a
  push), and undo restores both `mainSocketGroup` and the Calcs
  `skill_number`, and a deleted set.

### Acceptance gate — 2026-09-28 (Linux)
- `tools/linux-selftest.sh`: `pob-selftest EXIT=0`, `pob-qt --headless EXIT=0`
  with `skills-list`, `skills-detail`, `skills-gems`, `skills-persist` green.
- Open a build (OccVortex) -> groups, gems, link colours, levels/qualities as
  legacy; the side-bar main-skill selector follows right-click / reorder
  (checked in the running app under Xvfb).
- "ctf" -> Cold to Fire / Chance to Flee (initials tier); DPS order and the
  check/"+" colours come from the live GemSelectControl; hover shows "Selecting
  this gem will give you:".
- Copy -> paste gives an identical group (selftest + in-app Ctrl+C/Ctrl+V).
- Save round trip incl. variantId and `*Calcs` fields (above).
- Captures vs a Linux capture from this session's start: non-Skills views
  0-10 px; Tree 2,111 px = the checkbox-label fix; Skills = the new view. vs the
  committed (Windows) baseline every view differs by font rendering, so the
  Skills/Tree baseline refresh needs Windows.
