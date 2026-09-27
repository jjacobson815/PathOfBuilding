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
//
// STATE MODEL: `specState` caches pob_getSpecList() and is refreshed from the
// engine signals only (no frame loop, invariant #7). The dropdown's
// currentIndex is pushed imperatively for the same reason TopBar does it.
Item {
    id: treeViewRoot
    anchors.fill: parent

    readonly property var _win: Window.window
    property var specState: ({})
    readonly property var specs: (specState && specState.specs && specState.specs.length !== undefined)
                                 ? specState.specs : []

    function refreshSpecs() {
        if (luaEngine.currentMode !== "BUILD") return
        var st = luaEngine.invoke("pob_getSpecList", [])
        specState = st ? st : ({})
        var items = []
        for (var i = 0; i < specs.length; i++) items.push({ label: specs[i].label, specIndex: i + 1 })
        items.push({ label: "Manage trees... (ctrl-m)", specIndex: -1 })
        specSelect.model = items
        specSelect.currentIndex = (specState.active || 1) - 1
    }

    function cycleSpec(delta) {
        if (specSelect.open) return
        luaEngine.invoke("pob_cycleSpec", [delta])
    }

    function openManage() { managePopup.openFresh() }

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

    focus: true
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Up) { cycleSpec(-1); event.accepted = true }
        else if (event.key === Qt.Key_Down) { cycleSpec(1); event.accepted = true }
    }

    Shortcut {
        sequence: "Ctrl+M"
        enabled: treeViewRoot.visible && luaEngine.currentMode === "BUILD"
        onActivated: treeViewRoot.openManage()
    }

    Widgets.TreeViewer {
        id: treeViewer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: bottomBar.top
        controller: treeViewController
        interactive: true
        readOnly: false
        showSearch: true
        // Clicking the tree gives it key focus back (legacy routes unhandled
        // keys to the tab), so Up/Down cycle trees after using a text field.
        onActivated: treeViewRoot.forceActiveFocus()
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

            Item { Layout.fillWidth: true }
        }
    }

    Widgets.SpecManagePopup {
        id: managePopup
        parent: treeViewRoot._win ? treeViewRoot._win.contentItem : treeViewRoot
        onListEdited: treeViewRoot.refreshSpecs()
        onClosed: treeViewRoot.forceActiveFocus()
    }

    Component.onCompleted: refreshSpecs()
    Connections {
        target: luaEngine
        function onTreeChanged() { treeViewRoot.refreshSpecs() }
        function onBuildDataChanged() { treeViewRoot.refreshSpecs() }
        function onModeChanged() { treeViewRoot.refreshSpecs() }
    }
}
