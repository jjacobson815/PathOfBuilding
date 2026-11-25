# Visual & Layout Audit: `config.png` (`ConfigView.qml` & `ConfigOptionRow.qml`)

**Viewport:** 1100 × 720 (`sideBarWidth: 312`, `topBarHeight: 32`, `bottomBar: 28` → content viewport `788 × 660`)

## 1. Visual Defect Table

| Severity | Visual Symptom in PNG | Root Cause (`file:line`) | Expected Behavior |
| --- | --- | --- | --- |
| **Critical** | **Every single option label across both columns is right-clipped mid-character** (`Resistance penalt`, `Bandit quest` missing `:`, `Major Goc`, `Minor Goc`, `Ailment calculation mod`, `Ignore Jewel Limi`, `Do you use Power Charge`, `Do you have Onslaug`, `Are you Fortifiec`, `Map Tie`, `Prefix`/`Suffix` sliced, `Assassin's Mark` sliced, `Poacher's Marl`, `Warlord's Marl`, `Temporal Chain`). | `ConfigOptionRow.qml:64-82`: `labelArea` has `width: 222` and `clip: true`. Inside it, `optLabel` uses `anchors.right: parent.right` with no explicit `width` or `horizontalAlignment: Text.AlignRight`. `Label` computes its `width` via `.tgf` `TextMetrics` (narrower than Qt's Liberation Sans TTF render), so Qt anchors the narrower box flush right and the TTF overhang spills past `x = 222` straight into the `clip: true` guillotine. | Give `optLabel` a real box (`anchors.fill: parent`, `horizontalAlignment: root.isText ? Text.AlignLeft : Text.AlignRight`, `elide: Text.ElideRight`) — the same fix already used in `StatPanel.qml:194-205` — and measure overflow via `optLabel.implicitWidth` (not `TextMetrics`) so Qt's own right-edge alignment guarantees zero right-edge shearing. |
| **High** | Long option labels (`% increased effect of map mo`, `PvP damage scaling in effe`, `Are you on Consecrated Groun`, `Have you used a Warcry Recent`, `# of Warcries Used Recent`) still overflow `222px` even after dropping to `12px` and are hard-clipped without ellipsis or wrapping. | `ConfigOptionRow.qml:77-80`: Font-shrink threshold checks `textMetrics.width(14, "VAR", raw) > 220` (underestimating TTF width by ~10–15%), and `optLabel` has neither `elide: Text.ElideRight` nor two-line `wrapMode: Text.WordWrap` with dynamic row height. | Use `wrapMode: Text.WordWrap` (growing row height when `lineCount > 1`, mirroring legacy `ConfigTab`) or `elide: Text.ElideRight` with full-text tooltip fallback; never hard-clip mid-glyph. |
| **High** | Section border lines cut directly through the trailing letters of section titles (`When In Combat` through `'t'`, `Map Modifiers and Player Debuffs` through `'ffs'`, `For Effective DPS` through `'PS'`). | `ConfigView.qml:202-204` (`Widgets.Section` title plate): `Section`'s opaque title mask behind the label is sized with `TextMetrics`, which is narrower than Qt's painted TTF string, causing the top horizontal border stroke to resume behind the last 1–3 characters. | Size `Section`'s title-plate mask from `titleText.paintedWidth + 8` (or `implicitWidth + 8`) rather than `TextMetrics`, so the border clears the entire title with symmetrical padding. |
| **Medium** | Header row controls are misaligned horizontally (`Manage...` ends at `x: 386`, `Search` ends at `x: 370`, `Show All Configurations` starts at `x: 380`), and `"Config set:"` sits only ~2px from `setSelect`. | `ConfigView.qml:113-167`: Hardcoded `x` coordinates (`setLabel.x: 10`, `setSelect.x: 82`, `manageBtn.x: 296` / `w: 90` → `386`; `searchEdit.x: 10` / `w: 360` → `370`, `showAllBtn.x: 380` / `w: 210` → `590`). | Align header controls on the same column grid (`col0: 10..370`, `col1: 380..740`): e.g. `setLabel` (`x: 10`), `setSelect` (`x: 88, w: 186`), `manageBtn` (`x: 280, w: 90` → right `370`), matching `searchEdit` right edge (`370`). |
| **Medium** | At 1100px width (`flick.width = 770`), `colCount` evaluates to `2`, dumping all legacy Column 3 sections (including `Custom Modifiers`) at the very bottom of Column 2, while leaving `30px` of unused dead space on the right (`x: 740..770`). | `ConfigView.qml:31-46, 172-190`: Fixed `360px` column width (`Math.floor((770 - 10) / 370) = 2`) with `targetCol = Math.min(colCount - 1, desired - 1)`. | Allow each column to flex-expand to `Math.floor((flick.width - 20 - (colCount - 1) * 10) / colCount)` (`370px` each at 2 cols), giving `labelArea` an extra `+10px` (`232px`) and eliminating dead right gutter. |
| **Low** | Disabled `Config set:` (`Default`) dropdown and `Search` placeholder text have low contrast; `TopBar` right overflow (`Unnamed ...`, clipped `Loadouts`, off-screen `Mode: BUILD`), `StatPanel` left-elision, and `BottomBar` vertical cramping persist. | `ConfigView.qml:121-155`, `TopBar.qml:168-420`, `StatPanel.qml:194-205`, `BottomBar.qml:31-67`: Shared shell and disabled-state color token issues (`#64748B` on `#0F172A`). | Apply shared shell fixes (`TopBar`, `StatPanel`, `BottomBar`) and lift disabled/placeholder contrast to `>= 4.5:1`. |

## 2. Actual vs Target ASCII Wireframe Diff (1100 × 720)

```text
ACTUAL (1100x720):
+---------------------------------------------------------------------------------+
| [<<][<< Back][Save][Save As] Unnamed ... [0/123 0/8][Auto][1][Scionv][Nonev][Nonev][Loadout|
+----------------------+--------------------------------------------------------+-+
| BUILD / TOOLS        | Config set:[Default        v][Manage...]               | |
|                      | [Search                        ] [Show All Configs   ] | |
|                      | +-General------------------+  +-Map Modifiers...Debuff-+^| <- Border cuts through "ffs" & "t"
| Main Skill:          | |   Resistance penalt[Act10v] | % increased effect...mo||#| <- ALL labels sheared at x=222!
| [<No skills...    v] | |       Bandit quest[Kill v]  |             Map Tie[Rv]||#|
|                      | |          Major Goc[Nothi v] |              Prefix[Nv]||#|
|                      | |          Minor Goc[Nothi v] |              Suffix[Nv]|| |
|                      | |   Ignore Jewel Limi[ ]      |   PvP damage...in effe[ ]| |
|  .... Damage Red.:0% | +-When In Comba------------+  |      Assassin's Mark[  ]| |
|  ...ment Speed: +0%  | | Do you use Power Charge[ ]  |       Poacher's Marl[  ]| |
|                      | | Do you have Onslaug[ ]      |      Temporal Chain[  ]|v|
+----------------------+--------------------------------------------------------+-+
| [Options][About][Check for Update] PoB Community Fork / Version: 2.68.1         |
+---------------------------------------------------------------------------------+

TARGET (1100x720):
+---------------------------------------------------------------------------------+
| [<<][<< Back][Save][Save As] Unnamed build [0/123 0/8][Auto][1][Scionv][Nonev][Nonev][Loadouts v]|
+----------------------+--------------------------------------------------------+-+
| BUILD / TOOLS        | Config set: [Default     v][Manage...]                 | |
|                      | [Search                     ] [Show All Configurations ] | | <- Aligned at x=370/380
|                      | +- General ----------------+  +- Map Modifiers & Debuffs -+^| <- Mask clears full paintedWidth
| Main Skill:          | |  Resistance penalty: [Act10v]| % inc. effect of     ||#| <- Wrapped / full AlignRight box
| [<No skills...    v] | |        Bandit quest: [Kill v]|  map mods:   [      ]||#|    (ZERO right-edge clipping)
|                      | |           Major God: [None v]|    Map Tier: [Red  v]||#|
|                      | |           Minor God: [None v]|      Prefix: [None v]|| |
|                      | |  Ignore Jewel Limit: [ ]     |      Suffix: [None v]|| |
| Phys. Damage Red.:0% | +- When In Combat ---------+  | PvP damage scaling: [ ]| |
| Movement Speed:  +0% | | Use Power Charges?:  [ ]     |  Assassin's Mark: [  ]| |
|                      | | Have Onslaught?:     [ ]     |   Poacher's Mark: [  ]|v|
+----------------------+--------------------------------------------------------+-+
| [Options][About][Check for Update] PoB Community Fork / Version: 2.68.1         |
+---------------------------------------------------------------------------------+
```

## 3. Automated Layout Assertions (`Qt6::QuickTest`)

```qml
import QtQuick
import QtTest

TestCase {
    name: "ConfigViewLayoutAudit"
    when: windowShown

    function test_config_labels_never_clip_and_headers_clear_borders() {
        var view = findChild(mainWindow, "configView")
        verify(view !== null && view.visible)

        // 1. Every ConfigOptionRow label must render completely inside labelArea without clipping
        var rows = findChildren(view, "configOptionRow")
        verify(rows.length > 0, "Expected visible ConfigOptionRow items")
        for (var i = 0; i < rows.length; i++) {
            var area = findChild(rows[i], "labelArea")
            var lbl  = findChild(rows[i], "optLabel")
            verify(area !== null && lbl !== null)
            // Must use Qt box alignment, not TextMetrics-sized right-anchored overflow
            verify(lbl.x >= 0, "Label overflows left of labelArea: " + lbl.label)
            verify(lbl.x + lbl.paintedWidth <= area.width + 0.5,
                   "Label right-clipped in ConfigOptionRow: '" + lbl.label + "' painted="
                   + lbl.paintedWidth + " areaW=" + area.width)
            if (lbl.wrapMode === Text.NoWrap) {
                verify(lbl.elide !== Text.ElideNone, "Single-line config label must enable elide fallback")
            }
            // Control must not overlap labelArea
            var ctrlX = rows[i].isText ? 4 : 228
            if (!rows[i].isText) {
                verify(area.x + area.width + 4 <= ctrlX,
                       "labelArea touches control at row " + rows[i].optVar)
            }
        }

        // 2. Section title mask must fully cover paintedWidth of the section title
        var sections = findChildren(view, "configSection")
        for (var s = 0; s < sections.length; s++) {
            var titleMask = findChild(sections[s], "sectionTitleBg")
            var titleText = findChild(sections[s], "sectionTitleText")
            if (titleMask && titleText) {
                verify(titleMask.width >= titleText.paintedWidth + 6,
                       "Section border strikes through title: '" + titleText.text + "' mask="
                       + titleMask.width + " painted=" + titleText.paintedWidth)
            }
        }

        // 3. Header row 1 & row 2 right edges align cleanly with Column 0
        var manageBtn  = findChild(view, "manageBtn")
        var searchEdit = findChild(view, "searchEdit")
        var setLabel   = findChild(view, "setLabel")
        var setSelect  = findChild(view, "setSelect")
        verify(setLabel.x + setLabel.paintedWidth + 6 <= setSelect.x,
               "Config set label too close to dropdown")
        verify(Math.abs((manageBtn.x + manageBtn.width) - (searchEdit.x + searchEdit.width)) <= 2,
               "Header row 1/2 right edges misaligned")
    }
}
```
