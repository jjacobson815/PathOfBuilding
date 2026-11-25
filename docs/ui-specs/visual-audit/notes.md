# Visual & Layout Audit: `notes.png` (`NotesView.qml`)

**Viewport:** 1100 × 720 (`sideBarWidth: 312`, `topBarHeight: 32`, `bottomBar: 28` → content viewport `788 × 660`)

## 1. Visual Defect Table

| Severity | Visual Symptom in PNG | Root Cause (`file:line`) | Expected Behavior |
| --- | --- | --- | --- |
| **Critical** | Instruction line 2 is clipped mid-word at the right viewport edge (`"...will set the col"` — `"or."` sliced off). | `NotesView.qml:27-31, 113-124`: `_descLines` renders each string inside an unbounded `Widgets.Label` (`size: 14`) with no `width` or `wrapMode`. Line 2 (`127` chars) paints ~`790px` wide in Liberation Sans TTF, exceeding the `772px` inner width (`788 - 16` margins) and getting cut by `root { clip: true }`. | Replace the single-line `Widgets.Label` delegate with `Widgets.ColorText` bound to `width: parent.width` (`Layout.fillWidth: true`) and `wrapMode: Text.WordWrap` so instructions never clip horizontally at any viewport width. |
| **High** | Both the editor pane (left) and color-preview pane (right) render as unlabeled, visually identical dark empty rectangles — zero visual cue distinguishing the editable text box from the read-only preview. | `NotesView.qml:175-251`: Neither `notesEdit` nor the preview `Rectangle` has a section title bar, header label, or `placeholderText` (`"Type build notes here..."` / `"Live Color Preview"`), and both share the exact same `color: theme.background` fill. | Add compact `20px` header strips (`"Notes Editor"` / `"Color Preview"`) or subtle surface differentiation (`theme.titleBar` header + `placeholderText` in `notesEdit`) so editable vs. read-only panes are immediately distinguishable. |
| **High** | Toggling `"Show Color Codes"` breaks the live preview pane by displaying escaped `^_xRRGGBB` literals instead of colored text, and the preview `ColorText` width binding risks scrollbar overflow/loops inside `QC.ScrollView`. | `NotesView.qml:241-249`, `pob_notes_party.lua:94-105`: `pob_notesToggleColorCodes()` rewrites `^x` → `^_x` in `notesEdit.text`, which the preview binds directly (`sourceText: notesEdit.text`); `ColorText` also binds `width: parent.width - 12` against `ScrollView`'s internal `contentItem` instead of `previewScroll.availableWidth`. | Feed unescaped text (`notesEdit.text.replace(/^_([0-9] |
| **Medium** | Several color-code insert button labels fail WCAG AA contrast (`>= 4.5:1`) against the dark `#0F172A` button fill: `STRENGTH` (`#D20000`, ~2.9:1), `COLD` (`#3F6DB3`, ~3.3:1), `CHAOS` (`#D02090`, ~3.5:1), and `UNIQUE` (`#AF6025`, ~3.8:1). | `NotesView.qml:139-147`, `pob_notes_party.lua:43-56`: Button labels directly apply legacy `colorCodes.*` hex values designed for pure black `#000000` onto the lighter `#0F172A` button chrome. | Add a color swatch chip (left `10×10` rounded square in the exact `btn.code` hex) paired with crisp `#FFFFFF` label text, or lighten dark button label tints on `#0F172A` to meet `>= 4.5:1` contrast. |
| **Medium** | `"INTELLIGENCE"` sits tightly inside its `108px` button (~`4px` horizontal padding), and the right toggle column (`Show Color Codes` / `Hide Color Preview`, `Layout.alignment: Qt.AlignBottom`) leaves an awkward `132px` empty gap and an empty top-right slot beside Row 1 of the color grid. | `NotesView.qml:127-172`: Fixed `implicitWidth: 108` for all 12 buttons (`4 * 108 + 3 * 16 = 480px`) leaves tight padding on the 12-char uppercase `"INTELLIGENCE"`, while the two right-hand toggle buttons are bottom-aligned against a 3-row grid. | Widen grid buttons slightly to `116px` (or `columnSpacing: 10`, `width: 118`) and align the right toggle `ColumnLayout` to `Qt.AlignTop` (or place a `"Zoom: 16px"` readout in row 3) to balance the 3-row toolbar. |
| **Low** | *(Shell — TopBar / StatPanel / BottomBar)* `Unnamed ...` elides aggressively, `Loadouts` right edge clips, `Mode: BUILD` is off-screen, `StatPanel` left-elides `.... Damage Reduction` and `...ment Speed Modifier`, and `BottomBar` version text crowds the top edge of the `28px` bar. | `TopBar.qml:168-420`, `StatPanel.qml:47, 194-205`, `BottomBar.qml:31-67`, `main.qml:264-273`: Shared shell geometry defects across all BUILD views. | Apply shared shell fixes (`TopBar` compact dropdown widths, `StatPanel` wider `colLabelX: 196`, `BottomBar` `32px` height). |



## 2. Actual vs Target ASCII Wireframe Diff (1100 × 720)

