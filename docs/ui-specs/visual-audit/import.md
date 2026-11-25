# Visual & Layout Audit: `import.png` (`ImportView.qml`)

## 1. Visual Defect Table

| Severity | Visual Symptom in PNG | Root Cause `file:line` in QML | Expected Behavior |
| --- | --- | --- | --- |
| **Critical** | **Three dropdowns render completely blank** with no selected label: `Realm:` (Step 1), `League:` (Step 2), and `Upload to:` (Share card) display only an empty box and caret. | `app/qml/views/ImportView.qml:76-81, 93-95, 107-113` assign `model` and `currentIndex` back-to-back in a single-shot `_applyState(s)` on controls without declarative `model:` bindings (`ImportView.qml:295-303, 460-469, 678-687`). `app/qml/components/DropDownControl.qml:57-61` gates `currentItem` on `count`, which can lag behind `onModelChanged` (same timing hazard documented at `DropDownControl.qml:87-88`). | Make `DropDownControl.currentItem` read `(model && model.length !== undefined && currentIndex >= 0 && currentIndex < model.length)` directly (and re-evaluate on `modelChanged`), bind `model:` declaratively from `root.st` in `ImportView.qml`, and add sensible `placeholder` defaults (`"PC"`, `"All"`, `"pobb.in"`). |
| **Critical** | **TopBar overflows `1100px` right edge:** `Unnamed build` is crushed to `Unnamed ...`, the right half and caret of `Loadouts` are clipped past `x = 1100`, and `Mode: BUILD` is pushed 100% off-screen. | `app/qml/components/TopBar.qml:244-468` lays out 14 items with fixed widths (`levelEdit: 50`, `classDrop: 95`, `ascendDrop: 120`, `secondaryDrop: 150`, `loadoutDrop: 145`, `Mode: BUILD ~92`) plus `13 * 8px` spacing (`~1,192px` minimum > `1,100px` window). | Remove `Mode: BUILD` debug readout in BUILD mode (or gate on `devMode` in `BottomBar`), tighten `spacing: theme.space1` (`4px`), and slim `ascendDrop` (`105px`), `secondaryDrop` (`115px`), and `loadoutDrop` (`115px`) so all controls fit cleanly within `1100px` with `>= 100px` for `namePlate`. |
| **Critical** | **Sidebar stat labels are truncated on the left** (`.... Damage Reduction: 0%` and `...ment Speed Modifier: +0%`) while `~100px` sits unused to the right of the value column. | `app/qml/components/StatPanel.qml:43, 179-182` hardcode `colLabelX: 170` (`width: 168`) and `elide: Text.ElideLeft` with `size: 16` TTF `Liberation Sans`, whose rendered width (`~185px`) exceeds `168px`. | Shift `colLabelX` to `196` and `colValueX` to `200` (or compute dynamically from `root.width - 108`, preserving `~94px` for values + scrollbar), eliminating left-elision on standard PoB stat names. |
| **High** | **Six instructional hints and disabled reasons are truncated with `...**` across both columns (`Follow the steps below...`, `Creates a new build...`, `Generate a build code...`, `Include auras... Party t...`, `Paste a build share code...`, `Click Generate Code...`). | `app/qml/views/ImportView.qml:162-182` (`InlineHint`) defaults to `maxLines: 1`, `wrapMode: Text.NoWrap`, `elide: Text.ElideRight` (used at `264-267, 550-555, 639-642, 781-785`), and line `709` caps `exportPartyDescription` to `maxLines: 2` which still truncates at the right column's `~280px` inner width. | Allow `InlineHint` descriptions and disabled reasons to wrap cleanly (`wrapMode: Text.WordWrap`, no `maximumLineCount` cap) so users can read instructions and disabled reasons without hovering every line. |
| **High** | **Cramped dropdowns truncate labels/placeholders:** Step 2 `Character:` shows `Fetch charact...` and Open card mode selector shows `Open as a new build...` (cutting off `(default)`). | `app/qml/views/ImportView.qml:451-486` shares one row among `League:` + `leagueDrop(115)` + `Character:` + `charDrop` (`~130px` left); `ImportView.qml:619` weights the right column at `10/22` (`~342px`), leaving `openModeDrop` only `~165px` next to `Open as New Build` (`ImportView.qml:753-778`). | Stack `League:` and `Character:` onto a 2-column `GridLayout` (or widen `charDrop` by narrowing `leagueDrop` to `95px`), and place `openModeDrop` and `Open as New Build` on stacked rows or equalize column weights (`11/11`) with a concise button label (`"Open Build"`). |
| **Medium** | **Step 3 `Destination:` buttons wrap unevenly:** `Overwrite current build` drops onto a second line flush-left beneath `Destination:`, leaving an awkward gap beside `New build (default)`. | `app/qml/views/ImportView.qml:525-548` puts `Destination:` + two wide buttons (`~396px` combined) inside a `Flow` inside a `~378px` card body. | Put `Destination:` as a compact label above a single `RowLayout` of two equal-width toggle buttons (`"New build (default)"` and `"Overwrite current"`), keeping both options on one aligned row. |
| **Medium** | **`pointsPlate` (`0 / 123 0 / 8`) collapses internal spacing and sits off-center left** inside its border; `BottomBar` `PoB Community Fork` overflows vertically; negative resistance `-60%` values have low contrast on `#0F172A`. | `app/qml/components/TopBar.qml:337-363` passes `"^7  0 / 123   ^70 / 8"` through `ColorText` (`Text.StyledText` HTML collapses spaces while `TextMetrics` in `Label.qml:18` measures full spaces); `BottomBar.qml:54-66` overflows `main.qml:248`; `StatPanel.qml` renders `^xDD0022` on `#0F172A`. | Replace runs of spaces with `&nbsp;` in `ColorText.cpp:htmlEscape` (or render passive/ascendancy point counters as two separate labels), fix `BottomBar` height (`34px`), and raise negative stat red luminance for dark theme readability. |
| **Low** | Disabled buttons (`Copy`, `Import as New Build`, `Open as New Build`) blend into the `theme.titleBar` card surface with weak boundary contrast. | `app/qml/views/ImportView.qml:273, 591, 631, 725` use `color: theme.titleBar` for cards while disabled `Chrome.qml:25-31` paints `theme.disabled` (`#141822`) with thin `theme.border`. | Differentiate disabled button border/fill contrast against `theme.titleBar` cards or use slightly elevated card fill (`theme.sideBarBg`) with `1px` `theme.borderStrong` on interactive actions. |



