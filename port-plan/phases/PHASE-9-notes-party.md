# Phase 9 — Notes & Party Tabs

**Status:** NOT STARTED
**Goal:** Two smaller tabs. Notes = a rich color-code text editor. Party = importing
support-character buffs into the calc env. Grouped because both are self-contained
and neither is huge.
**Depends on:** Phase 1 (EditControl, color-code renderer), Phase 2 (Party feeds
`enemyModList`/buff exports), Phase 3 (shell).
**References to load:** [[tabs-catalog]] (Notes tab, Party tab),
[[calc-engine-contract]] (party buffExports seam), [[core-lifecycle]]
(import code/URL handling — the offline decode path).

## Part 9.1 — Notes tab (S)

- [ ] Full-tab rich EditControl (16pt, tab/newline allowed), Ctrl+Z/Y undo/redo,
  Ctrl +/-/0 zoom.
- [ ] 13 color-code insert buttons (NORMAL/MAGIC/RARE/UNIQUE/FIRE/COLD/LIGHTNING/
  CHAOS/STR/DEX/INT/DEFAULT) inserting `^x`/`^n` at caret or wrapping selection;
  **Show/Hide Color Codes** toggle (escapes codes for literal editing).
- [ ] `<Notes>` XML = raw text; modFlag = text differs from last saved.

## Part 9.2 — Party tab (M)

- [ ] Import code/URL box (same site handling as Import — offline decode works now;
  URL fetch needs Phase 10), destination dropdown (All / Party Member Stats / Aura /
  Curse / Warcry / Link / EnemyConditions / EnemyMods), Import button, Append
  checkbox, Clear, **Show Advanced Info** (editable raw text boxes vs summary
  labels), **Disable Party Effects**, **Rebuild All**.
- [ ] Seven data buffers (Party Stats / Auras / Warcry / Link / Enemy Conditions /
  Enemy Mods / Curses), each with advanced EditControl + summary label; focus-driven
  dynamic sizing.
- [ ] `ParseBuffs` → ModLists (aura priority by highest effect, curse-limit handling,
  Vaal split, link Parent→PartyMember actor rewrite). Export side (`setBuffExports`/
  `exportBuffs`) invoked when this build is exported with "Export Support" enabled
  (the checkbox lives on the Import tab — wire it in Phase 11).
- [ ] `<Party>` XML: destination/append/ShowAdvanceTools; `<ImportedBuffs>` text
  buffers; `<ExportedBuffs>` from last calc.

## Acceptance gate

- Notes: type + color-code a note; toggle show-codes; zoom; save → `<Notes>` round-
  trips; colors render correctly in the display.
- Party: paste a party export → buffs parse into the correct destination; stat
  panel reflects the party buffs (verify a support aura raises the main character's
  effect); Disable Party Effects removes them; save → `<Party>` round-trips.
- `pob-selftest` misc-tabs check green (already covers notes/party accessors);
  capture diff clean.

## Notes

- Party depends on the Phase 2 buffExports seam audit being done — if Party was
  stubbed there, un-stub it here.
- Party import from a URL (not just a pasted code) needs Phase 10 network; the
  paste-a-code path is fully offline.
