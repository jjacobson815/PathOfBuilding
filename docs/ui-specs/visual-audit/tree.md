# Visual & Layout Audit: `tree.png` (`TreeView.qml`)

## 1. Visual Defect Table

| Severity | Visual Symptom in PNG | Root Cause `file:line` in QML | Expected Behavior |
| --- | --- | --- | --- |
| **Critical** | **`Version:` label collides directly into the `3.30` dropdown border** — the `:` glyph sits on top of the left border stroke of `versionSelect`. | `app/qml/views/TreeView.qml:277-290` uses `Widgets.Label` (`size: 16`) inside `Flow` (`spacing: 6`). `app/qml/components/Label.qml:18` assigns `width: textMetrics.width(16, "VAR", "^7Version:")` (narrower `.tgf` atlas width), which underestimates the `16px` TTF `Liberation Sans` painted width by ~`6px`, causing `":"` to overrun into the adjacent dropdown. | Size `Label` width to `Math.max(textMetrics.width(...), Math.ceil(implicitWidth))` (or use `ColorText` with natural TTF `implicitWidth` in `Flow`/`RowLayout`) and normalize font size to `theme.fontSize` (`14px`). |
| **Critical** | **TopBar right-edge clipping** (`Unnamed ...` truncated, `Loadouts` right edge/caret clipped off-screen, `Mode: BUILD` off-screen) and **Sidebar left-elided stats** (`.... Damage Reduction:`, `...ment Speed Modifier:`). | Shared BUILD shell defects: `app/qml/components/TopBar.qml:244-468` minimum width (`~1,192px`) exceeds `1,100px`; `app/qml/components/StatPanel.qml:43, 179-182` caps labels at `168px` with `ElideLeft`. | Apply the shared `TopBar` width budget and `StatPanel` `colLabelX: 196` fixes so the shell frames the tree cleanly at `1100x720`. |
| **High** | **Bottom tree toolbar wraps onto an orphan 2nd row** (`Show Node Power:` alone on Row 2) and sits nearly touching the overflowing `PoB Community Fork` text below it with no separator line. | `app/qml/views/TreeView.qml:228-365` places 7 controls in `barFlow` totaling `~885px` inside the `788px` (`1100 - 312`) tree width (`specSelect: 190`, `compareCheck: ~92`, `Reset: 145`, `Version: ~58`, `versionSelect: 100`, `Timeless: 150`, `heatCheck: ~150`); `BottomBar.qml:54-66` simultaneously protrudes upward from `main.qml:248`. | Compact Row 1 control widths (`specSelect: 150`, `Reset Tree/Tattoos: 132`, `versionSelect: 78`, `Find Timeless Jewel: 136`) or organize into two intentional, evenly balanced rows separated from both `TreeScene` and `BottomBar` by `1px` `theme.border` dividers. |
| **High** | **Tree search bar occludes the top `~36px` of the passive tree canvas** (passive nodes peek out behind its corners) and its placeholder text has poor contrast on dark navy. | `app/qml/components/TreeViewer.qml:233-246` floats a raw `QtQuick.Controls.TextField` at `z: 50` over `TreeScene` (`anchors.top: parent.top`), sets `border.color: theme.section` (inconsistent cyan outline), and never sets `placeholderTextColor` (defaults to dim low-contrast grey over `theme.sideBarBg`). | Dock the search input as a dedicated `26px` header strip above `TreeScene` (or float it as a compact `320px` top-left pill with clear `x` button), replace raw `TextField` with `Widgets.EditControl`, and ensure placeholder contrast uses `theme.muted`. |
| **Medium** | **Mixed font sizes in the bottom control bar:** `Compare:`, `Version:`, and `Show Node Power:` visibly render larger (`16px`) than `Default`, `Reset Tree/Tattoos`, `3.30`, and `Find Timeless Jewel` (`14px`). | `app/qml/components/CheckBox.qml:67` derives label size as `boxSize - 4` (`20 - 4 = 16px` when `TreeView.qml:264, 305` set `height: 20`), and `TreeView.qml:279` sets `size: 16`, while `Button.qml:44` and `DropDownControl.qml:44` cap text at `theme.fontSize` (`14px`). | Cap `CheckBox` label size at `Math.min(theme.fontSize, Math.max(1, root.boxSize - 4))` and set `Version:` label `size: theme.fontSize` (`14px`) for uniform typography across the strip. |
| **Medium** | **Uneven spacing and left-edge misalignment on `CheckBox` wrappers** (`Compare:` has excess dead space to its left; `Show Node Power:` text hugs `x = 2px` misaligned with `Default` at `x = 4px`). | `app/qml/views/TreeView.qml:258-269, 299-315` manually wrap `CheckBox` in `Item { width: check.labelWidth + 32; x: parent.width - 20 }`, where `labelWidth` uses `.tgf` metrics (`CheckBox.qml:24`) that diverge from TTF painted width by `6–10px` depending on string length. | Compute `CheckBox.labelWidth` from `Math.ceil(labelText.implicitWidth) + 5` (actual TTF width) and size wrapper items tightly to `labelWidth + 20` (no arbitrary `+ 12` left padding). |
| **Low** | **No visual border separates the sidebar from the tree canvas or `TreeView.bottomBar**`, causing the sidebar and tree footer (`theme.sideBarBg`) to merge into an L-shaped slab. | `app/qml/main.qml:120-130` (`sideBar`) and `app/qml/views/TreeView.qml:228-236` (`bottomBar`) omit `1px` `theme.sideBarLine` / `theme.border` separator lines. | Add a `1px` right border (`theme.sideBarLine`) on `sideBar` and a `1px` top border (`theme.border`) on `TreeView`'s `bottomBar`. |



