# Visual & Layout Audit: `items.png` (`ItemsView.qml`)

**Viewport:** 1100 × 720 (`sideBarWidth: 312`, `topBarHeight: 32`, `bottomBar: 28` → content viewport `788 × 660`)

## 1. Visual Defect Table

| Severity | Visual Symptom in PNG | Root Cause (`file:line`) | Expected Behavior |
| --- | --- | --- | --- |
| **Critical** | `"All items:"` title collides directly with the left border of the `Sort` button (colon `:` overlaps button chrome). | `ItemsView.qml:322-354`, `ItemListBox.qml:67-73`: `itemList` is `width: 360`; right-anchored button `Row` totals `60+4+100+4+70+4+60 = 302px` (starting at local `x = 58`), while `Label` (`size: 16`, Liberation Sans TTF) paints `"All items:"` ~66px wide (`x: 0..66`). | At least `8px` horizontal clearance between `"All items:"` right edge and `Sort.x` (either widen `itemList`, compact buttons to content-fitted widths, or place buttons on a dedicated sub-toolbar row). |
| **Critical** | `"Body Armour:"` label in Column 1 has the left vertical stem of `'B'` clipped off at the viewport edge. | `ItemsView.qml:204-263`: `dd` sits at fixed `x: 96`; slot `Label` (`size: 16`) anchors `right: dd.left` (`rightMargin: 2`), allowing only `94px`. `"Body Armour:"` paints ~99px wide in TTF, pushing `x` to `-5` where `slotFlick { clip: true }` slices it. | Right-aligned fixed-box `Label` with `width >= 106` (shifting slot dropdowns to `x: 110`, or reducing slot label size to `14px` with `elide: Text.ElideLeft` fallback) so zero glyphs cross `x < 0`. |
| **Critical** | `"This is the list of items that have been added to this buil"` is clipped mid-word (`"buil"` instead of `"build."`) inside the All Items empty-state box. | `ItemListBox.qml:85-95`: `defaultText.split("\n")` renders each line in an unbounded `Label` (`size: 14`) at `x: 6` with no `width` or `wrapMode`. TTF text paints wider than legacy `.tgf` metrics, exceeding `box.width - 8` (`352px`) and clipping at `box { clip: true }`. | Bind each line `Label` (or a single `ColorText`) to `width: box.width - 12` with `wrapMode: Text.WordWrap` so empty-state instructions never clip horizontally. |
| **High** | Column 2 (`itemList`, `dbPanel`, `Delete` button, `Any type` / `Any league` / `Obtainable` / `Anywhere` dropdowns) overflows the `788px` content area by `2px`, clipping right borders; Column 3 (`Craft item...`, `Create custom...`, help text, `Shared items:`) is 100% off-screen at 1100px width. | `ItemsView.qml:157-168, 174, 322-372`: `leftCol` consumes `424px`, `itemList`/`dbPanel` occupy `x: 430..790` (`790 > 788`), and `col3` starts at hardcoded `x: 810` (`contentWidth >= 1170`). The horizontal `ScrollBar` at the bottom is barely visible dark-on-dark. | Compact Column 1 (`width: 392`, dropdowns `276px` at `x: 108`) and Column 2 (`x: 400, width: 376`) so Columns 1 + 2 fit cleanly inside `788px` with `>= 12px` right margin; add a high-contrast horizontal scrollbar or responsive compact toggle to reach Column 3 / `Craft item...` without blind scrolling. |
| **High** | *(Shell — TopBar)* `Unnamed ...` build name elides aggressively, `Loadouts` dropdown is clipped on the right (missing caret), and `Mode: BUILD` is pushed completely off-screen. | `TopBar.qml:168-420`: Sum of `Layout.preferredWidth` + margins + spacing is ~`1187px` in a `1100px` window (`secondaryDrop: 150`, `loadoutDrop: 145`, `ascendDrop: 120`, `classDrop: 95`, plus buttons and `Mode: BUILD`). | Tighten dropdown preferred widths (`class: 84`, `ascend: 104`, `secondary: 112`, `loadout: 116`) or hide/collapse `Mode: BUILD` debug readout in production so all top-bar controls satisfy `x + width <= topBar.width`. |
| **Medium** | *(Shell — Sidebar StatPanel)* `.... Damage Reduction: 0%` and `...ment Speed Modifier: +0%` are left-truncated despite ~75px of unused space on the right. | `StatPanel.qml:47, 194-205`: `colLabelX: 170` caps labels at `168px` (`size: 16`) with `elide: Text.ElideLeft`, while values sit at `x: 174` leaving `x: 225..296` empty. | Shift `colLabelX` to `196` / `colValueX` to `202` (or drop stat row font to `14px`) so standard PoB stat names fit without elision. |
| **Medium** | `dbPanel` shows `"Loading..."` indefinitely on initial capture and uses an asymmetric `y` formula for `reqDrop` (`sortDrop.y + 18 + 11 - 9`). | `ItemDBPanel.qml:112-146`: `dbPanel` relies on `stepTimer` slices after initial render; filter dropdowns span `179 + 2 + 179 = 360px` pushing right border to `x = 790`. | Keep filter widths driven by `(root.width - 2) / 2` so they adapt to `dbPanel.width`, and await DB ready signal in capture/test harness. |
| **Low** | Disabled `Flask 1..5` checkboxes and `"None"` / `"Default"` dropdown labels have poor contrast against `#0F172A`, and `BottomBar` two-line version text presses against the top edge of the `28px` bar. | `ItemsView.qml:236-250`, `BottomBar.qml:31-67`, `main.qml:264-273`: Disabled chrome uses `theme.mutedDark` (`#64748B`, ~3.5:1 on `#0F172A`); `BottomBar` `anchors.margins: 4` leaves `20px` for two `12px` stacked `ColorText` lines. | Raise disabled text/border contrast to `>= 4.5:1` (`#94A3B8` border / `#8B9BB4` text) and increase `bottomBarRow` height to `32px` (or `anchors.margins: 2`). |

