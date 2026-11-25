import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QC
import "../components" as Widgets
import "../components/QmlBridge.js" as QmlBridge

// CALCS view — Phase 8 (Calcs Tab & Breakdown).
// Ports src/Classes/CalcsTab.lua, CalcSectionControl.lua, CalcBreakdownControl.lua:
//   - CalcSections.lua-driven responsive offence (group 1, 3 cols) + defence
//     (groups 2/3, cols 4-5 with reflow + portrait 3-col fallback) grid.
//   - First section "View Skill Details" with independent *Calcs skill/part/
//     stage/mine/minion/spectre/minion-skill selectors, "Show Minion Stats",
//     Calculation Mode (calcsInput.misc_buffMode), and buff/combat/curse lists.
//   - Ctrl+F search bar highlighting matching subsection/row labels, Ctrl+Z /
//     Ctrl+Y undo/redo, and persisted <Section> subsection collapse toggles.
//   - On-demand click/hover breakdown panel (hover = transient, click = pinned
//     with bright green border, click-away closes, rebinds on every rebuild)
//     supporting TEXT lines, generic/reservation/damageTypes/slots/mod tables,
//     item tooltips, embedded Phase 4 TreeViewer for Tree-sourced mods, and
//     AoE radius visualiser over Assets/range_guide.png.
Item {
    id: calcsView
    anchors.fill: parent
    clip: true

    property var gridData: null
    property var skillSelect: null
    property var searchMatches: ({})
    property int searchHitCount: 0
    property string searchQuery: ""

    // Active breakdown panel state (transient on hover, sticky when pinned).
    property string activeCellKey: ""
    property bool breakdownPinned: false
    property var breakdownData: null
    property rect breakdownAnchor: Qt.rect(0, 0, 0, 0)

    readonly property var _sections: QmlBridge.toArray(gridData ? gridData.sections : null)
    readonly property int colWidth: (gridData && gridData.colWidth) ? gridData.colWidth : 230
    readonly property bool portraitMode: !!(gridData && gridData.portrait)

    // Responsive masonry layout (ports CalcsTab:Draw, CalcsTab.lua:232-308).
    // Returns { positions: [{x, y, visible}, ...], contentW, contentH }.
    readonly property var layoutInfo: computeLayout(_sections, gridFlick.width, gridFlick.height, colWidth, portraitMode)

    function computeLayout(sections, viewW, viewH, cw, portrait) {
        var positions = []
        if (!sections || sections.length === undefined) {
            return { positions: positions, contentW: cw * 3 + 24, contentH: 100 }
        }
        var availW = Math.max(cw * 3 + 24, viewW || (cw * 3 + 24))
        var availH = Math.max(400, viewH || 600)
        var maxCol = portrait ? 3 : Math.max(3, Math.floor(availW / (cw + 8)))
        var baseX = 4
        var baseY = 4
        var colY = {}
        var maxY = baseY
        var maxRight = baseX + (cw + 8) * 3

        for (var i = 0; i < sections.length; i++) {
            positions.push({ x: 0, y: 0, visible: false })
        }

        // First pass: place group 1 (cols 1..3), group 2 (col 4 if >=4), group 3 (col 5 if >=5).
        for (var i = 0; i < sections.length; i++) {
            var sec = sections[i]
            if (!sec || !sec.enabled) continue
            var secH = Math.max(22, sec.height || 22)
            var wCols = sec.widthCols || 1
            var col = 0
            if (sec.group === 1) {
                col = 1
                if (wCols === 1) {
                    var minY = colY[1] !== undefined ? colY[1] : baseY
                    for (var c = 2; c <= 3; c++) {
                        var cy = colY[c] !== undefined ? colY[c] : baseY
                        if (cy < minY) { col = c; minY = cy }
                    }
                } else {
                    var topY = colY[1] !== undefined ? colY[1] : baseY
                    for (var c = 2; c <= Math.min(3, wCols); c++) {
                        var cy2 = colY[c] !== undefined ? colY[c] : baseY
                        if (cy2 > topY) topY = cy2
                    }
                    colY[1] = topY
                }
            } else if (sec.group === 2) {
                if (maxCol >= 4) col = 4
            } else if (sec.group === 3) {
                if (maxCol >= 5) col = 5
            }

            if (col > 0) {
                var sx = baseX + (cw + 8) * (col - 1)
                var sy = colY[col] !== undefined ? colY[col] : baseY
                positions[i] = { x: sx, y: sy, visible: true }
                var nextY = sy + secH + 8
                for (var c2 = col; c2 <= col + wCols - 1; c2++) {
                    colY[c2] = nextY
                }
                if (nextY > maxY) maxY = nextY
                var rightEdge = sx + (sec.width || cw) + 8
                if (rightEdge > maxRight) maxRight = rightEdge
            }
        }

        // Second pass: reflow group 3 (and group 2 when maxCol < 4 / portrait).
        if (maxCol < 5) {
            var g1Max = Math.max(
                colY[1] !== undefined ? colY[1] : baseY,
                colY[2] !== undefined ? colY[2] : baseY,
                colY[3] !== undefined ? colY[3] : baseY
            )
            colY[1] = g1Max
            colY[2] = g1Max
            colY[3] = g1Max
            var targetMaxCol = maxCol >= 4 ? 4 : 3
            for (var j = 0; j < sections.length; j++) {
                var s2 = sections[j]
                if (!s2 || !s2.enabled) continue
                if (positions[j].visible) continue
                if (!((maxCol < 4 && s2.group === 2) || s2.group === 3)) continue
                var s2H = Math.max(22, s2.height || 22)
                var col2 = targetMaxCol
                var curColY = colY[col2] !== undefined ? colY[col2] : baseY
                if (curColY + s2H + 4 >= Math.max(availH, maxY)) {
                    var minY2 = curColY
                    for (var c3 = targetMaxCol; c3 >= 1; c3--) {
                        var cy3 = colY[c3] !== undefined ? colY[c3] : baseY
                        if (cy3 < minY2) { col2 = c3; minY2 = cy3 }
                    }
                }
                var sx2 = baseX + (cw + 8) * (col2 - 1)
                var sy2 = colY[col2] !== undefined ? colY[col2] : baseY
                positions[j] = { x: sx2, y: sy2, visible: true }
                colY[col2] = sy2 + s2H + 8
                if (colY[col2] > maxY) maxY = colY[col2]
                var r2 = sx2 + (s2.width || cw) + 8
                if (r2 > maxRight) maxRight = r2
            }
        }

        return { positions: positions, contentW: maxRight + 8, contentH: maxY + 16 }
    }

    function refresh() {
        var g = luaEngine.invoke("pob_calcsGetGrid", [])
        if (g) gridData = g
        var sel = luaEngine.invoke("pob_calcsGetSkillSelect", [])
        if (sel) skillSelect = sel
        if (searchQuery.length > 0) runSearch(searchQuery)
        // Rebind breakdown data after every rebuild (CalcsTab.lua:464-467).
        if (activeCellKey.length > 0) {
            var bd = luaEngine.invoke("pob_calcsGetBreakdown", [activeCellKey])
            if (bd && bd.ok && bd.count > 0) {
                breakdownData = bd
            } else {
                clearBreakdown()
            }
        }
    }

    function runSearch(q) {
        searchQuery = q || ""
        if (searchQuery.length === 0) {
            searchMatches = ({})
            searchHitCount = 0
            return
        }
        var r = luaEngine.invoke("pob_calcsSearch", [searchQuery])
        if (r && r.matched) {
            searchMatches = r.matched
            searchHitCount = r.count || 0
        } else {
            searchMatches = ({})
            searchHitCount = 0
        }
    }

    function clearBreakdown() {
        activeCellKey = ""
        breakdownPinned = false
        breakdownData = null
    }

    function showBreakdown(cellKey, cellRect, pin) {
        if (!cellKey) return
        if (!pin && breakdownPinned) return
        if (pin && breakdownPinned && activeCellKey === cellKey) {
            clearBreakdown()
            return
        }
        var bd = luaEngine.invoke("pob_calcsGetBreakdown", [cellKey])
        if (!bd || !bd.ok || !bd.count) {
            if (pin) clearBreakdown()
            return
        }
        activeCellKey = cellKey
        breakdownPinned = pin
        breakdownAnchor = cellRect
        breakdownData = bd
    }

    onVisibleChanged: {
        if (visible) refresh()
        else if (!breakdownPinned) clearBreakdown()
    }

    Component.onCompleted: refresh()

    Connections {
        target: luaEngine
        function onCalcsChanged() { if (calcsView.visible) calcsView.refresh() }
        function onSkillsChanged() { if (calcsView.visible) calcsView.refresh() }
        function onItemsChanged() { if (calcsView.visible) calcsView.refresh() }
        function onModeChanged() { if (calcsView.visible) calcsView.refresh() }
    }

    // Keyboard shortcuts (CalcsTab.lua:321-333): Ctrl+F search, Ctrl+Z undo, Ctrl+Y redo, Esc closes breakdown.
    Shortcut {
        enabled: calcsView.visible
        sequences: [StandardKey.Find]
        onActivated: {
            searchBox.forceEditFocus()
            searchBox.selectAll()
        }
    }
    Shortcut {
        enabled: calcsView.visible
        sequences: [StandardKey.Undo]
        onActivated: luaEngine.invoke("pob_calcsUndo", [])
    }
    Shortcut {
        enabled: calcsView.visible
        sequences: [StandardKey.Redo]
        onActivated: luaEngine.invoke("pob_calcsRedo", [])
    }
    Shortcut {
        enabled: calcsView.visible && calcsView.activeCellKey.length > 0
        sequence: "Escape"
        onActivated: calcsView.clearBreakdown()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        // Top search bar (CalcsTab.lua:41)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            color: theme.sideBarBg
            border.width: 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                spacing: 8

                Widgets.EditControl {
                    id: searchBox
                    objectName: "pob.calcs.input_search"
                    Layout.preferredWidth: 260
                    Layout.preferredHeight: 20
                    placeholder: "Search (Ctrl+F)"
                    maxChars: 100
                    size: theme.fontSize - 1
                    onEdited: (t) => calcsView.runSearch(t)
                    onCommitted: (t) => calcsView.runSearch(t)
                    onReverted: {
                        searchBox.text = ""
                        calcsView.runSearch("")
                    }
                }

                Widgets.Button {
                    objectName: "pob.calcs.btn_clear_search"
                    visible: calcsView.searchQuery.length > 0
                    label: "Clear"
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 20
                    onClicked: {
                        searchBox.text = ""
                        calcsView.runSearch("")
                    }
                }

                Widgets.ColorText {
                    visible: calcsView.searchQuery.length > 0
                    sourceText: calcsView.searchHitCount > 0
                                ? ("^x33FF77" + calcsView.searchHitCount + " match" + (calcsView.searchHitCount === 1 ? "" : "es"))
                                : "^xDD0022No matches"
                    font.pixelSize: theme.fontSize - 1
                }

                Item { Layout.fillWidth: true }

                Widgets.ColorText {
                    visible: calcsView.breakdownPinned
                    sourceText: "^x40FF40Breakdown pinned (click stat or outside to close)"
                    font.pixelSize: theme.fontSize - 2
                }
            }
        }

        // Scrollable responsive section grid
        Item {
            id: gridArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Flickable {
                id: gridFlick
                anchors.fill: parent
                contentWidth: Math.max(width, calcsView.layoutInfo.contentW)
                contentHeight: Math.max(height, calcsView.layoutInfo.contentH)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                QC.ScrollBar.vertical: QC.ScrollBar {
                    policy: QC.ScrollBar.AsNeeded
                    width: 16
                }
                QC.ScrollBar.horizontal: QC.ScrollBar {
                    policy: QC.ScrollBar.AsNeeded
                    height: 14
                }

                // Background click-away closes a pinned breakdown (CalcBreakdownControl.lua:775).
                MouseArea {
                    width: gridFlick.contentWidth
                    height: gridFlick.contentHeight
                    z: 0
                    onClicked: {
                        if (calcsView.breakdownPinned) calcsView.clearBreakdown()
                    }
                }

                Repeater {
                    model: calcsView._sections.length
                    delegate: Widgets.CalcSectionCard {
                        id: card
                        readonly property var pos: calcsView.layoutInfo.positions[index] || ({ x: 0, y: 0, visible: false })
                        x: pos.x
                        y: pos.y
                        visible: pos.visible
                        z: 1
                        sectionObj: calcsView._sections[index] || ({})
                        skillSelect: sectionObj && sectionObj.special ? calcsView.skillSelect : null
                        searchMatches: calcsView.searchMatches
                        activeCellKey: calcsView.activeCellKey
                        coordTarget: gridArea

                        onToggleSubsection: (si, ui) => {
                            luaEngine.invoke("pob_calcsToggleSubsection", [si, ui])
                            calcsView.refresh()
                        }
                        onCellHovered: (key, r) => calcsView.showBreakdown(key, r, false)
                        onCellUnhovered: (key) => {
                            if (!calcsView.breakdownPinned && calcsView.activeCellKey === key) {
                                calcsView.clearBreakdown()
                            }
                        }
                        onCellClicked: (key, r) => calcsView.showBreakdown(key, r, true)
                        onSkillFieldChanged: (field, value) => {
                            luaEngine.invoke("pob_calcsSetSkill", [field, value])
                            calcsView.refresh()
                        }
                        onInputChanged: (name, value) => {
                            luaEngine.invoke("pob_calcsSetInput", [name, value])
                            calcsView.refresh()
                        }
                        onManageSpectresRequested: spectreNotice.open()
                    }
                }
            }

            // Click-away interceptor when pinned so clicking anywhere outside closes it.
            MouseArea {
                anchors.fill: parent
                z: 40
                visible: calcsView.breakdownPinned && breakdownPanel.visible
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: calcsView.clearBreakdown()
            }

            // Hover / pinned breakdown panel (CalcBreakdownControl)
            Widgets.CalcBreakdownPanel {
                id: breakdownPanel
                objectName: "pob.calcs.breakdownPanel"
                z: 50
                breakdownData: calcsView.breakdownData
                pinned: calcsView.breakdownPinned
                anchorRect: calcsView.breakdownAnchor
                hostWidth: gridArea.width
                hostHeight: gridArea.height
                onCloseRequested: calcsView.clearBreakdown()
            }
        }
    }

    Widgets.MessagePopup {
        id: spectreNotice
        title: " Manage Spectres "
        message: "^7The Spectre Library is not built yet.^8 It is tracked as Phase 3 long-tail work; spectres already round-trip through the build XML."
    }
}