## 2. Actual vs Target ASCII Wireframe Diff (1100x720)

```text
ACTUAL (tree.jpg)                                        TARGET (TreeView.qml + TreeViewer.qml)
+------------------------------------------------------+ +------------------------------------------------------+
|[<<][<< Back][Save][Save As]Unnam.. [0/123 0/8][Au][1]| |[<<][<< Back][Save][Save As] Unnamed build  [0/123 | 0/8]|
|                 [Scion v][None v][None v][Loadout  <CLIP  [Auto][1][Scion v][None v][None v][Loadouts v]     |
+-------------+----------------------------------------+ +-------------+----------------------------------------+
| BUILD       |[Search nodes (dim low-contrast)...    ]| | BUILD       |[Search nodes...                   [x]] |
| |Tree       |   (occludes top passive nodes!)        | | |Tree       +----------------------------------------+
|  Skills..   |                                        | |  Skills..   |                                        |
| Main Skill: |            (Passive Tree)              | | Main Skill: |            (Passive Tree)              |
| [<No skill>]|                                        | | [<No skill>]|           (unoccluded top)             |
| ...         |                                        | | ...         |                                        |
| .... Dmg Re:|                                        | | Phys. Dmg R:|                                        |
| ...ment Spd:|                                        | | Move Speed: |                                        |
|             |[Default v]  Compare:[ ] [Reset..]      | |             +----------------------------------------+
|  (no border)| Version:[3.30 v][Find Timeless Jewel]  | | (1px border)|[Default v] Compare:[ ] [Reset Tree..]  |
|             |         ^":" collides with border!     | |             |Version: [3.30 v] [Find Timeless Jewel] |
|             |Show Node Power:[ ]  <-- orphan row 2   | |             |Show Node Power:[ ]  (14px aligned)     |
+-------------+PoB Community Fork (crowds row 2!)      | +-------------+----------------------------------------+
|[Options][About][Check..]Version: 2.68.1-qt.1 Dev Mode| |[Options][About][Check Update] PoB Community Fork     |
+------------------------------------------------------+ +------------------------------------------------------+

```

## 3. Automated Layout Assertions (`Qt6::QuickTest`)

```qml
// tests/quick/tst_tree_layout.qml
import QtQuick
import QtTest

TestCase {
    name: "TreeViewLayout"
    when: windowShown

    function test_versionLabelDoesNotOverlapDropdown() {
        const treeView = findChild(rootWindow, "treeView")
        const verLabel = findChild(treeView, "versionLabel")
        const verDrop = findChild(treeView, "versionSelect")

        // Painted TTF text must fit within label box and leave >= 4px gap before dropdown
        verify(verLabel.paintedWidth <= verLabel.width + 0.5,
               "Version label paintedWidth (" + verLabel.paintedWidth + ") > width (" + verLabel.width + ")")
        const lblRight = verLabel.mapToItem(treeView, verLabel.paintedWidth, 0).x
        const dropLeft = verDrop.mapToItem(treeView, 0, 0).x
        verify(lblRight <= dropLeft - 4,
               "Version: text collides with versionSelect border (" + lblRight + " vs " + dropLeft + ")")
    }

    function test_bottomBarTypographyAndCheckBoxAlignment() {
        const treeView = findChild(rootWindow, "treeView")
        const specDrop = findChild(treeView, "specSelect")
        const compareCheck = findChild(treeView, "compareCheck")
        const heatCheck = findChild(treeView, "heatCheck")
        const verLabel = findChild(treeView, "versionLabel")

        // Uniform 14px control bar font size
        compare(verLabel.font.pixelSize, theme.fontSize)
        compare(findChild(compareCheck, "labelText").font.pixelSize, theme.fontSize)
        compare(findChild(heatCheck, "labelText").font.pixelSize, theme.fontSize)

        // CheckBox labels must not clip past left edge or collide with their boxes
        for (const cb of [compareCheck, heatCheck]) {
            const lbl = findChild(cb, "labelText")
            const lblRect = lbl.mapToItem(treeView, 0, 0)
            const boxRect = cb.mapToItem(treeView, 0, 0)
            verify(lblRect.x >= 4, cb.objectName + " label clipped past left margin: x=" + lblRect.x)
            verify(lblRect.x + lbl.paintedWidth <= boxRect.x - 4,
                   cb.objectName + " label collides with checkbox")
        }

        // Bottom bar must stay strictly above BottomBar's version stack
        const treeBar = findChild(treeView, "bottomBar")
        const appBottomBar = findChild(rootWindow, "bottomBarRow")
        const treeBarBottom = treeBar.mapToItem(rootWindow.contentItem, 0, treeBar.height).y
        const appBarTop = appBottomBar.mapToItem(rootWindow.contentItem, 0, 0).y
        verify(treeBarBottom <= appBarTop, "Tree bottomBar overlaps app bottomBarRow")
    }

    function test_searchBarDoesNotOccludeSceneAndContrastOk() {
        const viewer = findChild(rootWindow, "treeViewer")
        const search = findChild(viewer, "treeSearch")
        const scene = findChild(viewer, "sceneGraph")

        // Docked search bar must sit above TreeScene rather than overlapping its top band
        const searchBottom = search.mapToItem(viewer, 0, search.height).y
        const sceneTop = scene.mapToItem(viewer, 0, 0).y
        verify(searchBottom <= sceneTop, "treeSearch occludes top of TreeScene")

        // Search placeholder/text contrast check against background
        verify(theme.contrastOk(search.color, theme.sideBarBg), "Search text fails WCAG AA")
    }
}

```
