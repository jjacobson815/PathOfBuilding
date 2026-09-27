import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import "../components" as Widgets
import "../components/StatDiff.js" as StatDiff

// TREE view — the passive-tree tab: the embeddable TreeViewer plus legacy
// TreeTab's bottom control strip (TreeTab.lua:31-367).
//
// Phase 4 Part 4.2 — spec management:
//   * spec dropdown: every tree ("[ver] title"), then "Manage trees... (ctrl-m)"
//     (TreeTab.lua:39-50, 475-480); per-row hover tooltip = class/ascendancy/
//     points/sockets, switch stat-diff, respec gold, game version (:51-103).
//   * Up/Down cycle trees while the tree has focus (:394-405); Ctrl+M opens
//     the Manage Trees popup (:408).
// Phase 4 Part 4.3 — interaction & display:
//   * Compare checkbox + compare-tree dropdown (:106-124) -> green/red/blue
//     node tints and forced-active connectors in the renderer;
//   * Show Node Power + power-stat + max-depth dropdowns (:195-265), the
//     node-power job driven by a Timer (one BuildPower resume per tick; the
//     legacy progress toast comes through the toast mirror), Power Report
//     drawer (:268-294, 194px bottom drawer);
//   * hotkeys (PassiveTreeView.lua:182-205, TreeTab.lua:393-410): p heat map,
//     Ctrl+D stat diffs, Ctrl+C copy node, PgUp/PgDn zoom (Shift x3), F1 wiki,
//     Ctrl+F search; node-click follow-ups (class-change confirm, Items tab).
//
// Phase 4 Part 4.4 — popups: Reset Tree/Tattoos (:129-154), Version dropdown
//   + Convert / Copy + Convert (:156-175, 676-693), the "older tree version"
//   banner with Convert / Convert all (:349-367, 695-707), and the mastery
//   (:1038-1063) and tattoo/runegraft (:868-1017) popups opened from node clicks.
//
// STATE MODEL: `specState` / `powerState` cache bridge reads and are refreshed
// from engine signals only (no frame loop, invariant #7). Dropdown indices are
// pushed imperatively for the same reason TopBar does it.
Item {
    id: treeViewRoot
    anchors.fill: parent

    readonly property var _win: Window.window
    property var specState: ({})
    readonly property var specs: (specState && specState.specs && specState.specs.length !== undefined)
                                 ? specState.specs : []
    property var powerState: ({})
    property bool showPowerReport: false
    readonly property var depthValues: [0, 5, 10, 15]   // 0 = "All"

    function refreshSpecs() {
        if (luaEngine.currentMode !== "BUILD") return
        var st = luaEngine.invoke("pob_getSpecList", [])
        specState = st ? st : ({})
        var items = []
        var labels = []
        for (var i = 0; i < specs.length; i++) {
            items.push({ label: specs[i].label, specIndex: i + 1 })
            labels.push(specs[i].label)
        }
        items.push({ label: "Manage trees... (ctrl-m)", specIndex: -1 })
        specSelect.model = items
        specSelect.currentIndex = (specState.active || 1) - 1
        compareSelect.model = labels
        compareSelect.currentIndex = (specState.compare || 1) - 1
        compareCheck.state = !!specState.isComparing
    }

    property var versionState: ({})
    function refreshVersion() {
        if (luaEngine.currentMode !== "BUILD") return
        var v = luaEngine.invoke("pob_getVersionState", [])
        versionState = v ? v : ({})
        if (!v) return
        versionSelect.model = v.versions
        versionSelect.currentIndex = v.current - 1
    }

    function refreshPower() {
        if (luaEngine.currentMode !== "BUILD") return
        var p = luaEngine.invoke("pob_getPowerState", [])
        powerState = p ? p : ({})
        if (!p) return
        powerStatSelect.model = p.statLabels
        powerStatSelect.currentIndex = (p.statIndex || 1) - 1
        var d = depthValues.indexOf(p.maxDepth || 0)
        if (d < 0) { customDepth.visible = true; customDepth.text = String(p.maxDepth); d = 4 }
        depthSelect.currentIndex = d
        heatCheck.state = !!p.showHeatMap
        if (p.showHeatMap && p.running && !powerTimer.running) powerTimer.start()
        if (!p.showHeatMap) showPowerReport = false
        if (showPowerReport && !p.running) reportPanel.setReport(luaEngine.invoke("pob_getPowerReport", []))
    }

    function cycleSpec(delta) {
        if (specSelect.open) return
        luaEngine.invoke("pob_cycleSpec", [delta])
    }

    function openManage() { managePopup.openFresh() }

    function setHeatMap(on) {
        luaEngine.invoke("pob_setHeatMap", [on])
        refreshPower()
        if (on) powerTimer.start()
    }

    // Spec-row tooltip (TreeTab.lua:51-103).
    function specTooltip(item, tt) {
        if (!item || item.specIndex < 1) return
        var t = luaEngine.invoke("pob_getSpecTooltip", [item.specIndex])
        if (!t) return
        tt.addLine(16, "Class: " + t.className)
        tt.addLine(16, "Ascendancy: " + t.ascendClassName)
        tt.addLine(16, "Points used: " + t.used)
        if (t.sockets > 0) tt.addLine(16, "Jewel sockets: " + t.sockets)
        if (!t.isActive) {
            StatDiff.addToTooltip(tt, "^7Switching to this tree will give you:", t.stats, null)
            if (t.gold) {
                tt.addLine(16, "^xFFD700" + t.gold.totalStr + " Gold ^7required to switch to this tree.")
                if (t.gold.respec > 0)
                    tt.addLine(16, "^7    " + t.gold.respec + (t.gold.respec === 1 ? " Passive node to be refunded." : " Passive nodes to be refunded."))
                if (t.gold.respecAscendancy > 0)
                    tt.addLine(16, "^7    " + t.gold.respecAscendancy + (t.gold.respecAscendancy === 1 ? " Ascendancy node to be refunded." : " Ascendancy nodes to be refunded."))
            }
        }
        tt.addLine(16, "^7Game Version: " + t.versionDisplay)
    }

    // Follow-ups of a node click that need UI (pob_clickNode / pob_rightClickNode).
    function handleNodeAction(r) {
        if (r.action === "items") {
            luaEngine.setActiveView("ITEMS")
        } else if (r.action === "classConfirm") {
            classConfirm.pending = r
            classConfirm.message = r.message
            classConfirm.open()
        } else if (r.action === "mastery") {
            masteryPopup.openFor(r.nodeId, treeViewer.tracePath)
        } else if (r.action === "modify") {
            tattooPopup.openFor(r.nodeId)
        }
    }

    focus: true
    Keys.onPressed: function (event) {
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        var shift = (event.modifiers & Qt.ShiftModifier) !== 0
        var hover = treeViewer.hoverNodeId
        if (event.key === Qt.Key_Up && !ctrl) { cycleSpec(-1) }
        else if (event.key === Qt.Key_Down && !ctrl) { cycleSpec(1) }
        else if (event.key === Qt.Key_P && !ctrl) { setHeatMap(!powerState.showHeatMap) }
        else if (event.key === Qt.Key_D && ctrl) {
            luaEngine.invoke("pob_toggleStatDifferences", [])
            treeViewer.refreshHover()
        }
        else if (event.key === Qt.Key_C && ctrl && hover >= 0) {
            var txt = luaEngine.invoke("pob_getNodeCopyText", [hover])
            if (txt) luaEngine.copyText(txt)
        }
        else if (event.key === Qt.Key_PageUp) { treeViewer.zoomStep(shift ? 3 : 1) }
        else if (event.key === Qt.Key_PageDown) { treeViewer.zoomStep(shift ? -3 : -1) }
        else if (event.key === Qt.Key_F1 && hover >= 0) {
            var url = luaEngine.invoke("pob_getNodeWikiUrl", [hover])
            if (url) luaEngine.openURL(url)
        }
        else return
        event.accepted = true
    }

    Shortcut {
        sequence: "Ctrl+M"
        enabled: treeViewRoot.visible && luaEngine.currentMode === "BUILD"
        onActivated: treeViewRoot.openManage()
    }
    Shortcut {
        sequence: "Ctrl+F"
        enabled: treeViewRoot.visible && luaEngine.currentMode === "BUILD"
        onActivated: treeViewer.focusSearch()
    }

    Widgets.TreeViewer {
        id: treeViewer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: reportPanel.visible ? reportPanel.top : convertBanner.top
        controller: treeViewController
        interactive: true
        readOnly: false
        showSearch: true
        // Clicking the tree gives it key focus back (legacy routes unhandled
        // keys to the tab), so Up/Down cycle trees after using a text field.
        onActivated: treeViewRoot.forceActiveFocus()
        onNodeAction: function (r) { treeViewRoot.handleNodeAction(r) }
    }

    Widgets.PowerReportPanel {
        id: reportPanel
        visible: treeViewRoot.showPowerReport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: convertBanner.top
        height: 194
        // Legacy Focus() jumps to zoom level 12 (PassiveTreeView.lua:1264).
        onNodeSelected: function (id) { treeViewer.centerOnNode(id, Math.pow(1.2, 12)) }
    }

    // "Older tree version" banner (TreeTab.lua:349-367).
    Rectangle {
        id: convertBanner
        visible: !!treeViewRoot.versionState.showConvert
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bottomBar.top
        height: visible ? 26 : 0
        color: theme.sideBarBg
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            spacing: 8
            Widgets.Label { label: treeViewRoot.versionState.bannerText || ""; size: 16 }
            Widgets.Button {
                Layout.preferredWidth: textMetrics.width(16, "VAR", label) + 20
                Layout.preferredHeight: 20
                label: treeViewRoot.versionState.convertLabel || ""
                onClicked: {
                    var r = luaEngine.invoke("pob_convertTree", [treeViewRoot.versionState.convertTarget, false, true])
                    if (r && r.message) { convertDone.title = r.messageTitle; convertDone.message = r.message; convertDone.open() }
                }
            }
            Widgets.Button {
                Layout.preferredWidth: textMetrics.width(16, "VAR", label) + 20
                Layout.preferredHeight: 20
                label: treeViewRoot.versionState.convertAllLabel || ""
                onClicked: convertAllPopup.open()
            }
            Item { Layout.fillWidth: true }
        }
    }

    Rectangle {
        id: bottomBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 28
        color: theme.sideBarBg

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            spacing: 6

            Widgets.DropDownControl {
                id: specSelect
                Layout.preferredWidth: 190
                Layout.preferredHeight: 20
                popupMinWidth: 260
                tooltipForItem: treeViewRoot.specTooltip
                onSelected: function (index) {
                    var item = model[index]
                    if (item.specIndex < 1) {
                        // "Manage trees..." is not a selectable state.
                        currentIndex = (treeViewRoot.specState.active || 1) - 1
                        treeViewRoot.openManage()
                    } else {
                        luaEngine.invoke("pob_setActiveSpec", [item.specIndex])
                    }
                    treeViewRoot.forceActiveFocus()
                }
            }

            Widgets.CheckBox {
                id: compareCheck
                Layout.preferredHeight: 20
                Layout.preferredWidth: 20
                // The label draws to the LEFT of the box (legacy CheckBoxControl).
                Layout.leftMargin: labelWidth + 12
                label: "Compare:"
                onToggled: function (s) {
                    luaEngine.invoke("pob_setCompare", [s, compareSelect.currentIndex + 1])
                    treeViewer.refreshHover()
                }
            }
            Widgets.DropDownControl {
                id: compareSelect
                visible: compareCheck.state
                Layout.preferredWidth: 160
                Layout.preferredHeight: 20
                popupMinWidth: 240
                onSelected: function (index) {
                    luaEngine.invoke("pob_setCompare", [true, index + 1])
                    treeViewRoot.forceActiveFocus()
                }
            }

            Widgets.Button {
                Layout.preferredWidth: 145
                Layout.preferredHeight: 20
                label: "Reset Tree/Tattoos"
                onClicked: resetPopup.open()
            }
            Widgets.Label {
                label: "^7Version:"
                size: 16
            }
            Widgets.DropDownControl {
                id: versionSelect
                Layout.preferredWidth: 100
                Layout.preferredHeight: 20
                popupMinWidth: 200
                onSelected: function (index) {
                    var v = model[index]
                    if (v && v.value !== treeViewRoot.versionState.treeVersion) {
                        convertPopup.version = v.value
                        convertPopup.title = "Convert to Version " + v.label
                        convertPopup.open()
                    }
                    treeViewRoot.forceActiveFocus()
                }
            }

            Item { Layout.fillWidth: true }

            Widgets.CheckBox {
                id: heatCheck
                Layout.preferredHeight: 20
                Layout.preferredWidth: 20
                Layout.leftMargin: labelWidth + 12
                label: "Show Node Power:"
                tooltipFunc: function (tt) {
                    var theme = (treeViewRoot.powerState.theme || "RED/BLUE").split("/")
                    tt.addLine(14, "When enabled, an estimate of the offensive and defensive strength of")
                    tt.addLine(14, "each unallocated passive is calculated and displayed visually.")
                    tt.addLine(14, "Offensive power shows as " + theme[0].toLowerCase() + ", defensive power as " + theme[1].toLowerCase() + ".")
                }
                onToggled: function (s) { treeViewRoot.setHeatMap(s) }
            }
            // Max-depth dropdown + Custom edit (TreeTab.lua:208-249).
            Widgets.DropDownControl {
                id: depthSelect
                visible: heatCheck.state
                Layout.preferredWidth: customDepth.visible ? 70 : 60
                Layout.preferredHeight: 20
                tooltipText: "Limit of Node distance to search (lower = faster)"
                model: ["All", "5", "10", "15", "Custom"]
                onSelected: function (index) {
                    if (index === 4) { customDepth.visible = true; return }
                    customDepth.visible = false
                    var r = luaEngine.invoke("pob_setPowerMaxDepth", [treeViewRoot.depthValues[index]])
                    if (r && r.restarted) powerTimer.start()
                    treeViewRoot.forceActiveFocus()
                }
            }
            Widgets.EditControl {
                id: customDepth
                visible: false
                Layout.preferredWidth: 40
                Layout.preferredHeight: 20
                isNumeric: true
                onCommitted: function (text) {
                    var r = luaEngine.invoke("pob_setPowerMaxDepth", [Number(text) || 0])
                    if (r && r.restarted) powerTimer.start()
                }
            }
            Widgets.DropDownControl {
                id: powerStatSelect
                visible: heatCheck.state
                Layout.preferredWidth: 150
                Layout.preferredHeight: 20
                popupMinWidth: 220
                onSelected: function (index) {
                    luaEngine.invoke("pob_setPowerStat", [index + 1])
                    treeViewRoot.refreshPower()
                    powerTimer.start()
                    treeViewRoot.forceActiveFocus()
                }
            }
            Widgets.Button {
                visible: heatCheck.state
                Layout.preferredWidth: 130
                Layout.preferredHeight: 20
                label: treeViewRoot.showPowerReport ? "Hide Power Report" : "Show Power Report"
                onClicked: {
                    treeViewRoot.showPowerReport = !treeViewRoot.showPowerReport
                    if (treeViewRoot.showPowerReport)
                        reportPanel.setReport(luaEngine.invoke("pob_getPowerReport", []))
                }
            }
        }
    }

    // One BuildPower resume per tick (~100ms of work each, as legacy per
    // frame). Stops itself when the job is done or the heat map is off; any
    // edit restarts it (BuildOutput re-arms powerBuildFlag).
    Timer {
        id: powerTimer
        interval: 1
        repeat: true
        onTriggered: {
            var r = luaEngine.invoke("pob_powerStep", [])
            if (!r || !r.running) {
                stop()
                treeViewRoot.refreshPower()
            }
        }
    }

    Widgets.SpecManagePopup {
        id: managePopup
        parent: treeViewRoot._win ? treeViewRoot._win.contentItem : treeViewRoot
        onListEdited: treeViewRoot.refreshSpecs()
        onClosed: treeViewRoot.forceActiveFocus()
    }

    Widgets.MasteryPopup {
        id: masteryPopup
        parent: treeViewRoot._win ? treeViewRoot._win.contentItem : treeViewRoot
        onClosed: treeViewRoot.forceActiveFocus()
    }
    Widgets.TattooPopup {
        id: tattooPopup
        parent: treeViewRoot._win ? treeViewRoot._win.contentItem : treeViewRoot
        onClosed: treeViewRoot.forceActiveFocus()
    }

    // Reset Tree/Tattoos (TreeTab.lua:129-154).
    Widgets.ConfirmPopup {
        id: resetPopup
        parent: treeViewRoot._win ? treeViewRoot._win.contentItem : treeViewRoot
        title: "Reset Tree/Tattoos"
        message: "^7Warning: resetting your passive tree or removing all tattoos cannot be undone."
        confirmLabel: "Reset Tree"
        extraLabel: "Remove All Tattoos"
        onAccepted: luaEngine.invoke("pob_resetTree", [])
        onExtraClicked: { resetPopup.close(); luaEngine.invoke("pob_removeAllTattoos", []) }
    }

    // Version dropdown -> OpenVersionConvertPopup (TreeTab.lua:676-693).
    Widgets.ConfirmPopup {
        id: convertPopup
        property string version: ""
        parent: treeViewRoot._win ? treeViewRoot._win.contentItem : treeViewRoot
        message: "^7Warning: some or all of the passives may be de-allocated due to changes in the tree.\n\nConvert will replace your current tree.\nCopy + Convert will backup your current tree."
        confirmLabel: "Convert"
        extraLabel: "Copy + Convert"
        onAccepted: luaEngine.invoke("pob_convertTree", [version, true, false])
        onExtraClicked: { convertPopup.close(); luaEngine.invoke("pob_convertTree", [version, false, false]) }
        onRejected: treeViewRoot.refreshVersion()
    }

    // Banner "Convert all" (TreeTab.lua:695-707).
    Widgets.ConfirmPopup {
        id: convertAllPopup
        parent: treeViewRoot._win ? treeViewRoot._win.contentItem : treeViewRoot
        title: "Convert all to Version " + (treeViewRoot.versionState.convertTargetDisplay || "")
        message: "^7Warning: some or all of the passives may be de-allocated due to changes in the tree.\n\nConvert will replace all trees that are not Version " + (treeViewRoot.versionState.convertTargetDisplay || "") + ".\nThis action cannot be undone."
        confirmLabel: "Convert"
        onAccepted: luaEngine.invoke("pob_convertAllTrees", [treeViewRoot.versionState.convertTarget])
    }

    Widgets.MessagePopup {
        id: convertDone
        parent: treeViewRoot._win ? treeViewRoot._win.contentItem : treeViewRoot
    }

    // Class Change confirm for an ascendancy node of another class
    // (PassiveTreeView.lua:459-476): Continue / Connect Path / Cancel.
    Widgets.ConfirmPopup {
        id: classConfirm
        property var pending: null
        parent: treeViewRoot._win ? treeViewRoot._win.contentItem : treeViewRoot
        title: "Class Change"
        confirmLabel: "Continue"
        extraLabel: "Connect Path"
        onAccepted: {
            var p = pending
            if (p) luaEngine.invoke("pob_confirmNodeClassChange", [p.nodeId, p.targetClassId, p.targetAscendClassId, "continue"])
            pending = null
        }
        onExtraClicked: {
            var p = pending
            classConfirm.close()
            if (p) luaEngine.invoke("pob_confirmNodeClassChange", [p.nodeId, p.targetClassId, p.targetAscendClassId, "connect"])
            pending = null
        }
        onRejected: pending = null
    }

    Component.onCompleted: { refreshSpecs(); refreshPower(); refreshVersion() }

    Connections {
        target: luaEngine
        function onTreeChanged() { treeViewRoot.refreshSpecs(); treeViewRoot.refreshPower(); treeViewRoot.refreshVersion() }
        function onBuildDataChanged() { treeViewRoot.refreshSpecs() }
        function onModeChanged() { treeViewRoot.refreshSpecs(); treeViewRoot.refreshPower(); treeViewRoot.refreshVersion() }
        // Any recalc re-arms the power job (CalcsTab:BuildOutput).
        function onCalcsChanged() { if (treeViewRoot.powerState.showHeatMap) powerTimer.start() }
    }
}
