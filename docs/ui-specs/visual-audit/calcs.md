# Visual & Layout Audit: `calcs.png` (`CalcsView.qml` & `CalcSectionCard.qml`)

**Viewport:** 1100 × 720 (`sideBarWidth: 312`, `topBarHeight: 32`, `bottomBar: 28` → content viewport `788 × 660`)

## 1. Visual Defect Table

| Severity | Visual Symptom in PNG | Root Cause (`file:line`) | Expected Behavior |
| --- | --- | --- | --- |
| **Critical** | **`View Skill Details:` collides vertically with `Skill Hit Damage:`** — the white bottom border of `View Skill Details:` touches/overlaps the orange top border of `Skill Hit Damage:` with zero 8px gap, jamming `"Curses and Debuffs:"` against the orange border. With more control rows (Part / Stages / Minion / Minion Skill), `View Skill Details` will overlap and occlude the header and top rows of `Skill Hit Damage`. | `pob_calcs.lua:154`, `CalcsView.qml:67-97`, `CalcSectionCard.qml:145`: Lua's `resolveSection` computes `sec.height` using `18px` per row (`132px` total), and `computeLayout` places `Skill Hit Damage` at `sy + secH + 8` (`144px`). However, `CalcSectionCard.qml:145` renders every control row at `22px` (`+4px` each), making the actual rendered card `146px+` tall — exceeding `sec.height` by `14px` (and up to `28px+` for minion/stage skills). | Make `pob_calcs.lua:154` add `22` (not `18`) for rows containing a `control`, OR drive `CalcsView.computeLayout` from actual card heights (including `2px` header dividers) so the `8px` inter-card gap is always preserved regardless of visible control rows. |
| **Critical** | **6-column wide tables (`Skill Hit Damage`, `Damage Taken`) overflow their card's inner width by `6px` (`4px` past the outer right border).** The `Chaos:` cells bleed flush over/past the right vertical card border. | `pob_calcs.lua:131`, `CalcSectionCard.qml:55, 150, 169, 179`: 3-column card has `width = 706`, inner `cardCol.width = 702` (`x: 2..704`). Label column is `132px` (`CalcSectionCard.qml:150`) and 6 cells are `96px` each (`576px`), totaling `132 + 576 = 708px` (`x: 2..710` on a `706px` card) with no `clip: true` on `cardCol`. | Compute each cell's width from `Math.floor((rowBox.width - labelBg.width) / rowBox.rowCells.length)` for multi-column rows (or set `labelBg.width: 126`, giving `126 + 6 * 96 = 702 === cardCol.width`) and add `clip: true` on `cardCol`. |
| **High** | **`Active Skill:` dropdown in `View Skill Details:` is completely blank/empty** while still rendering a bright enabled-looking white caret arrow. | `CalcSectionCard.qml:258-277`, `pob_calcs.lua:249-280`: Unlike `MainSkillPanel.qml:106` (which hides `skillDrop` when `noSkills` is true), `ctrlSkillComp` always renders with an empty `model`, no `placeholder` (`"<None>"`), and `DropDownControl` does not dim its caret when `controlEnabled: false`. | Hide the `Active Skill` row (or show dimmed placeholder `"<None>"` and dimmed caret) when `skills.length === 0` or `skillsEnabled === false`. |
| **High** | **No visible vertical scrollbar despite `Damage Taken:` being cut off mid-card at the bottom of the viewport**, leaving a `78px` blank navy margin on the right (`x: 710..788`). | `CalcsView.qml:255-261`: Uses `QC.ScrollBar` with `policy: QC.ScrollBar.AsNeeded` (which auto-fades to invisible when idle), inconsistent with the persistent `Widgets.ScrollBar` used in `ConfigView.qml:312` and `StatPanel.qml:231`. | Replace `QC.ScrollBar` with persistent `Widgets.ScrollBar` (`autoHide: true`, visible whenever `contentHeight > height`) so users immediately see that the Defence sections continue below the fold. |
| **Medium** | `CalcsView.qml:307-311` still wires `Manage Spectres...` to a stale `"The Spectre Library is not built yet"` `MessagePopup` stub even though `SpectreLibraryPopup` is already implemented in `main.qml:322`. | `CalcsView.qml:290, 307-311`: Local `spectreNotice` stub never updated after Phase 3 long-tail shipped `SpectreLibraryPopup`. | Emit a `manageSpectresRequested()` signal from `CalcsView` wired to `spectreLibraryPopup.openFresh()` in `main.qml` (matching `MainSkillPanel`). |
| **Medium** | Hardcoded legacy pure-black `#000000` / `#1A1A1A` card surfaces clash with the `#0F172A` Cyber Citrus canvas; `Cold:` (`#3F6DB3` on `#000000` ≈ 3.8:1) fails WCAG AA contrast, and the top `Search (Ctrl+F)` bar has `border.width: 0` on the same color as the canvas with dim placeholder text. | `CalcSectionCard.qml:31, 98, 148`, `pob_calcs.lua:177`, `CalcsView.qml:201-215`: Literal `#1A1A1A` / `#000000` / `#444444` instead of `theme.*` tokens; `Search` bar lacks bottom divider. | Theme card/row chrome via `theme.background`/`theme.titleBar`/`theme.border`, add a `1px` bottom border under the search bar, and brighten `Cold` header text to `>= 4.5:1` contrast (e.g. `#60A5FA` or `#5B9BF0`). |
| **Low** | `"Skill type-specific Stats:"` header is cramped next to its `-` collapse button (`230px` card), and `"Curses and Debuffs:"` sits within `3px` of the left border of `labelBg` (`132px`); shared `TopBar` / `StatPanel` / `BottomBar` defects persist. | `CalcSectionCard.qml:75-120, 150-165`, `TopBar.qml:168-420`, `StatPanel.qml:194-205`, `BottomBar.qml:31-67`. | Add `elide: Text.ElideRight` to the subsection title `ColorText` inside a bounded width (`parent.width - toggleBtn.width - 10`), and apply shared shell fixes. |

