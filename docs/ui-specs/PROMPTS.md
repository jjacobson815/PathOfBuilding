# Offload Prompts for UI Specs, Wireframes & Bug Audits (NotebookLM & Gemini Desktop)

All prompts below are designed as **single-paste self-advancing loops** — paste a prompt **once**, and if Gemini Desktop or NotebookLM pauses for response length, just reply `next` until the queue reaches 100%.

Every file block is wrapped in visible `=== BEGIN FILE: ... ===` / `=== END FILE: ... ===` markers (NotebookLM strips HTML comments on copy, so visible markers are used — and `split-ui-specs.ps1` also auto-detects `UI Spec:` headings as a fallback): just copy the AI's reply and run `.\tools\split-ui-specs.ps1 -FromClipboard` to save every spec directly into `docs/ui-specs/`.

---

## Quick Workflow

1. **Generate the 8 Markdown packs + companion screenshots:**
   ```powershell
   .\tools\repomix-ui-docs.ps1
   ```
2. **Upload sources:**
   - **NotebookLM:** Create notebook **`PoB-Qt UI Specs`**, upload `docs/repomix-packs/00-*.md` .. `07-*.md` + `docs/ui-specs/SPEC-TEMPLATE.md`.
   - **Gemini Desktop (visual critique):** Attach `docs/ui-specs/SPEC-TEMPLATE.md`, the relevant pack `.md` file(s), and the screenshots from `docs/repomix-packs/screenshots/`.
3. **Run any loop prompt below (paste ONCE, then reply `next` until done).**
4. **Auto-save outputs into `docs/ui-specs/`:**
   Copy the model's response to your clipboard and run:
   ```powershell
   .\tools\split-ui-specs.ps1 -FromClipboard
   ```
   *(Or save responses to a `.txt`/`.md` file and run `.\tools\split-ui-specs.ps1 -InputFile <path>`.)*

---

## Prompt 1 — All Views + App Shell Loop (1 Paste -> All 11 View Specs & ASCII Wireframes)

Use in **NotebookLM** (with all 8 packs + `SPEC-TEMPLATE.md` loaded) or **Gemini Desktop**.

```text
Goal: Produce a complete, untruncated UI specification and lightweight wireframe mock-up for EVERY view in the ordered queue below, using ONLY the uploaded PoB-Qt repomix packs and `SPEC-TEMPLATE.md`.

Queue (11 files total):
1.  app/qml/main.qml                      -> docs/ui-specs/views/MainShell.md
2.  app/qml/views/BuildListPage.qml       -> docs/ui-specs/views/BuildListPage.md
3.  app/qml/views/ImportView.qml          -> docs/ui-specs/views/ImportView.md
4.  app/qml/views/TreeView.qml            -> docs/ui-specs/views/TreeView.md
5.  app/qml/views/SkillsView.qml          -> docs/ui-specs/views/SkillsView.md
6.  app/qml/views/ItemsView.qml           -> docs/ui-specs/views/ItemsView.md
7.  app/qml/views/ConfigView.qml          -> docs/ui-specs/views/ConfigView.md
8.  app/qml/views/CalcsView.qml           -> docs/ui-specs/views/CalcsView.md
9.  app/qml/views/NotesView.qml           -> docs/ui-specs/views/NotesView.md
10. app/qml/views/PartyView.qml           -> docs/ui-specs/views/PartyView.md
11. app/qml/views/PlaceholderView.qml     -> docs/ui-specs/views/PlaceholderView.md

Loop Execution Protocol:
- Process items strictly in order starting at #1.
- Output as many COMPLETE, untruncated specs as fit comfortably in this turn (typically 2-3 views per turn). NEVER abbreviate, skip sections, or say "same as above".
- Wrap each spec in exact visible file markers (NOT HTML comments) so my script can auto-save it:
  === BEGIN FILE: docs/ui-specs/views/<Name>.md ===
  ...full Markdown following SPEC-TEMPLATE.md Sections 1-6...
  === END FILE: docs/ui-specs/views/<Name>.md ===
- End every turn with a single status footer:
  `LOOP STATUS: [X/11 done] | Next: #<N> <File> (reply "next" to continue)`