## 2. Actual vs Target ASCII Wireframe Diff (1100x720)

```text
ACTUAL (import.png)                                      TARGET (ImportView.qml + Shell)
+------------------------------------------------------+ +------------------------------------------------------+
|[<<][<< Back][Save][Save As]Unnam.. [0/123 0/8][Au][1]| |[<<][<< Back][Save][Save As] Unnamed build  [0/123 | 0/8]|
|                 [Scion v][None v][None v][Loadout  <CLIP  [Auto][1][Scion v][None v][None v][Loadouts v]     |
+-------------+------------------------+---------------+ +-------------+------------------------+---------------+
| BUILD       | Import a Character     | Share this..  | | BUILD       | Import a Character     | Share this    |
|  Tree..     | Follow the steps...    | Generate a b..| |  Tree..     | Follow the steps below | Generate a    |
| TOOLS       | +--------------------+ | [Gen][Copy]   | | TOOLS       | to bring a character.. | build code..  |
| |Import     | |1. Connect Realm:[ v]| | [Click Ge...]| | |Import     | +--------------------+ | [Gen][Copy]   |
|             | |[Sign in][Account]  | | Up:[     v][S]| |             | |1. Connect Realm[PCv]| | [Code output] |
| Main Skill: | |[Authorize w/ PoE]  | | [] Export..t..| | Main Skill: | |[Sign in][Account]  | | Up:[pobb.in v]|
| [<No skill>]| +--------------------+ +---------------+ | [<No skill>]| |[Authorize w/ PoE]  | | [Share Link]  |
|             | |2. Pick a character | | Open a build  | |             | +--------------------+ | [] Export...  |
| Avg Dmg:0.1 | |Lg:[   v]Ch:[Fetch..]| | Paste a...   | | Avg Dmg:0.1 | |2. Pick a character | | (full 3 lines)|
| ...         | +--------------------+ | [Paste link..]| | ...         | |League: [All      v]| +---------------+
| .... Dmg Re:| |3. Choose what..    | |[Open as..][Op]| | Phys. Dmg R:| |Char:   [Fetch... v]| | Open a build  |
| Fire:-60%   | |Destination:[New..] | |Paste a...pas..| | Fire:-60%   | +--------------------+ | [Paste link..]|
| ...ment Spd:| |[Overwrite current] | +---------------+ | Move Speed: | |3. Choose what..    | | [Open as new..|
|             | |Creates a new...cur.|                 | |             | |Destination:        | | [Open Build]  |
|             | +--------------------+                 | |             | |[New build][Overwr.]| | (wrapped hint)|
+-------------+----------------------------------------+ +-------------+----------------------------------------+
|[Options][About][Check..]PoB Community Fork (overflow)| |[Options][About][Check Update] PoB Community Fork     |
+------------------------------------------------------+ +------------------------------------------------------+

```

