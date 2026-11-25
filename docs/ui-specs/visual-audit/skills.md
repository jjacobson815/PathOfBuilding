# Visual & Layout Audit: `skills.png` (`SkillsView.qml`)

## 1. Visual Defect Table

| Severity | Visual Symptom in PNG | Root Cause `file:line` in QML | Expected Behavior |
| --- | --- | --- | --- |
| **Critical** | **Horizontal scrollbar (`hScroll`) is permanently active on an empty tab** (`~45%` thumb width) despite zero visible content past `x = 380` (`~408px` of blank navy on the right), and its left arrow collides directly with the upward-bleeding `PoB Community Fork` text in `BottomBar`. | `app/qml/views/SkillsView.qml:124` hardcodes `content.implicitWidth: 400 + 564 + 350` (`1314px`) even when `root.detail === null` (`SkillsView.qml:241`), unconditionally triggering `hScroll` (`SkillsView.qml:404-412`) at `1100x720` (`page.width = 788px`); `app/qml/main.qml:248` (`28px`) clips `BottomBar.qml:54-66`. | Compute `content.implicitWidth` dynamically: `root.detail ? (groupDetail.x + 620) : (groupList.x + groupList.width + 20)` so `hScroll` only appears when a selected group actually overflows the viewport, and raise `bottomBarRow` to `34px`. |
| **Critical** | **`Usage Tips:` overflows the `360px` left column by `~45px` into the `groupDetail` column** (`- Ctrl + Right click to include/exclude in FullDPS calculations.` extends past `x = 400`), and its 5 lines are vertically cramped so descenders (`p`, `g`) nearly touch ascenders on the next line. | `app/qml/views/SkillsView.qml:164-176` renders each tip as an unwrapped `Widgets.Label` (`size: 14`) inside an unconstrained `Column` (`spacing: 0`); `app/qml/components/Label.qml:19` pins `height: root.size` (`14px`) shorter than TTF line height, while `groupDetail` starts at `x = 400` (`SkillsView.qml:239`). | Constrain `tips` to `width: 360`, use `Widgets.ColorText` with `width: 360; wrapMode: Text.WordWrap` (natural `implicitHeight`), and set `spacing: 2` so tips stay strictly inside the left column without colliding with `groupDetail`. |
| **Critical** | **Shared BUILD shell regressions:** `TopBar` clips `Unnamed ...`, truncates the right edge/caret of `Loadouts`, and pushes `Mode: BUILD` off-screen; `StatPanel` left-elides `.... Damage Reduction:` and `...ment Speed Modifier:`. | `app/qml/components/TopBar.qml:244-468` minimum width (`~1,192px`) exceeds `1,100px`; `app/qml/components/StatPanel.qml:43, 179-182` caps stat labels at `168px` with `ElideLeft`. | Apply the shared `TopBar` width budget and widen `StatPanel` `colLabelX` to `196` (`colValueX: 200`). |
| **High** | **`Skill set:` label juts `~6px` left of the `x = 20` column margin** (misaligned with `Socket Groups:` and `Gem Options`), renders larger (`16px`) than adjacent `Default` / `Manage...` (`14px`), and its `:` sits `2px` from `setSelect`'s border. | `app/qml/views/SkillsView.qml:128-140` anchors `Skill set:` (`size: 16`) with `anchors.rightMargin: 2` to `setSelect` at fixed `x: 76` (`74 - ~60px = ~14px < 20px`), while `DropDownControl` (`size: 14`) and `Button` (`_labelSize: 14`) use `theme.fontSize`. | Align `Skill set:` at `x: 20` (`size: theme.fontSize`), place `setSelect` at `x: skillSetLabel.x + skillSetLabel.implicitWidth + 6`, and size `setSelect` so `Manage...` still aligns flush with `x = 380`. |
| **High** | **`Delete All` button text is cramped against its left/right borders** (`~2–3px` side clearance inside `width: 70; height: 18`), and the `p` descender in `Socket Groups:` nearly touches the top border of the socket-group list box (`box.y: 20`). | `app/qml/components/SocketGroupList.qml:68-89` uses `size: 16` at `y: 2` (`2 + 16 = 18px` plus TTF descender overhang reaching `y = 20`) and pins `Delete All` to `width: 70; height: 18`, overriding `Button.qml:49`'s `horizontalPadding: 10` auto-width. | Increase header strip height to `24px` (`box.y: 24`), set header label `size: theme.fontSize` (`14px`), raise button height to `20px`, and widen `Delete All` to `84px` (or let `implicitWidth` size it). |
| **Medium** | **`Gem Options` `Section` floating title plate hugs/clips the `p` descender and `s` right edge**, and the 5 controls inside `Gem Options` are positioned by brittle sibling magic offsets (`opts`) with `16px` labels mixed against `14px` dropdown/input text. | `app/qml/components/Section.qml:27-44` sizes `labelPlate` to `height: 18` and `width: labelText.width + 10` (`.tgf` width < TTF width); `app/qml/views/SkillsView.qml:179-235` declares `opts` outside `Section` at `y: groupList.y + 20 + 300 + 45` with `size: 16` labels (`199, 211, 222`) and `CheckBox` `20 - 4 = 16px` (`CheckBox.qml:67`). | Size `Section.labelPlate` using `Math.ceil(labelText.implicitWidth) + 12` and `height: 20`, parent `opts` directly inside `Section` via a `GridLayout`, and standardize all option labels to `theme.fontSize` (`14px`). |
| **Medium** | **No empty-state guidance in either the `Socket Groups:` list or the right-hand detail pane** when a build has 0 socket groups — leaving `~65%` of the tab blank dark navy. | `app/qml/components/SocketGroupList.qml:88-119` renders an empty bordered box when `count === 0`, and `app/qml/views/SkillsView.qml:241` hides `groupDetail` with no placeholder. | Show a muted centered hint inside `SocketGroupList` (`"No socket groups — click New or press Ctrl+V to paste"`) and a subtle prompt in the right pane when `root.detail === null`. |



