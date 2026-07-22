# Phase 3 — Build Shell (top bar, side bar, stat panel, warnings)

**Status:** NOT STARTED
**Goal:** Build the frame that every tab lives inside: the top bar (save/save-as/
back, class & ascendancy dropdowns, loadouts, points/level), the side bar (tab
strip + hotkeys, main-skill selector stack, spectre library, live stat panel,
warnings), and the build XML save/load orchestration. After this the app can open,
edit at the shell level, and save a real build with correct denormalized stats.
**Depends on:** Phase 1 (components), Phase 2 (stat panel + warnings read calc output).
**References to load:** [[tabs-catalog]] (Build mode shell section — the checklist),
[[core-lifecycle]] (save/load, savers, lifecycle), [[calc-engine-contract]]
(stat panel + BuildDisplayStats).

## Why here

The shell frames all tabs and owns save/load. It needs Phase 2's output marshalling
(stat panel, warnings) and the compare bridge (top-bar tooltips). Do it before the
individual tabs so they have a home and the save format is correct.

## Part 3.1 — Top bar

- [ ] Left: `<< Back` (unsaved prompt via Phase 1 popup), **Save**, **Save As**
  (folder-browser popup + New Folder + filename sanitization
  `[\\/:%*%?"<>|%c]`), build-name display (relocates to sidebar on narrow screens). (M)
- [ ] Right: points display (used/max asc/max) with tooltip (req level, act
  estimate via `EstimatePlayerProgress`, quest points, lab); auto/manual level
  toggle + level edit (1-100) with XP-mult tooltip. (M)
- [ ] **Class / Ascendancy / Secondary-ascendancy dropdowns** with tree-reset
  confirm popup (incl. "Connect Path" third option); legacy alt-ascendancy filtering. (M)
- [ ] **Loadouts dropdown** — `SyncLoadouts`: build entries by matching Tree/Item/
  Skill/Config set titles exactly or by `{tag}`; selecting swaps all four active
  sets at once; "New Loadout" (creates identically-named spec+itemSet+skillSet+
  configSet), "Sync", "Help". (M — depends on all four set systems existing; the
  set-management UIs land in their tab phases, so wire Loadouts incrementally or
  gate its full function until Items/Skills/Config tabs exist.)

## Part 3.2 — Side bar

- [ ] Tab strip from the `viewList` registry (already the sanctioned host seam) +
  hotkeys: Ctrl+1..7 (Tree/Skills/Items/Calcs/Config/Notes/Party), Ctrl+I import,
  Ctrl+S save, Ctrl+W/MOUSE4 close-with-prompt; collapse toggle (`sideBarCollapsed`). (S-M)
- [ ] **Main-skill selector stack** (refreshed each recalc): socket-group dropdown
  (full socket-group tooltip), active-skill dropdown, skill-part dropdown, stage-
  count edit, mine-count edit, minion dropdown (also lists item sets for Animate
  Guardian; drag-equip target), minion-skill dropdown, "Manage Spectres" button. (M)
- [ ] **Spectre Library popup** — dual-pane searchable source/destination minion
  lists with drag between panes; saves `spectreList`. (M)
- [ ] **Stat panel** — `TextListControl`-style, built from `BuildDisplayStats.lua`
  (playerDisplayStats, minionDisplayStats, extraSaveStats) over the Phase 2
  marshalled output: per-stat fmt/color/condFunc/warnFunc/overCap, FullDPS skill
  rows, minion section, skill-disabled reason, info messages. (M)
- [ ] **Warnings** — "N Warnings" with tooltip list: too many passive/asc points,
  insufficient Life/Mana/Rage/ES for costs, unreserved pool %, Vixen's, multiple
  Aspects, jewel limit exceeded, socket gem-count, missing anoints. (S-M)

## Part 3.3 — Build XML orchestration & lifecycle

- [ ] Savers registry (`Config,Notes,Party,Tree,TreeView,Items,Skills,Calcs,Import`
  + legacy `Spec`) with the **Tree-deferred load order** then `PostLoad`. (M —
  bridge exists via `pob_getBuildXML`/`pob_loadBuildXML`; verify order + section
  round-trip.)
- [ ] `<Build>` attribs + **denormalized `<PlayerStat>/<MinionStat>/<FullDPSSkill>`**
  from `calcsTab.mainOutput` on save — **saving must run after a completed calc
  pass** or third-party sites lose stats. `<Spectre>`, `<TimelessData>`. (M)
- [ ] Version-conversion popup for old builds (`targetVersion != liveTargetVersion`). (S)
- [ ] `unsaved` = OR of all tab `modFlag`s → unsaved indicator + `CanExit` save
  prompt (Save / Don't Save / Cancel). Dev autosave to `~~temp~~.xml` on shutdown
  (dev-mode only). (S)

## Acceptance gate

- Open a real legacy build XML → shell shows correct name/class/ascendancy/level/
  points; stat panel matches legacy numbers; warnings match.
- Change class/ascendancy → tree-reset confirm works; loadout swap changes sets.
- Save → produced XML round-trips through legacy PoB **and** contains correct
  `<PlayerStat>/<FullDPSSkill>` (diff against a legacy-saved copy of the same build).
- Save-As into a new folder works; unsaved prompt fires on close.
- `pob-selftest` green; capture diff clean.

## Notes

- The stat panel and warnings are the first real consumers of Phase 2 — if numbers
  are wrong here, fix the marshalling, not the panel.
- Loadouts fully works only once all four set-management UIs exist; it's fine to
  ship a partial Loadouts here and complete it after Phase 7.
- Save-requires-calc-output is a subtle interop trap — gate `SaveDBFile` on a
  fresh `BuildOutput` (legacy does this implicitly via the frame loop).