## 3. Automated Layout Assertions (`Qt6::QuickTest`)

```qml
// tests/quick/tst_import_layout.qml
import QtQuick
import QtTest

TestCase {
    name: "ImportViewLayout"
    when: windowShown

    function test_topBarFitsWithin1100Width() {
        const win = rootWindow // 1100x720
        const topBar = findChild(win, "topBar")
        const loadoutDrop = findChild(topBar, "loadoutDrop")
        const nameText = findChild(topBar, "nameText")

        // Rightmost visible TopBar control must stay strictly inside window bounds
        const loadoutRight = loadoutDrop.mapToItem(win.contentItem, loadoutDrop.width, 0).x
        verify(loadoutRight <= win.width - 8, "loadoutDrop clipped off right edge: x=" + loadoutRight)
        verify(!nameText.truncated || nameText.width >= 90, "Unnamed build overly crushed: w=" + nameText.width)
    }

    function test_allPopulatedDropdownsRenderNonEmptyLabels() {
        const view = findChild(rootWindow, "importView")
        const realmDrop = findChild(view, "realmDrop")
        const leagueDrop = findChild(view, "leagueDrop")
        const shareSiteDrop = findChild(view, "shareSiteDrop")
        const openModeDrop = findChild(view, "openModeDrop")

        for (const dd of [realmDrop, leagueDrop, shareSiteDrop, openModeDrop]) {
            verify(dd.count > 0, dd.objectName + " model unexpectedly empty")
            verify(dd.currentIndex >= 0, dd.objectName + " has no active selection")
            verify(dd.currentLabel.length > 0, dd.objectName + " rendered blank label")
            const lbl = findChild(dd, "valueLabel")
            verify(lbl.paintedWidth > 0 && !lbl.truncated, dd.objectName + " label missing or truncated: " + dd.currentLabel)
        }
    }

    function test_noTruncatedInstructionalHintsOrSidebarStats() {
        const view = findChild(rootWindow, "importView")
        const hintLabels = findChildren(view, "hintLabel")
        for (const h of hintLabels) {
            if (h.visible) {
                verify(!h.truncated, "Instructional hint truncated: " + h.sourceText)
                verify(h.paintedWidth <= h.width + 1, "Hint overflows container")
            }
        }

        // Sidebar StatPanel labels must not elide standard stats
        const statList = findChild(rootWindow, "statPanelList")
        for (let i = 0; i < statList.count; i++) {
            const row = statList.itemAtIndex(i)
            if (!row) continue
            const statLbl = findChild(row, "statLabel")
            if (statLbl && statLbl.visible) {
                verify(!statLbl.truncated, "Sidebar stat label elided: " + statLbl.label)
                verify(statLbl.x + statLbl.width < 200, "Stat label overlaps value column")
            }
        }
    }

    function test_destinationButtonsSingleRowNoOverlap() {
        const newBtn = findChild(rootWindow, "destNewBuildBtn")
        const overwriteBtn = findChild(rootWindow, "destOverwriteBtn")
        compare(newBtn.mapToItem(null, 0, 0).y, overwriteBtn.mapToItem(null, 0, 0).y)
        verify(newBtn.mapToItem(null, newBtn.width, 0).x < overwriteBtn.mapToItem(null, 0, 0).x)
    }
}

```
