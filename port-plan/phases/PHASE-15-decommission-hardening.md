# Phase 15 — SimpleGraphic Decommission & Final Hardening

**Status:** NOT STARTED
**Goal:** Close out the port: formally retire the SimpleGraphic host contract,
remove any dead legacy-update code, do the final performance and parity passes, and
establish the ongoing upstream-sync procedure so the fork doesn't rot each league.
**Depends on:** all prior phases (this is the finish line).
**References to load:** [[00-architecture]], [[host-api-contract]],
[[data-and-assets]] (upstream-sync), [[build-test-packaging]].

## Part 15.1 — Formalize the host contract

- [ ] Declare the SimpleGraphic rendering/input globals **permanently stubbed** and
  document it (in `HOST_CONTRACT.md`): `SetDrawLayer/SetViewport/SetDrawColor/
  DrawImage*/DrawString*/NewImageHandle` never become real; QML owns display.
  Record that any future reuse of legacy Draw code would require full text metrics +
  the `^0`–`^9` palette (external sourcing). (S)
- [ ] Confirm no runtime path can drive the engine into legacy SimpleGraphic-only
  code (Update.exe spawn, `ConExecute("set vid_mode...")`, etc.) — those globals
  stay stubbed/no-op. (S)
- [ ] Remove dead legacy-update code paths if Phase 14 replaced them (or keep them
  inert and documented). (S)

## Part 15.2 — Performance pass

- [ ] Marshalling: eliminate the full `QVariant` deep-copy of the ~3.2k-node tree on
  every `treeChanged` (lazy/dirty views or incremental diffs); stop `pob_getTreeData`
  re-resolving sprites (with per-asset `io.open`) every call. (M)
- [ ] `pob_getActiveSkills` — cache per-skill DPS instead of a full `BuildOutput`
  per display skill per refresh. (S-M)
- [ ] Tree renderer final optimization (persist atlas decode, spatial hitTest index,
  incremental repaint) if not fully done in Phase 4. (M)
- [ ] Profile memory on a long session (per-tree-version accumulation with no
  eviction; GlobalCache Env retention; 51.5 MB GV LUT) — add eviction if needed;
  confirm LuaJIT GC64 on x64. (M)

## Part 15.3 — Full parity QA sweep

- [ ] Walk the entire [[tabs-catalog]] as a parity checklist against legacy — every
  tab, every sub-feature, every keyboard shortcut (global Ctrl+1..7/I/S/W, per-tab
  Ctrl+F/Z/Y/C/V/D, e, F1, F2, MOUSE4/5), responsive layouts (portrait mode, two-
  line tree toolbar, options two-column, top-bar buildName relocation). (L)
- [ ] Calc parity: run the full `busted` suite + TestBuilds snapshots against the
  Qt host; zero numeric drift vs the chosen baseline. (S)
- [ ] Visual parity: pixel-sample key views vs legacy screenshots. (M)
- [ ] Decide the fate of dev-mode-only behaviors (autosave `~~temp~~.xml`, JSON
  import, ModCache regen, devModeAlt tooltips) — port or document as dropped. (S)

## Part 15.4 — Upstream-sync procedure (ongoing)

- [ ] Document + script the per-league sync: pull upstream `src/` (Modules + Data
  atomically), normalize CRLF, re-apply the four sanctioned host seams (viewList,
  sideBarCollapsed, TotalDotDPS, UITheme), regenerate ModCache, run calc-parity.
  Include the `src/Export/` data-refresh note (run legacy Export + bun_extract_file
  against Content.ggpk, copy regenerated Data/TreeData). (M)

## Acceptance gate

- Full parity checklist walked; no missing feature vs legacy (or every gap is an
  explicit, user-agreed drop).
- Full `busted` + TestBuilds parity green; visual parity confirmed.
- No hardcoded paths, no dead scaffolding, no SimpleGraphic-only runtime path.
- Upstream-sync procedure documented and dry-run once.
- The app is a complete, self-updating, cross-checked replacement for legacy PoB.

## Notes

- This phase is where "feature-complete" becomes "done." Resist the urge to declare
  victory at Phase 11 — the parity sweep routinely surfaces the last 10% of micro-
  features (responsive layouts, obscure keyboard shortcuts, dev-mode paths).
- The upstream-sync procedure is what keeps the port alive after the port "ends" —
  without it the fork rots ~quarterly.