- When I reply `next` or `continue`, immediately emit the next batch with zero preamble until 11/11 are done.

Per-Spec Rules:
1. Follow `SPEC-TEMPLATE.md` Sections 1-6 strictly (keep `Status: Draft` until reviewed).
2. Keep wireframes lightweight: fixed-width ASCII box wireframes (1100x720 layout) + a concise Mermaid `flowchart TD` hierarchy. Do NOT emit HTML/CSS.
3. Assign a stable `objectName` (`pob.<view>.<control>`) to EVERY interactive control (buttons, dropdowns, checkboxes, text inputs, lists, popups).
4. Cite exact `file` + symbol/id/property name (e.g., `TopBar.qml (loadoutDrop)`) rather than repomix line offsets. Distinguish intentional UX improvements from bugs; never normalize a bug into expected behavior. Never put raw `|` or `||` characters inside Markdown table cells (write `or` in prose so table rows do not break).
5. Explicitly audit each view and its child controls in Section 6 (Bug Audit Findings) for:
   - `Array.isArray(...)` used on Lua `QVariantList` bridge values (returns `false` in Qt6 QML -> empty dropdowns/lists)
   - Text overflow / clipped labels / hardcoded button widths / oversized fonts missing `elide: Text.ElideRight` + hover tooltip fallback
   - `ScrollView` content exceeding `availableWidth`
   - `Keys.on*` attached directly to `PopupBase`/`Dialog` roots
   - Shadowed default `property ... data` or unguarded `.length` on empty Lua tables (`QVariantMap`, where `.length` is `undefined`)
   - Dropdowns/controls stuck disabled or stale after a Lua mutation
   - Missing Tab/Enter/Esc handling or missing disabled-state tooltips
6. In Section 5, write concrete `Qt6::QuickTest` Acceptance Criteria (`AC-01`..`AC-N`) testable via `objectName`, clicks, typing, dropdown selection, and layout/overflow checks.

Start now with item #1.
```

---

## Prompt 2 — All 75 Components Loop (1 Paste -> Complete Component Library Specs & Anatomy Wireframes)

Use in **NotebookLM** (click **Refresh / Clear chat** first to start a fresh thread after Prompt 1 — your 9 uploaded sources stay intact). Kept compact (~2,000 chars) to stay well under NotebookLM's chat input limit.

```text
Goal: Using ONLY the uploaded PoB-Qt repomix packs and `SPEC-TEMPLATE.md`, write a complete, untruncated UI spec + ASCII anatomy wireframe for EVERY component below (75 total).

Queue (target path for each: `docs/ui-specs/components/<Name>.md`):
A(1-9): TopBar, BottomBar, StatPanel, MainSkillPanel, WarningsBar, UpdateBanner, Toast, ToastStack, Chrome
B(10-25): Button, DropDownControl, EditControl, CheckBox, Slider, ScrollBar, Tooltip, Label, ColorText, Arrow, CheckMark, RectangleOutline, Section, PathControl, TextListControl, HoverKeyArea
C(26-32): SearchHost, UndoHandler, Dragger, DragSource, DragGhost, DropTarget, PopupButton
D(33-44): PopupBase, ConfirmPopup, MessagePopup, TextInputPopup, NewFolderPopup, SaveAsPopup, OptionsDialog, AboutPopup, ConversionPopup, SetManagePopup, LoadoutManagePopup, SpectreLibraryPopup
E(45-52): TreeViewer, SpecManagePopup, TreeImportPopup, TreeExportPopup, MasteryPopup, TattooPopup, TimelessJewelPopup, PowerReportPanel
F(53-54): SocketGroupList, GemSelect
G(55-70): ItemListBox, ItemDBPanel, ItemAffixRow, ItemTextPopup, CraftPopupBase, CraftNewPopup, CraftEnchantPopup, CraftAnointPopup, CraftCorruptPopup, CraftImplicitPopup, CraftCustomPopup, CraftCruciblePopup, CraftButton, CraftDrop, CraftEdit, CraftLabel
H(71-75): ConfigOptionRow, CalcSectionCard, CalcBreakdownPanel, CalcRadiusVisual, PartyBufferBox

