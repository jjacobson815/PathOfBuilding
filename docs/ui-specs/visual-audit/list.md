# Visual & Layout Audit: `list.png` (`BuildListPage.qml`)

## 1. Visual Defect Table

| Severity | Visual Symptom in PNG | Root Cause `file:line` in QML | Expected Behavior |
| --- | --- | --- | --- |
| **Critical** | `Build Library`, `New Build`, `Paste build share URL`, and `Builds/folders: 2` sit flush at `x = 0` with zero top, left, or bottom padding; `Builds/folders: 2` sits directly on top of the `Options` button. | `app/qml/views/BuildListPage.qml:20-32` sets `Layout.leftMargin/rightMargin/topMargin/bottomMargin: theme.space3` on a direct child of `StackLayout` (`app/qml/main.qml:106-110, 240-245`), which ignores `Layout.*Margin` on its page children. | Wrap the page's `ColumnLayout` inside an `Item` with `anchors.fill: parent; anchors.margins: theme.space3` so all four edges have a symmetric `12px` inset. |
| **Critical** | `PoB Community Fork` in the bottom bar protrudes above the `28px` footer strip into the page area, and `Version: 2.68.1-qt.1` touches the bottom window pixel (`y = 719`). | `app/qml/main.qml:248-255` caps `bottomBarRow` to `Layout.preferredHeight: 28`, while `app/qml/components/BottomBar.qml:31-35, 54-66` stacks two `12px` `ColorText` lines (`~28px` total painted height) inside a `RowLayout` with `anchors.margins: 4` (`20px` inner height). | Increase `bottomBarRow` height to `34px` (or align the 2-line version stack with `verticalCenter` and `anchors.topMargin/bottomMargin: 2`) and add a `1px` `theme.border` top separator. |
| **High** | Right-hand metadata (`Witch  Lv99`, `Scion  Lv1`) presses directly against `x = 1100` with `0px` right padding, misaligned with `New Folder` and `Import URL` above (`8px` trailing spacer). | `app/qml/views/BuildListPage.qml:120-124` sets only `anchors.leftMargin: theme.space2` on the delegate `RowLayout`, omitting `anchors.rightMargin`, while toolbars rely on ad-hoc trailing spacers (`BuildListPage.qml:87, 106`). | Remove the ad-hoc toolbar spacers once the page wrapper provides uniform `12px` margins, and add `anchors.rightMargin: theme.space2` to the list delegate `RowLayout`. |
| **High** | `New folder name` and `Paste build share URL` inputs render as unthemed flat grey `QtQuick.Controls.TextField`s (~`28px` tall) that clash vertically and visually with the `20px` `Widgets.Button` controls beside them. | `app/qml/views/BuildListPage.qml:72-77, 92-97` use raw `TextField` instead of `Widgets.EditControl`, while adjacent buttons pin `implicitHeight: 20` (`BuildListPage.qml:55-86, 98-105`). | Replace both `TextField`s with `Widgets.EditControl` (`Layout.preferredHeight: 24`) and standardize toolbar button heights to `24px` (`theme.controlSize` / `implicitHeight: 24`). |
| **High** | `Dev Mode` renders in pure `#FF0000` red against dark navy (`~3.8:1` contrast, failing WCAG AA `4.5:1`), and `Check for Update` remains permanently disabled despite Phase 14.2 update checking being implemented. | `app/qml/components/BottomBar.qml:67-72` hardcodes `^1` (palette `#FF0000` in `ColorText.cpp:9`), overriding `defaultColor: theme.danger` (`#EF4444`); `BottomBar.qml:47-53` pins `controlEnabled: false`. | Remove the `^1` escape so `theme.danger` (or a brighter `#F87171` token) applies with `>= 4.5:1` contrast, and wire `Check for Update` to `pob_checkForUpdates`. |
| **Medium** | Zebra striping on the build list is completely invisible (`OccVortex` and `~~temp~~` share the exact same background), and clicking a row draws an opaque sharp-cornered delegate `Rectangle` over the rounded `ListView.highlight`. | `app/qml/views/BuildListPage.qml:115, 119` paints `index % 2 ? theme.sideBarBg : "transparent"`, but `app/src/Theme.cpp:69` aliases `m_background = m_sideBarBg` (identical color); line 119 also paints `theme.accent` redundantly over `highlight`. | Use a distinct subtle tint (e.g. `Qt.rgba(1, 1, 1, 0.03)` or `theme.titleBar`) for alternating rows, remove duplicate selection fill in favor of `highlight`, and frame `buildListView` in a `1px` `theme.border` box with `Widgets.ScrollBar`. |
| **Medium** | `Build Library` header (`size: 20`) clips/crowds descender space (`y` in `Library`), and `OccVortex` displays base class `Witch Lv99` instead of ascendancy (`Occultist`) while toolbar lacks Sort / Search / Copy / Rename / Breadcrumb parity controls. | `app/qml/views/BuildListPage.qml:50-53` uses `Widgets.Label` which hardcodes `height: root.size` (`app/qml/components/Label.qml:19`) shorter than TTF ascent+descent; `BuildListPage.qml:134-136` ignores `model.ascendClassName` (`app/src/BuildListModel.cpp:25, 42`). | Use `height: Math.ceil(implicitHeight)` on `Label` (or `ColorText` for headings) and display `model.ascendClassName |



## 2. Actual vs Target ASCII Wireframe Diff (1100x720)

```text
ACTUAL (list.png)                                        TARGET (BuildListPage.qml)
+------------------------------------------------------+ +------------------------------------------------------+
|                                           Mode: LIST | |                                           Mode: LIST |
+------------------------------------------------------+ +------------------------------------------------------+
|Build Library   <-- x=0, y=32 (0px margin!)           | |  (12px page padding via wrapper Item)                |
|[New Build][Open][Delete]    [New folder name][New F.]| |  Build Library                                       |
|                             ^28px grey TextField     | |  [New Build] [Open] [Delete]   [New folder ][New Fld]|
|[Paste build share URL                   ][Import URL]| |  [Paste build share URL                  ][Import URL]|
| OccVortex                                 Witch Lv99|| |  +------------------------------------------------+  |
| ~~temp~~                                   Scion Lv1|| |  | OccVortex                      Occultist Lv99  |  |
|  (no border, invisible zebra, right-clipped metadata)| |  | ~~temp~~                           Scion Lv1   |  |
|                                                      | |  | (bordered list, subtle zebra, ScrollBar)       |  |
|                                                      | |  +------------------------------------------------+  |
|Builds/folders: 2        PoB Community Fork <--bleeds!| |  Builds/folders: 2                                   |
|[Options][About][Check..]Version: 2.68.1-qt.1 Dev Mode| +------------------------------------------------------+
+------------------------------------------------------+ | [Options][About][Check Update] PoB Community Fork    |
                                                         |                                Version: 2.68.1-qt.1  |
                                                         +------------------------------------------------------+