## 2. Actual vs Target ASCII Wireframe Diff (1100x720)

```text
ACTUAL (skills.png)                                      TARGET (SkillsView.qml)
+------------------------------------------------------+ +------------------------------------------------------+
|[<<][<< Back][Save][Save As]Unnam.. [0/123 0/8][Au][1]| |[<<][<< Back][Save][Save As] Unnamed build  [0/123 | 0/8]|
|                 [Scion v][None v][None v][Loadout  <CLIP  [Auto][1][Scion v][None v][None v][Loadouts v]     |
+-------------+----------------------------------------+ +-------------+----------------------------------------+
| BUILD       |Skill set:[Default       v][Manage...]  | | BUILD       | Skill set: [Default     v][Manage...]  |
| |Skills     | ^x=14 (misaligned left of x=20!)       | | |Skills     | Socket Groups:   [New][Delete All][Del]|
|  Items..    | Socket Groups:  [New][Delete Al][Del]  | |  Items..    | +-------------------+ +--------------+ |
|             | +-------------------+ ^cramped 70px    | |             | | (Click New or     | | Select or    | |
| Main Skill: | |                   |                  | | Main Skill: | |  Ctrl+V to add    | | create a     | |
| [<No skill>]| |  (blank box)      |  (blank 408px    | | [<No skill>]| |  socket group)    | | socket group | |
|             | |                   |   dead space)    | |             | |                   | | to edit gems | |
| Avg Dmg:0.1 | +-------------------+                  | | Avg Dmg:0.1 | +-------------------+ +--------------+ |
| ...         | Usage Tips:                            | | ...         | Usage Tips:                            |
| .... Dmg Re:| - Ctrl+Right click... FullDPS calculations. | Phys. Dmg R:| - Ctrl + Right click to include/       |
| ...ment Spd:| +-Gem Options-------+  ^overruns x=400!| | Move Speed: |   exclude in FullDPS calculations.     |
|             | |Sort gems by DPS:[v][Combined DPS v]  | |             | +-[ Gem Options ]---+                  |
|             | | (16px labels vs 14px control text)   | |             | | Sort gems by DPS: [v][Combined DPS v]|
|             | +-------------------+                  | |             | | Default gem level: [Normal Max    v] |
|             |[<=========== hScroll (always on!) ===>]| |             | +-------------------+ (no idle hScroll)|
+-------------+PoB Community Fork (collides w/ hScroll)| +-------------+----------------------------------------+
|[Options][About][Check..]Version: 2.68.1-qt.1 Dev Mode| |[Options][About][Check Update] PoB Community Fork     |
+------------------------------------------------------+ +------------------------------------------------------+

```

