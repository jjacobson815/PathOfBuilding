# Phase 5 — Skills Tab

**Status:** NOT STARTED
**Goal:** Port the skills/gems tab: skill sets, the socket-group list with its
keyboard semantics, the group detail panel, and the dynamic gem rows built on
GemSelectControl (fuzzy matching + live DPS-sorted candidates + compare tooltips).
**Depends on:** Phase 1 (components incl. EditControl/DropDownControl), Phase 2
(GemSelect live compares), Phase 3 (shell main-skill selectors reference this data).
**References to load:** [[tabs-catalog]] (Skills tab), [[control-library]]
(GemSelectControl, SkillListControl), [[calc-engine-contract]] (gem DPS compares).

## Part 5.1 — Skill sets & socket-group list

- [ ] Skill sets: dropdown + Manage popup (generic set-manager: new/copy/delete/
  rename/reorder). (S)
- [ ] Socket-group list (SkillListControl): add/delete/reorder with link-color gem
  string rendering (R-G-B letters) + slot icons; **keyboard semantics**: Ctrl+C/V
  copy/paste socket groups as text (round-trip the "Label:/Slot:/Name lvl/q
  DISABLED count" format), Ctrl+click enable/disable, Ctrl+right-click include/
  exclude FullDPS, right-click set-as-main. Reorder fixes `mainSocketGroup` + calcs
  indices. (M)

## Part 5.2 — Group detail & gem options

- [ ] Group detail panel: label edit, "Socketed in" slot dropdown (with equipped-
  item tooltip), Enabled checkbox, Include-in-FullDPS checkbox, source Count edit,
  **Imbued Support gem selector** (per-slot ExtraSupport + clear; hidden for item-
  provided groups), source note for item/node/explode-provided groups. (M)
- [ ] Gem options panel: sort-by-DPS checkbox + sort-stat dropdown (FullDPS/
  CombinedDPS/Hit/Average/DoT/Bleed/Ignite/Poison/EHP), default gem level dropdown
  (normalMax/corruptedMax/awakenedMax/characterLevel/levelOne), default gem quality,
  show-support-gems dropdown (All/Non-Exceptional/Exceptional), show-legacy-gems. (S)

## Part 5.3 — Gem rows (GemSelectControl)

- [ ] Dynamic gem rows (one per gem, created on demand): delete X, **GemSelect**
  (fuzzy/abbreviation match `FindSkillGem`, sorted-by-DPS dropdown with gem
  tooltips, `:tag`/`:-tag` filters, S/A overlay filters, ENTER/ESC commit/revert,
  supporting-gem cross-highlight), level edit (+N from supports), quality edit
  (tooltip: quality stat lines + "setting to 20 gives you" diff), enabled checkbox
  (enable/disable diff tooltip), count edit (DPS-mult tooltip), error label
  (unrecognized/ambiguous/unsupported), per-Vaal enableGlobal1/2 checkboxes,
  tab-group nav, horizontal scrollbar. (L — GemSelect live compares depend on the
  Phase 2 calculator bridge + the async-calc decision.)
- [ ] Socket-group tooltip builder (`AddSocketGroupTooltip`) reused by side bar +
  Calcs tab. (S)

## Part 5.4 — Persistence

- [ ] `<Skills>` XML round-trip: attribs (activeSkillSet, defaultGemLevel/Quality,
  sortGemsByDPS[Field], showSupportGemTypes, showLegacyGems); `<SkillSet>` →
  `<Skill>` groups → `<Gem>` with full attribs (nameSpec, skillId, gemId/variantId,
  level, quality, enabled, enableGlobal1/2, count, and every `skillPart`/`stageCount`/
  `mineCount`/`minion`/`minionItemSet`/`minionSkill` + their `*Calcs` variants).
  Support **legacy flat `<Skill>`** and legacy gem-name matching. (M)
- [ ] Undo state deep-copies all sets and preserves main-group selection for both
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