## 2. Actual vs Target ASCII Wireframe Diff (1100 × 720)

```text
ACTUAL (1100x720):
+---------------------------------------------------------------------------------+
| [<<][<< Back][Save][Save As] Unnamed ... [0/123 0/8][Auto][1][Scionv][Nonev][Nonev][Loadout| <- CLIPPED (Mode: BUILD off-screen)
+----------------------+-------------------------------+--------------------------+
| BUILD / TOOLS        | Item set: [Default  v][Manage]| All items:[Sort][DelUnu][DelAll][Del| <- COLLISION ("All items:" hits [Sort]) + 2px right clip
|                      | Equipped items: WeaponSet I II| +------------------------+
| Main Skill:          |   Weapon 1: [None          v] | | This is the list of... buil| <- CLIPPED defaultText ("buil")
| [<No skills...    v] | |3ody Armour:[None         v] | |                        |
|                      |   <- 'B' CLIPPED at x=0       | +------------------------+
|  .... Damage Red.:0% |   Flask 1:[ ][None         v] | Import from: [Uniques v] |
|  ...ment Speed: +0%  |   ...                         | [Any slot v][Any type  v| <- Right border clipped at x=790 > 788
|  <- LEFT-ELIDED      | Passive tree:[Default][Manage]| [Loading...             ]| (Col 3 @ x=810 completely off-screen)
+----------------------+-------------------------------+--------------------------+
| [Options][About][Check for Update] PoB Community Fork (cramped 28px bar)        |
+---------------------------------------------------------------------------------+

TARGET (1100x720):
+---------------------------------------------------------------------------------+
| [<<][<< Back][Save][Save As] Unnamed build [0/123 0/8][Auto][1][Scionv][Nonev][Nonev][Loadouts v] |
+----------------------+-------------------------------+--------------------------+
| BUILD / TOOLS        |   Item set: [Default v][Manage]| All items:              |
|                      | Equipped items: WeaponSet I II | [Sort][Del Unused][Del All][Del] |
| Main Skill:          |     Weapon 1: [None        v] | +-----------------------+|
| [<No skills...    v] |  Body Armour: [None        v] | | This is the list of   || <- Wrapped inside box.width - 12
|                      |      Flask 1:[ ][None      v] | | items added to this   ||
| Phys. Damage Red.:0% |      ...                      | | build. ...            ||
| Movement Speed:  +0% | Passive tree: [Default][Manag]| +-----------------------+|
|                      | (x: 0..392, labels x: 0..106) | Import from: [Uniques v]||
|                      |                               | [Any slot v][Any type v]|| <- Fits cleanly in x: 400..776 (<=788)
|                      |                               | [Visible HScroll + Craft]||
+----------------------+-------------------------------+--------------------------+
| [Options][About][Check for Update] PoB Community Fork / Version: 2.68.1 (32px)  |
+---------------------------------------------------------------------------------+
```