## 3. Automated Layout Assertions (`Qt6::QuickTest`)

```qml
// tests/quick/tst_skills_layout.qml
import QtQuick
import QtTest

TestCase {
    name: "SkillsViewLayout"
    when: windowShown

    function test_emptyStateHidesHorizontalScrollbar() {
        const view = findChild(rootWindow, "skillsView")
        const hScroll = findChild(view, "hScroll")
        const groupList = findChild(view, "groupList")

        if (groupList.count === 0) {
            compare(hScroll.visible, false, "Horizontal scrollbar should not show when detail pane is hidden")
        }
    }

    function test_usageTipsStayWithinLeftColumnAndDoNotCollideWithDetail() {
        const view = findChild(rootWindow, "skillsView")
        const groupList = findChild(view, "groupList")
        const tipsCol = findChild(view, "usageTipsColumn")
        const detail = findChild(view, "groupDetail")

        const listRight = groupList.mapToItem(view, groupList.width, 0).x
        const detailLeft = detail.mapToItem(view, 0, 0).x
        const tipItems = tipsCol.children

        for (let i = 0; i < tipItems.length; i++) {
            const item = tipItems[i]
            if (!item.visible || item.paintedWidth === undefined) continue
            verify(item.paintedWidth <= groupList.width,
                   "Usage tip overflows left column width (" + item.paintedWidth + " > " + groupList.width + ")")
            const tipRight = item.mapToItem(view, item.paintedWidth, 0).x
            verify(tipRight <= listRight + 1, "Tip overruns SocketGroupList right edge: x=" + tipRight)
            verify(tipRight < detailLeft - 8, "Tip collides with groupDetail column (" + tipRight + " vs " + detailLeft + ")")
        }
    }

    function test_leftColumnAlignmentAndHeaderButtonPadding() {
        const view = findChild(rootWindow, "skillsView")
        const skillSetLbl = findChild(view, "skillSetLabel")
        const setSelect = findChild(view, "setSelect")
        const groupList = findChild(view, "groupList")
        const groupsLbl = findChild(groupList, "socketGroupsLabel")
        const groupsBox = findChild(groupList, "socketGroupsBox")
        const deleteAllBtn = findChild(groupList, "deleteAllButton")
        const deleteAllText = findChild(deleteAllBtn, "labelText")

        // Left margin consistency across Skill set: and Socket Groups:
        compare(Math.round(skillSetLbl.mapToItem(view, 0, 0).x),
                Math.round(groupList.mapToItem(view, 0, 0).x))
        verify(skillSetLbl.mapToItem(view, skillSetLbl.paintedWidth, 0).x <= setSelect.mapToItem(view, 0, 0).x - 4,
               "Skill set: label crowds setSelect border")

        // Socket Groups: header must not touch list box border; Delete All must have >= 6px side padding
        verify(groupsLbl.y + groupsLbl.paintedHeight <= groupsBox.y - 2,
               "Socket Groups: descender collides with list border")
        verify(deleteAllText.paintedWidth <= deleteAllBtn.width - 12,
               "Delete All label cramped: paintedWidth=" + deleteAllText.paintedWidth + ", btnWidth=" + deleteAllBtn.width)
    }

    function test_gemOptionsSectionLabelPlateAndUniformFontSize() {
        const view = findChild(rootWindow, "skillsView")
        const section = findChild(view, "gemOptionsSection")
        const plate = findChild(section, "labelPlate")
        const plateText = findChild(plate, "labelText")

        verify(plateText.paintedWidth <= plate.width - 8,
               "Section title plate too narrow for TTF text: " + plateText.paintedWidth + " vs " + plate.width)
        verify(plateText.paintedHeight <= plate.height - 4,
               "Section title plate clips descenders vertically")

        for (const name of ["defaultLevelLabel", "defaultQualityLabel", "supportTypesLabel"]) {
            const lbl = findChild(view, name)
            compare(lbl.font.pixelSize, theme.fontSize, name + " font size mismatch")
        }
    }
}

```