## 2. Actual vs Target ASCII Wireframe Diff (1100 × 720)

```text
ACTUAL (1100x720):
+---------------------------------------------------------------------------------+
| [<<][<< Back][Save][Save As] Unnamed ... [0/123 0/8][Auto][1][Scionv][Nonev][Nonev][Loadout|
+----------------------+----------------------------------------------------+-----+
| BUILD / TOOLS        | [Search (Ctrl+F)        ]  (no bar border)         |     |
|                      | +------------------------------------------------+ |     |
|                      | | View Skill Details:                        [-] | | 78px|
| Main Skill:          | |  Socket Group: [<No skills added yet>       v] | | dead|
| [<No skills...    v] | |  Active Skill: [ (BLANK + bright caret)     v] | | gap |
|                      | |  Calc Mode:    [Effective DPS v]               | | NO  |
|                      | | Curses&Debuffs:                                | | V-  |
|                      | +================================================+ | SCR | <- ZERO gap! White/Orange COLLIDE
|                      | | Skill Hit Damage: 0.1 DPS                  [-] | | BAR |
|                      | |            |All |Phys |Light|Cold |Fire |Chaos:|| |     | <- Chaos overflows card right edge +4px
|                      | | MH Hit Dmg |1-2 |1-2  |0-0  |0-0  |0-0  |0-0   || |     |
|                      | +------------------------------------------------+ |     |
|  .... Damage Red.:0% | +-------------++--------------++-----------------+ |     |
|  ...ment Speed: +0%  | |Attack/Cast  ||Crits: 0% x1.5||Skill type-spec..| |     |
|                      | +-------------++--------------++-----------------+ |     |
|                      | +------------------------------------------------+ |     |
|                      | | Damage Taken: (CUT OFF AT BOTTOM, no scrollbar)| |     |
+----------------------+----------------------------------------------------+-----+
| [Options][About][Check for Update] PoB Community Fork / Version: 2.68.1         |
+---------------------------------------------------------------------------------+

TARGET (1100x720):
+---------------------------------------------------------------------------------+
| [<<][<< Back][Save][Save As] Unnamed build [0/123 0/8][Auto][1][Scionv][Nonev][Nonev][Loadouts v]|
+----------------------+----------------------------------------------------+---+-+
| BUILD / TOOLS        | [Search (Ctrl+F)        ]                          |   | |
|                      | ---------------------------------------------------+---+ | <- 1px divider
|                      | +------------------------------------------------+     |^|
| Main Skill:          | | View Skill Details:                        [-] |     |#| <- Persistent Widgets.ScrollBar
| [<No skills...    v] | |  Socket Group: [<No skills added yet>       v] |     |#|
|                      | |  Active Skill: [<None> (dimmed caret)       v] |     |#|
|                      | |  Calc Mode:    [Effective DPS v]               |     | |
|                      | | Curses&Debuffs:                                |     | |
|                      | +------------------------------------------------+     | |
|                      |        (crisp 8px vertical gap guaranteed)             | |
|                      | +------------------------------------------------+     | |
|                      | | Skill Hit Damage: 0.1 DPS                  [-] |     | |
|                      | |           |All |Phys |Light|Cold |Fire |Chaos: |     | | <- Fits inside cardCol.width (702px)
|                      | | MH Hit Dmg|1-2 |1-2  |0-0  |0-0  |0-0  |0-0    |     | |
| Phys. Damage Red.:0% | +------------------------------------------------+     | |
| Movement Speed:  +0% | +-------------++--------------++-----------------+     |v|
+----------------------+----------------------------------------------------+---+-+
| [Options][About][Check for Update] PoB Community Fork / Version: 2.68.1         |
+---------------------------------------------------------------------------------+
```

