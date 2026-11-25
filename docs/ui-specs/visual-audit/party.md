# Visual & Layout Audit: `party.png` (`PartyView.qml` & `PartyBufferBox.qml`)

**Viewport:** 1100 × 720 (`sideBarWidth: 312`, `topBarHeight: 32`, `bottomBar: 28` → content viewport `788 × 660`)

## 1. Visual Defect Table

| Severity | Visual Symptom in PNG | Root Cause (`file:line`) | Expected Behavior |
| --- | --- | --- | --- |
| **Critical** | **`"Clear"` button is 100% clipped off-screen**, **`"Rebuild All"` is sliced to `"Rebu"**`, and **instruction lines 1–2 are cut off mid-word** (`"...Export support" e`, `"...your curses wil"`). | `PartyView.qml:72-98, 130-203`: The viewport (`788px`) is split 50/50 into two `380px` `QC.ScrollView`s with `clip: true`. Inside the left `ScrollView`, the child `ColumnLayout` binds `width: Math.max(300, parent.width - 8)`, where `parent` is `ScrollView.contentItem` (a `Flickable` whose `contentWidth` expands to the widest child). Because `_descLines` uses unbounded single-line `Widgets.Label` (~`590px` wide), `ColumnLayout` inflates to `~590px`, tricking both `Flow` toolbars into laying out controls horizontally (`160+8+120+8+78+8+120 = 502px` and `150+8+150+8+120 = 436px`) instead of wrapping at `380px` — pushing `Clear` completely out of view and chopping `Rebuild All` at `x = 380`. | Hoist the 3 instruction lines and import controls into a **full-width top header** (`772px`, above the 2-column buffer split) with `ColorText { wrapMode: Text.WordWrap }`, AND bind each `ScrollView`'s `contentWidth: availableWidth` + `ColumnLayout.width: leftScroll.availableWidth` so `Flow`s and buffers wrap cleanly inside their visible pane with zero horizontal clipping. |
| **Critical** | **`"Show Advanced Info"` has its leading `'S'` sliced off on the left (`"how Advanced Info"`).** | `PartyView.qml:176-187`: The wrapper `Item` sets `width: advCheck.labelWidth + 24` with `advCheck { anchors.right: parent.right }`. Because `CheckBox.labelWidth` is measured with legacy `.tgf` `TextMetrics` (~10–15% narrower than Qt's rendered Liberation Sans TTF), the right-anchored checkbox draws its left-side label past `x < 0` into `ScrollView { clip: true }`. (The same bug lurks on `appendCheck` at `PartyView.qml:152-161`.) | Measure checkbox wrapper width from actual painted/implicit width (`advCheck.implicitWidth` or `Math.ceil(advCheck.labelWidth * 1.18) + 28`), or fix `CheckBox.qml` to size itself using Qt's own `Text.implicitWidth` so left-aligned labels never spill past `x < 0`. |
| **High** | `importDetail` validation label (`"Code is valid"` / `"Invalid code"`) has only `44px` of room left in the `380px` column and will clip immediately once the user pastes a code. | `PartyView.qml:105-128`: `importCodeIn` hardcodes `Layout.preferredWidth: 328` inside a `380px` column, leaving `380 - 328 - 8 = 44px` for `importDetail` (`Widgets.Label`, `size: 16`, no wrap/elide). | Moving the import bar into the full-width top header (`772px`) gives `importCodeIn` (`360px`) and `importDetail` (`~400px` with `elide: Text.ElideRight`) ample room without clipping. |
| **High** | Summary buffer lines in `PartyBufferBox` will also clip horizontally on any non-empty import (aura/curse/enemy mod descriptions wider than `380px`). | `PartyBufferBox.qml:92-104`: Summary `Repeater` renders single-line `Widgets.Label` (`size: 14`) with no `width` or `wrapMode` inside `ScrollView { clip: true }`. | Replace summary `Widgets.Label` with `Widgets.ColorText` bound to `width: parent.width` and `wrapMode: Text.WordWrap`. |
| **Medium** | Severe layout imbalance & missing visual hierarchy: right column (`Enemy Conditions`, `Enemy Modifiers`, `Curses`) starts flush at `y = 0` beside the left column's instructions, `Enemy Conditions` shows a raw dashed fallback `"---------------------------"` while all other empty sections show bare unboxed headings (`Auras`, `Warcry Skills`, `Link Skills`, `Enemy Modifiers`, `Curses`), and `importCodeIn` has no placeholder text. | `PartyView.qml:72-289`, `PartyBufferBox.qml:31, 92-104`: Two-column `RowLayout` starts at `y = 0` instead of below the header; summary mode renders raw text without `Section`/card containers or muted empty-state text (`"None"`), and `PartyView.qml:258` hardcodes `"^7---------------------------\n"`. | Place the 2-column buffer grid below the full-width import header; wrap each `PartyBufferBox` in a `Widgets.Section` (or subtle bordered card) with consistent muted `"^8(None)"` empty-state text instead of raw dashes, and add `placeholder: "Paste PoB export code or URL..."` to `importCodeIn`. |
| **Low** | Disabled `Import` button has low text contrast (`#64748B` on `#0F172A`, ~3.5:1); shared `TopBar` (`Unnamed ...`, clipped `Loadouts`, off-screen `Mode: BUILD`), `StatPanel` left-elision, and `BottomBar` vertical cramping persist. | `PartyView.qml:142-150`, `TopBar.qml:168-420`, `StatPanel.qml:47, 194-205`, `BottomBar.qml:31-67`. | Raise disabled button contrast to `>= 4.5:1` and apply shared shell fixes. |



## 2. Actual vs Target ASCII Wireframe Diff (1100 × 720)

```text
ACTUAL (1100x720):
+---------------------------------------------------------------------------------+
| [<<][<< Back][Save][Save As] Unnamed ... [0/123 0/8][Auto][1][Scionv][Nonev][Nonev][Loadout|
+----------------------+----------------------------+-----------------------------+
| BUILD / TOOLS        | To import a build..." e    | Enemy Conditions            | <- Line 1 CLIPPED! Right col starts at y=0
|                      | Auras with the... wil      | --------------------------- | <- Line 2 CLIPPED! Raw dashed line
|                      | All of these effects...    | Enemy Modifiers             |
|                      | Enter a build code/URL:    | Curses                      |
| Main Skill:          | [                        ] |                             | <- Only 44px left for importDetail
| [<No skills...    v] | [All       v][Import]App[ ]| ([Clear] 100% OFF-SCREEN!)  | <- Flow didn't wrap! Clear GONE
|                      | how Advanced Info[ ][Disab]|[Rebu (CLIPPED!)]            | <- 'S' clipped left, "Rebuild All" clipped right
|                      | Auras                      |                             |
|                      | Warcry Skills              |                             |
|  .... Damage Red.:0% | Link Skills                |   (550px empty void)        |
|  ...ment Speed: +0%  |                            |                             |
+----------------------+----------------------------+-----------------------------+
| [Options][About][Check for Update] PoB Community Fork / Version: 2.68.1         |
+---------------------------------------------------------------------------------+

TARGET (1100x720):
+---------------------------------------------------------------------------------+
| [<<][<< Back][Save][Save As] Unnamed build [0/123 0/8][Auto][1][Scionv][Nonev][Nonev][Loadouts v]|
+----------------------+----------------------------------------------------------+
| BUILD / TOOLS        | To import a build it must be exported with "Export       | <- Full-width wrapped header (772px)
|                      | support" enabled in the import/export tab. ...           |
|                      | Enter a build code/URL below:                            |
| Main Skill:          | [Paste PoB export code or URL...    ]  (Status / detail) | <- Full room for importDetail
| [<No skills...    v] | [All         v] [Import]  Append [ ]  [Clear]            | <- All 4 controls fit cleanly
|                      | Show Advanced Info [ ]  [Disable Party Effects] [Rebuild]| <- Full 'S', full "Rebuild All"
|                      +----------------------------+-----------------------------+
|                      | +- Auras ----------------+ | +- Enemy Conditions ------+ | <- Balanced 2-col grid below header
|                      | | (None)                 | | | (None)                  | |    with clear card hierarchy &
|                      | +------------------------+ | +-------------------------+ |    wrapped summary ColorText
| Phys. Damage Red.:0% | +- Warcry Skills --------+ | +- Enemy Modifiers -------+ |
| Movement Speed:  +0% | | (None)                 | | | (None)                  | |
|                      | +- Link Skills ----------+ | +- Curses ----------------+ |
+----------------------+----------------------------+-----------------------------+
| [Options][About][Check for Update] PoB Community Fork / Version: 2.68.1         |
+---------------------------------------------------------------------------------+

```

## 3. Automated Layout Assertions (`Qt6::QuickTest`)

```qml
import QtQuick
import QtTest

TestCase {
    name: "PartyViewLayoutAudit"
    when: windowShown

    function test_party_no_horizontal_clipping_and_all_controls_visible() {
        var view = findChild(mainWindow, "partyView")
        verify(view !== null && view.visible)

        // 1. Instruction lines must wrap and fit completely within their visible container
        var descLines = findChildren(view, "partyDescLine")
        verify(descLines.length >= 3, "Expected Party instruction lines")
        for (var i = 0; i < descLines.length; i++) {
            var lineRight = descLines[i].mapToItem(view, descLines[i].paintedWidth, 0).x
            verify(lineRight <= view.width - 8,
                   "Party instruction line clipped: idx=" + i + " right=" + lineRight + " max=" + (view.width - 8))
        }

        // 2. Every action button (Import, Clear, Disable Party Effects, Rebuild All) must be fully inside view
        var requiredButtons = ["partyImportBtn", "partyClearBtn", "partyDisableBtn", "partyRebuildBtn"]
        for (var b = 0; b < requiredButtons.length; b++) {
            var btn = findChild(view, requiredButtons[b])
            verify(btn !== null && btn.visible, "Missing button: " + requiredButtons[b])
            var tl = btn.mapToItem(view, 0, 0)
            var br = btn.mapToItem(view, btn.width, btn.height)
            verify(tl.x >= 0 && br.x <= view.width,
                   "Button clipped horizontally: " + requiredButtons[b] + " x=[" + tl.x + ", " + br.x + "] viewW=" + view.width)
            verify(tl.y >= 0 && br.y <= view.height,
                   "Button clipped vertically: " + requiredButtons[b])
        }

        // 3. CheckBox labels ("Append", "Show Advanced Info") must not clip on the left (x >= 0 in parent)
        var checks = [findChild(view, "appendCheck"), findChild(view, "advCheck")]
        for (var c = 0; c < checks.length; c++) {
            var cb = checks[c]
            verify(cb !== null && cb.visible)
            var lbl = findChild(cb, "checkBoxLabel")
            if (lbl) {
                var lblLeft = lbl.mapToItem(view, 0, 0).x
                verify(lblLeft >= 8,
                       "CheckBox label clipped on left edge: '" + cb.label + "' x=" + lblLeft)
            }
        }

        // 4. Both ScrollViews must lock contentWidth to availableWidth so Flows wrap instead of overflowing
        var scrolls = [findChild(view, "partyLeftScroll"), findChild(view, "partyRightScroll")]
        for (var s = 0; s < scrolls.length; s++) {
            if (scrolls[s]) {
                verify(scrolls[s].contentWidth <= scrolls[s].availableWidth + 1,
                       "Party ScrollView overflows horizontally: contentW="
                       + scrolls[s].contentWidth + " availW=" + scrolls[s].availableWidth)
            }
        }

        // 5. Left and right buffer columns must never overlap
        var leftCol  = findChild(view, "partyLeftScroll")
        var rightCol = findChild(view, "partyRightScroll")
        if (leftCol && rightCol) {
            verify(leftCol.mapToItem(view, leftCol.width, 0).x + 8 <= rightCol.mapToItem(view, 0, 0).x,
                   "Party left and right columns overlap")
        }
    }
}

```