## 3. Automated Layout Assertions (`Qt6::QuickTest`)

```qml
import QtQuick
import QtTest

TestCase {
    name: "ItemsViewLayoutAudit"
    when: windowShown

    function test_items_no_overlap_or_clipping() {
        var view = findChild(mainWindow, "itemsView")
        verify(view !== null && view.visible)

        // 1. "All items:" header must not collide with the Sort/Delete action bar
        var itemList = findChild(view, "itemList")
        var titleLbl = findChild(itemList, "listTitleLabel")
        var btnRow   = findChild(view, "itemListButtons")
        var titleRect = titleLbl.mapToItem(view, 0, 0, titleLbl.paintedWidth, titleLbl.height)
        var btnRect   = btnRow.mapToItem(view, 0, 0, btnRow.width, btnRow.height)
        var sameRow   = (titleRect.y < btnRect.y + btnRect.height) && (btnRect.y < titleRect.y + titleRect.height)
        if (sameRow) {
            verify(titleRect.x + titleRect.width + 6 <= btnRect.x,
                   "All items label overlaps action buttons: " + (titleRect.x + titleRect.width) + " vs " + btnRect.x)
        }

        // 2. Column 1 slot labels (including "Body Armour:") must stay >= 0 inside slotFlick
        var slotFlick = findChild(view, "slotFlick")
        var slotLabels = findChildren(slotFlick, "slotRowLabel")
        for (var i = 0; i < slotLabels.length; i++) {
            var lbl = slotLabels[i]
            var leftEdge = lbl.mapToItem(slotFlick, 0, 0).x
            verify(leftEdge >= 0, "Slot label clipped on left: " + lbl.label + " x=" + leftEdge)
            verify(lbl.paintedWidth <= lbl.width + 0.5,
                   "Slot label overflows box: " + lbl.label + " painted=" + lbl.paintedWidth + " w=" + lbl.width)
            verify(!lbl.truncated, "Slot label unexpectedly truncated: " + lbl.label)
        }

        // 3. ItemListBox empty-state defaultText must fit inside box without clipping
        var emptyLabels = findChildren(itemList, "defaultTextLine")
        for (var j = 0; j < emptyLabels.length; j++) {
            verify(emptyLabels[j].paintedWidth <= itemList.width - 12,
                   "Empty state text clipped: painted=" + emptyLabels[j].paintedWidth + " max=" + (itemList.width - 12))
        }

        // 4. Column 2 (itemList + dbPanel) must fit completely inside 788px viewport
        var dbPanel = findChild(view, "dbPanel")
        verify(itemList.x + itemList.width <= view.width,
               "itemList overflows viewport right edge: " + (itemList.x + itemList.width) + " > " + view.width)
        verify(dbPanel.x + dbPanel.width <= view.width,
               "dbPanel overflows viewport right edge: " + (dbPanel.x + dbPanel.width) + " > " + view.width)

        // 5. TopBar children must not overflow window width (1100px)
        var topBar = findChild(mainWindow, "topBar")
        var loadoutDrop = findChild(topBar, "loadoutDrop")
        verify(loadoutDrop.mapToItem(topBar, loadoutDrop.width, 0).x <= topBar.width,
               "TopBar loadoutDrop overflows window right edge")
    }
}
```