Loop Protocol:
- Process strictly in order from #1 (4-6 complete components per turn; fewer for huge ones). Never abbreviate or merge files.
- Wrap each component in visible markers (not HTML comments):
  === BEGIN FILE: docs/ui-specs/components/<Name>.md ===
  ...full Markdown following SPEC-TEMPLATE.md Sections 1-6 (Status: Draft)...
  === END FILE: docs/ui-specs/components/<Name>.md ===
- End every turn with: `LOOP STATUS: [X/75 done] | Next: #<N> <Name> (reply "next" to continue)`
- On `next`, resume immediately with zero preamble.

Rules: Include ASCII anatomy (padding/border/elision/popup), full state matrix (default/hover/pressed/focused/disabled/empty/long-text/color-codes), binding hazards, isolated `Qt6::QuickTest` ACs, and Section 6 bugs citing `File (symbol/id)` (no raw `|` or `||` inside table cells). Start at #1.
```

---

## Prompt 3 — All 9 Screenshots Visual Critique Loop (Gemini Desktop — 1 Paste)

Attach **all 9 PNGs** from `docs/repomix-packs/screenshots/` + the relevant pack `.md` files (or upload packs 00–07 together in Gemini Desktop).

```text
Goal: Perform a visual & layout bug critique across ALL 9 attached 1100x720 screenshots of `pob-qt` by cross-referencing each PNG against the attached QML + Lua packs.

Queue (9 views):
1. list.png   -> BuildListPage.qml
2. import.png -> ImportView.qml
3. tree.png   -> TreeView.qml
4. skills.png -> SkillsView.qml
5. items.png  -> ItemsView.qml
6. config.png -> ConfigView.qml
7. calcs.png  -> CalcsView.qml
8. notes.png  -> NotesView.qml
9. party.png  -> PartyView.qml

Loop Execution Protocol:
- Emit 3 views per turn wrapped in visible markers (NOT HTML comments):
  === BEGIN FILE: docs/ui-specs/visual-audit/<view>.md ===
  ...report...
  === END FILE: docs/ui-specs/visual-audit/<view>.md ===
- End each turn with: `LOOP STATUS: [X/9 done] | Next: #<N> <view>.png (reply "next" to continue)`

For EACH screenshot, output:
1. **Visual Defect Table** (Severity | Visual Symptom in PNG | Root Cause `file:line` in QML | Expected Behavior): call out every text overflow, clipped/cramped button, missing/empty dropdown label, column collision, unreadable contrast, or layout imbalance.
2. **Actual vs Target ASCII Wireframe Diff** (compact 1100x720 box wireframe showing what to fix).
3. **Automated Layout Assertions**: exact bounding-box / `paintedWidth <= width` / `elide` / non-overlap assertions for `Qt6::QuickTest` so these defects cannot regress.

Start now with #1 (`list.png`).
```

---

## Prompt 4 — Full-App Master Bug vs Expected-Behavior Triage (NotebookLM — Single Turn)

Run once in NotebookLM with all 8 packs loaded to produce a single authoritative `docs/ui-specs/BUG-TRIAGE.md`.

```text
Goal: Cross-reference ALL 8 uploaded PoB-Qt UI packs (`00-shell-and-theme.md` through `07-view-notes-party.md`) against `tabs-catalog.md`, `control-library.md`, and the phase specs to establish what is expected behavior vs what is a bug across all 86 QML files.

Wrap the entire output in visible markers (NOT HTML comments):
=== BEGIN FILE: docs/ui-specs/BUG-TRIAGE.md ===
...
=== END FILE: docs/ui-specs/BUG-TRIAGE.md ===