## 3. Automated Layout Assertions (`Qt6::QuickTest`)

```qml
import QtQuick
import QtTest

TestCase {
    name: "CalcsViewLayoutAudit"
    when: windowShown

    function test_calcs_cards_no_vertical_or_horizontal_overflow() {
        var view = findChild(mainWindow, "calcsView")
        verify(view !== null && view.visible)

        var cards = findChildren(view, "calcSectionCard")
        var visibleCards = []
        for (var i = 0; i < cards.length; i++) {
            if (cards[i].visible) visibleCards.push(cards[i])
        }
        verify(visibleCards.length >= 2, "Expected multiple visible CalcSectionCard items")

        // 1. Pairwise non-overlap check: no two cards may collide, and stacked cards keep >= 6px gap
        for (var a = 0; a < visibleCards.length; a++) {
            var ca = visibleCards[a]
            for (var b = a + 1; b < visibleCards.length; b++) {
                var cb = visibleCards[b]
                var xOverlap = (ca.x < cb.x + cb.width) && (cb.x < ca.x + ca.width)
                var yOverlap = (ca.y < cb.y + cb.height) && (cb.y < ca.y + ca.height)
                verify(!(xOverlap && yOverlap),
                       "CalcSectionCard overlap between " + ca.sectionObj.id + " (bottom="
                       + (ca.y + ca.height) + ") and " + cb.sectionObj.id + " (top=" + cb.y + ")")
                if (xOverlap && ca.y < cb.y) {
                    verify(cb.y - (ca.y + ca.height) >= 6,
                           "Insufficient vertical gap between " + ca.sectionObj.id + " and " + cb.sectionObj.id
                           + ": " + (cb.y - (ca.y + ca.height)) + "px")
                }
            }

            // 2. Every cell inside a card must remain within the card's inner width (cardWidth - 4)
            var cells = findChildren(ca, "calcCellWrap")
            for (var c = 0; c < cells.length; c++) {
                var cellRight = cells[c].mapToItem(ca, cells[c].width, 0).x
                verify(cellRight <= ca.width - 2,
                       "Cell overflows card right border in " + ca.sectionObj.id + ": "
                       + cellRight + " > " + (ca.width - 2))
            }

            // 3. Rendered card height must match layout engine's predicted sec.height
            verify(Math.abs(ca.height - ca.sectionObj.height) <= 2,
                   "Card height drift in " + ca.sectionObj.id + ": actual=" + ca.height
                   + " layout=" + ca.sectionObj.height)
        }

        // 4. Persistent vertical scrollbar must be visible when contentHeight > viewport height
        var gridFlick = findChild(view, "gridFlick")
        var vScroll   = findChild(view, "calcsVScroll")
        if (gridFlick.contentHeight > gridFlick.height) {
            verify(vScroll !== null && vScroll.visible && vScroll.opacity >= 0.9,
                   "Vertical scrollbar hidden while Calcs grid overflows vertically")
        }

        // 5. Disabled Active Skill dropdown must display placeholder or be hidden (never blank)
        var skillDrop = findChild(view, "calcsActiveSkillDrop")
        if (skillDrop && skillDrop.visible) {
            verify(skillDrop.displayText.length > 0 || skillDrop.placeholder.length > 0,
                   "Active Skill dropdown renders completely empty")
        }
    }
}
```
