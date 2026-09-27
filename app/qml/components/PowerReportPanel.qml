import QtQuick
import QtQuick.Layouts

// PowerReportPanel — Phase 4 Part 4.3, ports PowerReportListControl
// (Classes/PowerReportListControl.lua) over pob_getPowerReport rows
// (TreeTab:BuildPowerReportList). Columns Type / Node Name / <stat> / Points /
// Per Point; click a sortable header to sort (descending, ascending in
// "Show Allocated" mode); the filter dropdown and "Show Masteries" check
// re-filter; clicking a row raises nodeSelected(id) (legacy jumps the tree).
Rectangle {
    id: root

    signal nodeSelected(int nodeId)

    property var report: ({ rows: [], label: "" })
    property int filterIndex: 0        // 0 unalloc, 1 unalloc + clusters, 2 allocated
    property bool showMasteries: true
    property int sortCol: 3            // legacy ReSort(3) default
    property var shown: []

    color: theme.sideBarBg
    border.color: theme.border
    border.width: 1

    // Column fractions of legacy's 700px list (:11-28).
    readonly property var colFrac: [0.15, 0.45, 0.16, 0.05, 0.16]
    readonly property var sortable: [true, false, true, true, true]

    function setReport(r) {
        report = r || ({ rows: [], label: "" })
        relist()
    }

    // ReList (:98-120) then ReSort (:58-96).
    function relist() {
        const rows = (report.rows && report.rows.length !== undefined) ? report.rows : []
        const allocated = filterIndex === 2
        const showClusters = filterIndex === 1
        const out = []
        for (let i = 0; i < rows.length; i++) {
            const it = rows[i]
            let insert = allocated ? it.allocated : (it.power > 0 && (showClusters || it.pathDist !== "Cluster"))
            if (insert && !showMasteries && it.type === "Mastery") insert = false
            if (insert) out.push(it)
        }
        const dir = allocated ? 1 : -1
        const num = function (v) { return typeof v === "number" ? v : Number.MAX_VALUE }
        const cmpPower = function (a, b) { return dir * (a.power - b.power) }
        let cmp
        switch (sortCol) {
        case 1: cmp = function (a, b) { return a.type === b.type ? cmpPower(a, b) : (a.type < b.type ? -1 : 1) }; break
        case 4: cmp = function (a, b) {
                const da = num(a.pathDist === 1000 ? "Anoint" : a.pathDist), db = num(b.pathDist === 1000 ? "Anoint" : b.pathDist)
                return da === db ? cmpPower(a, b) : da - db }; break
        case 5: cmp = function (a, b) {
                return a.pathPower === b.pathPower ? num(a.pathDist) - num(b.pathDist) : dir * (a.pathPower - b.pathPower) }; break
        default: cmp = cmpPower
        }
        out.sort(cmp)
        shown = out
    }

    function colWidth(i) { return Math.floor((root.width - 12) * colFrac[i]) }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 3

        RowLayout {
            spacing: 8
            Label {
                label: root.report.label || ""
                size: 14
            }
            Item { Layout.fillWidth: true }
            CheckBox {
                Layout.preferredHeight: 18
                Layout.preferredWidth: 18
                Layout.leftMargin: labelWidth + 6
                label: "Show Masteries:"
                state: root.showMasteries
                onToggled: function (s) { root.showMasteries = s; root.relist() }
            }
            DropDownControl {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 18
                model: ["Show Unallocated", "Show Unallocated & Clusters", "Show Allocated"]
                currentIndex: root.filterIndex
                onSelected: function (i) { root.filterIndex = i; root.sortCol = 3; root.relist() }
            }
        }

        // Header
        Row {
            spacing: 0
            Repeater {
                model: ["Type", "Node Name", root.report.statLabel || "Power", "Points", "Per Point"]
                delegate: Rectangle {
                    width: root.colWidth(index)
                    height: 18
                    color: root.sortCol === index + 1 ? theme.active : theme.titleBar
                    border.color: theme.border
                    Label { anchors.centerIn: parent; label: modelData; size: 13 }
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.sortable[index]
                        onClicked: { root.sortCol = index + 1; root.relist() }
                    }
                }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.shown
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                width: list.width
                height: 16
                color: rowMa.containsMouse ? theme.hover : "transparent"
                Row {
                    Label { width: root.colWidth(0); label: modelData.type || ""; size: 13; clip: true }
                    Label { width: root.colWidth(1); label: modelData.name || ""; size: 13; clip: true }
                    Label { width: root.colWidth(2); label: modelData.powerStr || ""; size: 13; clip: true }
                    Label { width: root.colWidth(3); size: 13; clip: true
                            label: modelData.pathDist === 1000 ? "Anoint" : String(modelData.pathDist) }
                    Label { width: root.colWidth(4); label: modelData.pathPowerStr || ""; size: 13; clip: true }
                }
                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: if (modelData.id !== undefined) root.nodeSelected(modelData.id)
                }
            }
        }
    }
}
