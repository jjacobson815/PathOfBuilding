import QtQuick
import QtQuick.Controls as QC
import "StatDiff.js" as StatDiff
import "QmlBridge.js" as QmlBridge

// CalcBreakdownPanel — Phase 8 Part 8.2.
// Ports CalcBreakdownControl (CalcBreakdownControl.lua): hover-transient or
// click-pinned panel showing TEXT lines, TABLE sections (generic, reservations,
// damageTypes, slots, live Tabulate/Combine mod tables) and RADIUS visualisers.
// Cell tooltips on TABLE rows dispatch to:
//   - kind === "lines" : per-source Combine totals in shared Tooltip
//   - kind === "item"  : live AddItemTooltip via pob_calcsItemTooltip
//   - kind === "node"  : embedded Phase 4 TreeViewer focused on tip.nodeId
Item {
    id: root

    property var breakdownData: null
    property bool pinned: false
    property rect anchorRect: Qt.rect(0, 0, 0, 0)
    property real hostWidth: 800
    property real hostHeight: 600

    signal closeRequested()

    readonly property var _sections: (breakdownData && breakdownData.ok)
                                     ? QmlBridge.toArray(breakdownData.sections) : []
    readonly property bool hasContent: _sections.length > 0

    visible: hasContent

    // Positioning (CalcBreakdownControl.lua:718-724): right of cell (+5),
    // flip left if overflowing hostWidth, clamp vertically inside hostHeight.
    readonly property real _contentW: Math.max(180, Math.min(Math.max(240, hostWidth - 16), bodyCol.implicitWidth + (needsScroll ? 22 : 8)))
    readonly property real _desiredH: bodyCol.implicitHeight + 12
    readonly property bool needsScroll: _desiredH > Math.max(120, hostHeight - 8)
    readonly property real _panelW: _contentW
    readonly property real _panelH: Math.min(_desiredH, Math.max(120, hostHeight - 8))

    width: _panelW
    height: _panelH

    x: {
        var rightX = anchorRect.x + anchorRect.width + 5
        if (rightX + width <= hostWidth - 2) return rightX
        var leftX = anchorRect.x - 5 - width
        return Math.max(2, Math.min(leftX, hostWidth - width - 2))
    }
    y: {
        var clamped = Math.min(anchorRect.y, hostHeight - height - 2)
        return Math.max(2, clamped)
    }

    // Active sub-tooltip / embedded tree preview state.
    property int _previewNodeId: -1
    property rect _previewCellRect: Qt.rect(0, 0, 0, 0)

    function clearSubTooltips() {
        cellTooltip.hide()
        _previewNodeId = -1
        _previewCellRect = Qt.rect(0, 0, 0, 0)
    }

    onBreakdownDataChanged: clearSubTooltips()
    onVisibleChanged: if (!visible) clearSubTooltips()

    function _splitLines(text) {
        if (!text) return []
        var s = String(text)
        return s.length > 0 ? s.split("\n") : []
    }

    function _colWidth(sec, colIdx) {
        var cols = sec ? QmlBridge.toArray(sec.cols) : []
        if (cols.length === 0) return 40
        var col = cols[colIdx]
        var w = textMetrics.width(15, "VAR", col ? (col.label || "") : "") + 10
        var rows = sec ? QmlBridge.toArray(sec.rows) : []
        for (var r = 0; r < rows.length; r++) {
            var cells = rows[r] ? QmlBridge.toArray(rows[r].cells) : []
            var c = cells[colIdx]
            if (c && c.text) {
                var cw = textMetrics.width(12, "VAR", c.text) + 10
                if (cw > w) w = cw
            }
        }
        return Math.min(360, Math.max(36, Math.ceil(w)))
    }

    function _showCellTip(tip, cellItem) {
        if (!tip || !cellItem) {
            clearSubTooltips()
            return
        }
        var pt = cellItem.mapToItem(root.parent, 0, 0)
        var vp = Qt.rect(0, 0, root.hostWidth, root.hostHeight)
        if (tip.kind === "node" && tip.nodeId !== undefined) {
            cellTooltip.hide()
            _previewCellRect = Qt.rect(pt.x, pt.y, cellItem.width, cellItem.height)
            _previewNodeId = Number(tip.nodeId)
            return
        }
        _previewNodeId = -1
        cellTooltip.clear()
        cellTooltip.maxWidth = 600
        if (tip.kind === "lines" && tip.lines && tip.lines.length !== undefined) {
            for (var i = 0; i < tip.lines.length; i++) {
                cellTooltip.addLine(i === 0 ? 16 : 14, String(tip.lines[i]))
            }
            cellTooltip.showAt(pt.x, pt.y, cellItem.width, cellItem.height, vp)
        } else if (tip.kind === "item" && tip.itemId !== undefined) {
            var res = luaEngine.invoke("pob_calcsItemTooltip", [tip.itemId, tip.slot || ""])
            StatDiff.fillFromLines(cellTooltip, res)
            if (cellTooltip.lines && cellTooltip.lines.length > 0) {
                cellTooltip.showAt(pt.x, pt.y, cellItem.width, cellItem.height, vp)
            }
        }
    }

    // Background + 2px border (bright green when pinned, muted green on hover).
    Rectangle {
        objectName: "pob.breakdown.frame"
        anchors.fill: parent
        color: "#E6000000"
        border.width: 2
        border.color: root.pinned ? "#40FF40" : "#55AA55"

        Button {
            objectName: "pob.breakdown.closeBtn"
            visible: root.pinned
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 4
            anchors.rightMargin: 4
            width: 18; height: 18
            label: "x"
            z: 5
            onClicked: root.closeRequested()
        }

        // Eat clicks inside the panel so click-away backdrop does not dismiss it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (mouse) => { mouse.accepted = true }
        }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 4
            anchors.rightMargin: root.needsScroll ? 18 : 4
            contentWidth: bodyCol.implicitWidth
            contentHeight: bodyCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: root.needsScroll

            QC.ScrollBar.vertical: QC.ScrollBar {
                policy: root.needsScroll ? QC.ScrollBar.AlwaysOn : QC.ScrollBar.AlwaysOff
                width: 14
            }

            Column {
                id: bodyCol
                spacing: 8

                Repeater {
                    model: root._sections.length
                    delegate: Item {
                        id: secItem
                        readonly property var sec: root._sections[index] || ({})
                        width: secLoader.implicitWidth
                        height: secLoader.implicitHeight

                        Loader {
                            id: secLoader
                            sourceComponent: secItem.sec.type === "TEXT" ? textSecComp
                                           : secItem.sec.type === "TABLE" ? tableSecComp
                                           : secItem.sec.type === "RADIUS" ? radiusSecComp
                                           : null
                            onLoaded: {
                                if (item) item.sec = Qt.binding(function() { return secItem.sec })
                            }
                        }
                    }
                }
            }
        }
    }

    // --- TEXT section ---
    Component {
        id: textSecComp
        Column {
            id: textCol
            property var sec: ({})
            readonly property var rawLines: sec ? QmlBridge.toArray(sec.lines) : []
            spacing: 1
            padding: 2

            Repeater {
                model: textCol.rawLines.length
                delegate: Column {
                    id: textLineCol
                    readonly property var parts: root._splitLines(textCol.rawLines[index])
                    Repeater {
                        model: textLineCol.parts.length
                        delegate: ColorText {
                            sourceText: textLineCol.parts[index]
                            defaultColor: "#FFFFFF"
                            font.pixelSize: textCol.sec.textSize || 15
                        }
                    }
                }
            }
        }
    }

    // --- RADIUS section ---
    Component {
        id: radiusSecComp
        CalcRadiusVisual {
            property var sec: ({})
            radiusValue: sec.radius || 0
            guidePath: sec.guide || ""
            overlayPath: sec.overlay || ""
            polygonPoints: sec ? QmlBridge.toArray(sec.polygon) : []
        }
    }

    // --- TABLE section ---
    Component {
        id: tableSecComp
        Column {
            id: tblCol
            property var sec: ({})
            readonly property var cols: sec ? QmlBridge.toArray(sec.cols) : []
            readonly property var rows: sec ? QmlBridge.toArray(sec.rows) : []
            readonly property var colWidths: {
                var arr = []
                for (var i = 0; i < cols.length; i++) arr.push(root._colWidth(sec, i))
                return arr
            }
            readonly property int totalW: {
                var sum = 4
                for (var i = 0; i < colWidths.length; i++) sum += colWidths[i]
                return Math.max(120, sum)
            }
            spacing: 0

            // Optional table label
            ColorText {
                visible: !!(tblCol.sec.label && tblCol.sec.label.length > 0)
                sourceText: "^7" + (tblCol.sec.label || "") + ":"
                defaultColor: "#FFFFFF"
                font.pixelSize: 15
                leftPadding: 2
                bottomPadding: 2
            }

            // Header row
            Row {
                height: 20
                Repeater {
                    model: tblCol.cols.length
                    delegate: Item {
                        width: tblCol.colWidths[index] || 40
                        height: 20
                        Rectangle {
                            visible: index > 0
                            x: 0; y: 0; width: 1; height: parent.height
                            color: "#808080"
                        }
                        ColorText {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 4
                            width: parent.width - 6
                            sourceText: "^7" + (tblCol.cols[index].label || "")
                            defaultColor: "#FFFFFF"
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Data rows
            Repeater {
                model: tblCol.rows.length
                delegate: Item {
                    id: rowItem
                    readonly property var rowObj: tblCol.rows[index] || ({})
                    readonly property var rowCells: rowObj ? QmlBridge.toArray(rowObj.cells) : []
                    width: tblCol.totalW
                    height: 16

                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: "#808080"
                    }

                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: tblCol.cols.length
                            delegate: Item {
                                id: cellBox
                                readonly property var cellObj: rowItem.rowCells[index] || ({})
                                readonly property bool hasTip: !!(cellObj && cellObj.tip)
                                width: tblCol.colWidths[index] || 40
                                height: 16

                                Rectangle {
                                    visible: index > 0
                                    x: 0; y: 0; width: 1; height: parent.height
                                    color: "#808080"
                                }

                                // Legacy green top/bottom highlight lines on hovered interactive cell
                                Rectangle {
                                    visible: cellMouse.containsMouse && cellBox.hasTip
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 1
                                    color: "#00FF00"
                                    z: 2
                                }
                                Rectangle {
                                    visible: cellMouse.containsMouse && cellBox.hasTip
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 1
                                    color: "#00FF00"
                                    z: 2
                                }

                                ColorText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 4
                                    width: parent.width - 8
                                    sourceText: cellBox.cellObj.text || ""
                                    defaultColor: "#FFFFFF"
                                    font.pixelSize: 12
                                    horizontalAlignment: cellBox.cellObj.right ? Text.AlignRight : Text.AlignLeft
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    id: cellMouse
                                    objectName: "pob.breakdown.tableCell"
                                    anchors.fill: parent
                                    hoverEnabled: cellBox.hasTip
                                    enabled: cellBox.hasTip
                                    cursorShape: cellBox.hasTip ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onEntered: root._showCellTip(cellBox.cellObj.tip, cellBox)
                                    onExited: root.clearSubTooltips()
                                }
                            }
                        }
                    }
                }
            }

            // Optional footer (split on newlines for single-line ColorText)
            Column {
                id: footerCol
                visible: !!(tblCol.sec.footer && tblCol.sec.footer.length > 0)
                topPadding: 3
                leftPadding: 2
                readonly property var footerLines: root._splitLines(tblCol.sec.footer)
                Repeater {
                    model: footerCol.footerLines.length
                    delegate: ColorText {
                        sourceText: "^7" + footerCol.footerLines[index]
                        defaultColor: "#FFFFFF"
                        font.pixelSize: 12
                    }
                }
            }
        }
    }

    // Shared floating Tooltip for item tooltips & per-source totals.
    Tooltip {
        id: cellTooltip
        z: 200
    }

    // Embedded Phase 4 passive tree viewer for Tree-sourced mod rows
    // (CalcBreakdownControl.lua:633-652: 304x304 white border, focusZoom 5, red ring).
    Rectangle {
        id: nodePreview
        visible: root._previewNodeId >= 0
        parent: root.parent
        z: 210
        width: 304
        height: 304
        color: "#FFFFFF"
        x: {
            var rx = root._previewCellRect.x + root._previewCellRect.width + 5
            if (rx + width <= root.hostWidth - 2) return rx
            return Math.max(2, root._previewCellRect.x - width - 5)
        }
        y: Math.max(2, Math.min(root._previewCellRect.y, root.hostHeight - height - 2))

        TreeViewer {
            id: embeddedTree
            objectName: "pob.breakdown.treePreview"
            anchors.fill: parent
            anchors.margins: 2
            interactive: false
            readOnly: true
            showSearch: false
            showTooltip: false
            showFocusRing: true
            focusNodeId: root._previewNodeId
            focusZoom: 5
        }
    }
}