Include exactly three tables:
1. **Confirmed Bugs in Current QML/Bridge Code**
   Columns: `ID | Severity | View/Component | File:Line | Bug Class | User-Visible Symptom | Expected Behavior | Suggested Qt6::QuickTest Case`
   Specifically hunt for:
   - `Array.isArray` on `QVariantList` bridge values
   - Empty Lua tables marshalled as `QVariantMap` (`length === undefined`)
   - Dropdowns/lists whose models or `enabled` bindings can silently stay empty/stale
   - Fixed pixel widths or font-size formulas causing text overflow/clipping
   - Unwired callbacks, dead buttons, or missing error/disabled tooltips
   - Broken keyboard shortcuts / modal dialog `Keys` / focus traps
2. **Intentional UX Deviations (NOT Bugs)**
   Columns: `View/Component | Legacy PoB Behavior | Qt Port Behavior | Source Citation`
3. **Missing / Deferred Features vs `tabs-catalog.md`**
   Columns: `Feature | View | Status (Deferred v1.1 / Dropped / Accidental Gap) | Source Citation`

Cite exact `file:line` for every row. Never guess; mark anything unverifiable as `[Unconfirmed]`.
```

---

## Prompt 5 — Returning to Antigravity: Batch Spec-to-Test Loop (1 Paste)

Once your specs are saved in `docs/ui-specs/`, paste this **once** in a fresh Antigravity session to build `Qt6::QuickTest` coverage across a group of specs in a single autonomous run (use `/goal` if you want it to run through all specs without stopping).

### Model & Effort
- **Surface:** Antigravity App
- **Agent:** Main Agent
- **Primary:** **Orchestrator (Neon)** (`Medium`–`High`) — plans test architecture/shared helpers in Neon and executes per-spec `objectName` hooks & QML `TestCase` files in Hydrogen.
- **Low-Quota Fallback:** **Claude Sonnet 5.5** (`High`) or **Orchestrator (Claude Opus 5.5 + Sonnet 5.5)**

### Quota & Scope Rationale
Looping over pinned specs in `docs/ui-specs/` mixes light architecture (shared fixtures/mocks) with repetitive QML test wiring; Orchestrator (Neon) keeps mechanical per-view test authoring on Hydrogen while preserving escalation to Neon if a real bridge bug surfaces.

### Copy-Paste Prompt
```text
/goal
Implement automated Qt6::QuickTest UI coverage for all specs currently saved under `docs/ui-specs/<views|components>/` (starting with `<spec-glob-or-all>`).

Spec scope: Read ONLY the target spec files in `docs/ui-specs/`, their corresponding `app/qml/` files, `docs/ui-specs/BUG-TRIAGE.md` (if present), and `app/tests/ui/UiTestHelper.h`; skip unrelated views and already-loaded rule files (AGENTS.md / GEMINI.md).

Objective (iterate through every spec in scope without skipping):
1. Add the stable `objectName` selectors (`pob.<scope>.<control>`) defined in Section 3 of each spec to its `.qml` file.
2. Fix any Confirmed Bugs in Section 6 that block the spec's Acceptance Criteria (without modifying `src/` calc logic or emulating SimpleGraphic globals).
3. Create or update `app/tests/ui/<views|components>/tst_<name>.qml` covering every `AC-01`..`AC-N` in Section 5, including Zero-Warning and multi-resolution Layout/Overflow oracle checks (`960x640`, `1100x720`, `1600x900`).
4. Update `docs/ui-specs/<views|components>/<Name>.md` status to `Test-Covered` once its suite passes.

Verification (run fresh after final edit; apply verification-before-completion):
- `python tools/lint_qml.py`
- `PATH="/c/msys64/mingw64/bin:$PATH" ninja -C build-win pob-ui-test pob-qt`
- `cd src && PATH="/c/msys64/mingw64/bin:$PATH" QT_FORCE_STDERR_LOGGING=1 ../build-win/pob-ui-test.exe -input ../app/tests/ui`
- `cd src && PATH="/c/msys64/mingw64/bin:$PATH" QT_FORCE_STDERR_LOGGING=1 ../build-win/pob-selftest.exe "$PWD" "$PWD/../runtime" "$PWD/../app/lua/pob_host.lua"`

Escalation: STOP after 2 consecutive failures on the same verification gate and escalate to neon-architect / Gemini 4 Neon with exact commands and verbatim stderr.
```