```

## 3. Automated Layout Assertions (`Qt6::QuickTest`)

```qml
// tests/quick/tst_buildlist_layout.qml
import QtQuick
import QtTest

TestCase {
    name: "BuildListPageLayout"
    when: windowShown

    function test_pageMarginsAndRightEdgeClearance() {
        const win = rootWindow // 1100x720
        const page = findChild(win, "buildListPage")
        const header = findChild(page, "buildLibraryHeader")
        const list = findChild(page, "buildListView")
        const footer = findChild(page, "buildCountLabel")
        const bottomBar = findChild(win, "bottomBarRow")

        // Page must maintain >= 12px inset from all edges despite StackLayout host
        const headerPos = header.mapToItem(win.contentItem, 0, 0)
        verify(headerPos.x >= 12, "Header flush with left edge: x=" + headerPos.x)
        verify(headerPos.y >= topBar.height + 12, "Header flush with topBar: y=" + headerPos.y)

        // Footer count must not touch or overlap bottomBarRow
        const footerBottom = footer.mapToItem(win.contentItem, 0, footer.height).y
        const barTop = bottomBar.mapToItem(win.contentItem, 0, 0).y
        verify(footerBottom <= barTop - 8, "Footer count crowds bottom bar")

        // ListView metadata right edge must stay >= 12px + 8px inside window right edge
        if (list.count > 0) {
            const row0 = list.itemAtIndex(0)
            const meta = findChild(row0, "buildRowMeta")
            verify(meta.paintedWidth <= meta.width, "Row metadata text overflow")
            const metaRight = meta.mapToItem(win.contentItem, meta.width, 0).x
            verify(metaRight <= win.width - 20, "Row metadata jammed to right edge: x=" + metaRight)
        }
    }

    function test_toolbarControlHeightParityAndNoClipping() {
        const folderEdit = findChild(rootWindow, "folderNameField")
        const folderBtn = findChild(rootWindow, "newFolderButton")
        const importEdit = findChild(rootWindow, "importUrlField")
        const importBtn = findChild(rootWindow, "importUrlButton")

        // Controls on the same row must have matching heights and non-overlapping boxes
        compare(Math.abs(folderEdit.height - folderBtn.height) <= 2, true)
        compare(Math.abs(importEdit.height - importBtn.height) <= 2, true)
        verify(folderEdit.mapToItem(null, folderEdit.width, 0).x < folderBtn.mapToItem(null, 0, 0).x)
        verify(importEdit.mapToItem(null, importEdit.width, 0).x < importBtn.mapToItem(null, 0, 0).x)
    }

    function test_bottomBarContainedInStrip() {
        const bar = findChild(rootWindow, "bottomBarRow")
        const forkLabel = findChild(bar, "bottomForkLabel")
        const verLabel = findChild(bar, "bottomVersionLabel")
        const devLabel = findChild(bar, "bottomDevModeLabel")

        const forkTop = forkLabel.mapToItem(bar, 0, 0).y
        const verBottom = verLabel.mapToItem(bar, 0, verLabel.height).y
        verify(forkTop >= 0, "PoB Community Fork protrudes above bottomBarRow: y=" + forkTop)
        verify(verBottom <= bar.height, "Version label clipped below bottomBarRow: y=" + verBottom)
        if (devLabel.visible) {
            verify(theme.contrastOk(devLabel.color, bar.color), "Dev Mode fails WCAG AA contrast")
        }
    }
}

```
