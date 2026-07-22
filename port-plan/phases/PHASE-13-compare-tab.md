# Phase 13 — Compare Tab

**Status:** NOT STARTED — SCOPE: **confirm with user before starting.**
**Goal:** Port the Compare tab — side-by-side comparison of the current build
against one or more other builds across six sub-views, with a category-attribution
power report.
**Depends on:** nearly all other tabs (it re-renders tree/skills/items/calcs/config
for two builds), Phase 11 (import as comparison).
**References to load:** [[tabs-catalog]] (Compare tab), and the reference for
whichever sub-view you're working (Calcs → [[calc-engine-contract]], etc.).

## Scope gate (resolve first)

`CompareTab.lua` (4986 lines) **appears to be a fork-specific feature, NOT in
upstream PoB Community**, and is **NOT in the build savers list** — comparison
builds are session-only (no XML persistence). Before investing, confirm with the
user whether Compare (plus its dependencies ExtBuildListControl / PoBArchivesProvider
"PoB Archives", and CompareBuySimilar) are in scope for the port. If dropped, also
remove the Import tab's "import as comparison" mode and the "Similar Builds" path.

## Parts (if in scope)

- [ ] Compare entries: "Compare with" build selector (multiple entries), Import
  popup (code / URL / from-file / folder-browse with search+sort), Re-import
  Current, Remove; per-compare-build set selectors (Tree/Skill/Item/Config) + main-
  skill selector row. (M-L)
- [ ] Six sub-views:
  - **Summary** — side-by-side stat-list diff of all display stats. (M)
  - **Tree** — overlay (green/red/blue on primary viewer) or side-by-side; search
    sync; copy compare spec to primary (incl. jewel comparison spec building). (M)
  - **Skills** — socket-group signature matching + per-gem diffs. (M)
  - **Items** — per-slot compare, compact/expanded inline details, copy to primary,
    abyss/Ring3 handling. (M)
  - **Calcs** — full CalcSections grid for both builds (reuse the Phase 8 resolver),
    per-build skill-detail headers + buff-mode, "show only differences", hover
    breakdown. (M)
  - **Config** — side-by-side config diff with interactive mirrored controls, copy-
    config, show-all. (M)
- [ ] **Compare Power Report** — coroutine attributing stat differences to categories
  (tree nodes / items / skill gems / support gems / config) with progress %,
  sortable list. (M)

## Acceptance gate

- Load a second build for comparison → all six sub-views render correct diffs vs
  the current build (spot-check summary stat deltas, tree overlay, calcs "only
  differences").
- Compare Power Report attributes a known stat difference to the correct category.
- `pob-selftest` compare accessor check green; capture diff clean.

## Notes

- This phase is mostly composition of components/resolvers built in Phases 4–8 —
  keep those reusable across builds/actors and Compare is far less work than its
  line count implies.
- Session-only (no XML) — don't add a savers entry.