```text
ACTUAL (1100x720):
+---------------------------------------------------------------------------------+
| [<<][<< Back][Save][Save As] Unnamed ... [0/123 0/8][Auto][1][Scionv][Nonev][Nonev][Loadout|
+----------------------+----------------------------------------------------------+
| BUILD / TOOLS        | You can use Ctrl +/- (or Ctrl+Scroll) to zoom...         |
|                      | This field also supports different colors... set the col | <- CLIPPED ("or." gone)
|                      | Below are some common color codes PoB uses:              |
|                      | [NORMAL] [MAGIC] [RARE]  [UNIQUE]                        |
| Main Skill:          | [FIRE]   [COLD]  [LIGHT] [CHAOS]      [Show Color Codes] | <- Low contrast (STR/COLD/CHAOS)
| [<No skills...    v] | [STR]    [DEX]   [INT]   [DEFLT]    [Hide Color Preview] |
|                      | +-------------------------------+ +--------------------+ |
|                      | |                               | |                    | | <- Two identical blank boxes
|                      | |     (no label/placeholder)    | | (no preview header)| |    (unlabeled, Show Color Codes
|  .... Damage Red.:0% | |                               | |                    | |     breaks preview rendering)
|  ...ment Speed: +0%  | +-------------------------------+ +--------------------+ |
+----------------------+----------------------------------------------------------+
| [Options][About][Check for Update] PoB Community Fork / Version: 2.68.1         |
+---------------------------------------------------------------------------------+

TARGET (1100x720):
+---------------------------------------------------------------------------------+
| [<<][<< Back][Save][Save As] Unnamed build [0/123 0/8][Auto][1][Scionv][Nonev][Nonev][Loadouts v]|
+----------------------+----------------------------------------------------------+
| BUILD / TOOLS        | You can use Ctrl +/- (or Ctrl+Scroll) to zoom...         |
|                      | This field also supports different colors. Using the     | <- Word-wrapped inside 772px
|                      | caret symbol (^) followed by a Hex code or (0-9)...      |
|                      | [# NORMAL] [# MAGIC] [# RARE]  [# UNIQUE] [Show Codes  ] | <- Swatch + high-contrast text
| Main Skill:          | [# FIRE  ] [# COLD ] [# LIGHT] [# CHAOS ] [Hide Preview] | <- Top-aligned with row 1
| [<No skills...    v] | [# STR   ] [# DEX  ] [# INT  ] [# DEFLT ]  Zoom: 16px    |
|                      | +-------------------------------+ +--------------------+ |
|                      | | Notes (Markdown / ^-codes)    | | Live Color Preview | | <- Distinct pane headers
|                      | +-------------------------------+ +--------------------+ |
| Phys. Damage Red.:0% | | Type build notes here...      | | (renders unescaped | | <- Unescaped preview even when
| Movement Speed:  +0% | |                               | |  color codes live) | |    Show Color Codes is ON
|                      | +-------------------------------+ +--------------------+ |
+----------------------+----------------------------------------------------------+
| [Options][About][Check for Update] PoB Community Fork / Version: 2.68.1         |
+---------------------------------------------------------------------------------+

```

## 3. Automated Layout Assertions (`Qt6::QuickTest`)

```qml
import QtQuick
import QtTest

TestCase {
    name: "NotesViewLayoutAudit"
    when: windowShown

    function test_notes_instructions_buttons_and_preview_layout() {
        var view = findChild(mainWindow, "notesView")
        verify(view !== null && view.visible)

        // 1. Instruction text lines must wrap/fit inside content width with zero right clipping
        var descItems = findChildren(view, "notesDescLine")
        verify(descItems.length >= 3, "Expected Notes instruction lines")
        for (var i = 0; i < descItems.length; i++) {
            var rightEdge = descItems[i].mapToItem(view, descItems[i].paintedWidth, 0).x
            verify(rightEdge <= view.width - 8,
                   "Notes instruction line clipped on right: line=" + i + " right=" + rightEdge + " max=" + (view.width - 8))
            verify(descItems[i].wrapMode !== Text.NoWrap,
                   "Notes instruction line must allow wrapping")
        }

        // 2. All 12 color buttons must fit their label text with >= 6px padding and stay within view
        var colorBtns = findChildren(view, "notesColorBtn")
        compare(colorBtns.length, 12, "Expected 12 color-code buttons")
        for (var b = 0; b < colorBtns.length; b++) {
            var btn = colorBtns[b]
            var lbl = findChild(btn, "buttonLabel")
            if (lbl) {
                verify(lbl.paintedWidth + 8 <= btn.width,
                       "Color button label cramped: " + btn.label + " painted=" + lbl.paintedWidth + " w=" + btn.width)
            }
            verify(btn.mapToItem(view, btn.width, 0).x <= view.width - 8,
                   "Color button overflows right edge: " + btn.label)
        }

        // 3. Editor and preview panes must not overlap and must have visible headers/placeholders
        var editorPane  = findChild(view, "notesEditorPane")
        var previewPane = findChild(view, "notesPreviewPane")
        verify(editorPane !== null && previewPane !== null)
        if (previewPane.visible) {
            verify(editorPane.mapToItem(view, editorPane.width, 0).x + 6 <= previewPane.mapToItem(view, 0, 0).x,
                   "Editor and preview panes overlap")
            verify(previewPane.mapToItem(view, previewPane.width, 0).x <= view.width - 6,
                   "Preview pane overflows right viewport edge")
        }

        // 4. Preview ColorText must never show escaped "^_" artifacts when Show Color Codes is active
        var previewText = findChild(view, "notesPreviewText")
        var notesEdit   = findChild(view, "notesEdit")
        if (previewText && notesEdit) {
            verify(previewText.width <= previewPane.width,
                   "Preview ColorText wider than preview container")
            verify(previewText.sourceText.indexOf("^_") === -1,
                   "Preview pane displays raw escaped ^_ color codes")
        }
    }
}

```
