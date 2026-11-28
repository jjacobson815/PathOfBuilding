import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import "QmlBridge.js" as QmlBridge

// SpectreLibraryPopup — Phase 3 long-tail, ports Build.lua's Spectre Library
// (Build.lua:1415-1841): dual-pane Spectres in Build / Available Spectres
// with drag-to-add, 6 monster-category toggles, Corpse Only + Show All
// checkboxes, Search + SearchMode + 12-mode Sort dropdowns, and right-hand
// Minion Stats panel with Gem Level (1-40), stat cards, Spawns list, and
// hover tooltips.
PopupBase {
    id: root

    title: "Spectre Library"
    padding: 12
    acceptOnEnter: false

    signal spectresSaved()

    property var spectreList: []
    property var available: []
    property var categories: []
    property var searchModes: ["Names", "Skills", "Both"]
    property var sortModes: []
    property int totalSpectres: 0
    property int filteredCount: 0

    property int buildSel: -1
    property int availSel: -1
    readonly property int buildCount: QmlBridge.toArray(spectreList).length
    readonly property int availCount: QmlBridge.toArray(available).length
    readonly property bool hasBuildSel: buildSel >= 0 && buildSel < buildCount
    readonly property bool hasAvailSel: availSel >= 0 && availSel < availCount

    property string searchText: ""
    property int searchMode: 1
    property int sortMode: 1
    property bool corpseOnly: false
    property bool showAll: false
    property var enabledCats: ({
        Beast: true, Humanoid: true, Eldritch: true,
        Construct: true, Demon: true, Undead: true
    })

    property int gemLevel: 20
    property string selectedMinionId: ""
    property var minionStats: ({})
    readonly property var spawnLocations:
        (minionStats && minionStats.spawnLocations) ? QmlBridge.toArray(minionStats.spawnLocations) : []

    function fileUrl(p) {
        if (!p) return ""
        var norm = String(p).replace(/\\/g, "/")
        return (norm.charAt(0) === "/" ? "file://" : "file:///") + norm
    }

    function _fillTooltipLines(tip, res) {
        tip.clear()
        var lines = res ? QmlBridge.toArray(res.lines) : []
        if (!lines.length) return
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i]
            if (l.separator || l.sep) tip.addSeparator(l.size || 2)
            else tip.addLine(l.size || 14, l.text && l.text.length > 0 ? l.text : " ", l.font, l.center === true)
        }
    }

    function _showTipAt(tip, item) {
        var win = item ? item.Window.window : null
        var o = win ? item.mapToItem(win.contentItem, 0, 0) : Qt.point(0, 0)
        var vp = win ? Qt.rect(-o.x, -o.y, win.width, win.height) : Qt.rect(0, 0, item.width, item.height)
        tip.showAt(0, 0, item.width, item.height, vp)
    }

    function openFresh() {
        buildSel = -1
        availSel = -1
        searchText = ""
        searchMode = 1
        sortMode = 1
        corpseOnly = false
        showAll = false
        enabledCats = {
            Beast: true, Humanoid: true, Eldritch: true,
            Construct: true, Demon: true, Undead: true
        }
        gemLevel = 20
        selectedMinionId = ""
        minionStats = ({})

        searchEdit.text = ""
        corpseCheck.state = false
        showAllCheck.state = false
        gemLevelEdit.text = "20"

        var st = luaEngine.invoke("pob_spectresGetState", [_buildQueryOpts()])
        _applyQueryResult(st, true)
        searchModeDrop.currentIndex = 0
        sortModeDrop.currentIndex = 0
        open()
    }

    function _buildQueryOpts() {
        return {
            search: searchText,
            searchMode: searchMode,
            sortMode: sortMode,
            corpseOnly: corpseOnly,
            showAll: showAll,
            categories: enabledCats
        }
    }

    function _applyQueryResult(st, syncBuildList) {
        if (!st || !st.ok) return
        if (syncBuildList)
            spectreList = QmlBridge.toArray(st.spectreList)
        available = QmlBridge.toArray(st.available)
        categories = QmlBridge.toArray(st.categories)
        var sModes = QmlBridge.toArray(st.searchModes)
        searchModes = sModes.length > 0 ? sModes : ["Names", "Skills", "Both"]
        sortModes = QmlBridge.toArray(st.sortModes)
        totalSpectres = st.totalSpectres || 0
        filteredCount = st.filteredCount || 0
        if (availSel >= availCount) availSel = availCount - 1

        if (selectedMinionId.length === 0) {
            if (buildCount > 0) _selectMinion(spectreList[0].id)
            else if (availCount > 0) _selectMinion(available[0].id)
        }
    }

    function _requery() {
        var st = luaEngine.invoke("pob_spectresQuery", [_buildQueryOpts()])
        _applyQueryResult(st, false)
    }

    function _selectMinion(minionId) {
        if (!minionId) {
            selectedMinionId = ""
            minionStats = ({})
            return
        }
        selectedMinionId = minionId
        var res = luaEngine.invoke("pob_spectresGetMinionStats", [minionId, gemLevel])
        minionStats = (res && res.ok) ? res : ({})
    }

    function _addEntry(entry) {
        if (!entry || !entry.id) return
        for (var i = 0; i < buildCount; i++) {
            if (spectreList[i].id === entry.id) {
                buildSel = i
                availSel = -1
                _selectMinion(entry.id)
                return
            }
        }
        var next = spectreList.slice()
        next.push(entry)
        spectreList = next
        buildSel = next.length - 1
        availSel = -1
        _selectMinion(entry.id)
    }

    function _addSelected() {
        if (!hasAvailSel) return
        _addEntry(available[availSel])
    }

    function _removeSelected() {
        if (!hasBuildSel) return
        var next = spectreList.slice()
        next.splice(buildSel, 1)
        spectreList = next
        if (buildSel >= next.length) buildSel = next.length - 1
        if (buildSel >= 0) _selectMinion(next[buildSel].id)
    }

    function _toggleCategory(key) {
        var next = Object.assign({}, enabledCats)
        next[key] = !next[key]
        enabledCats = next
        _requery()
    }

    function _save() {
        var ids = []
        for (var i = 0; i < buildCount; i++) ids.push(spectreList[i].id)
        var res = luaEngine.invoke("pob_spectresSave", [ids])
        if (res && res.ok) {
            spectresSaved()
            accept()
        }
    }

    ColumnLayout {
        spacing: 8

        RowLayout {
            spacing: 10
            Layout.preferredWidth: 920
            Layout.preferredHeight: 440

            // ===== Left pane: Spectres in Build =====
            ColumnLayout {
                Layout.preferredWidth: 220
                Layout.fillHeight: true
                spacing: 4

                RowLayout {
                    spacing: 6
                    Label { label: "^7Spectres in Build"; size: 14 }
                    Item { Layout.fillWidth: true }
                    Button {
                        objectName: "pob.spectres.removeBtn"
                        implicitWidth: 64; implicitHeight: 18
                        label: "Remove"
                        controlEnabled: root.hasBuildSel
                        onClicked: root._removeSelected()
                    }
                }

                Rectangle {
                    id: buildListBox
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "transparent"
                    border.width: 1
                    border.color: buildDrop.containsDrag ? theme.success : theme.border
                    clip: true
                    focus: true

                    Keys.onPressed: function (event) {
                        if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && root.hasBuildSel) {
                            root._removeSelected()
                            event.accepted = true
                        }
                    }

                    ListView {
                        id: buildListView
                        objectName: "pob.spectres.buildList"
                        anchors.fill: parent
                        anchors.margins: 2
                        cacheBuffer: 0
                        model: root.spectreList
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            width: buildListView.width
                            height: 18
                            color: index === root.buildSel ? theme.active
                                 : buildRowMa.containsMouse ? theme.hover : "transparent"

                            Label {
                                anchors.left: parent.left
                                anchors.leftMargin: 4
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                label: "^7" + (modelData.name || modelData.id)
                                size: 14
                            }

                            MouseArea {
                                id: buildRowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    root.buildSel = index
                                    root.availSel = -1
                                    root._selectMinion(modelData.id)
                                    buildListBox.forceActiveFocus()
                                }
                                onContainsMouseChanged: {
                                    if (!containsMouse) { buildTip.hide(); return }
                                    root._fillTooltipLines(buildTip, luaEngine.invoke("pob_spectresGetMinionTooltip", [modelData.id]))
                                    if (buildTip.lines.length > 0) root._showTipAt(buildTip, buildRowMa)
                                }
                            }
                            Tooltip { id: buildTip }
                        }
                    }

                    DropArea {
                        id: buildDrop
                        anchors.fill: parent
                        keys: ["Spectre"]
                        onEntered: function (drag) {
                            drag.accepted = !!drag.source && drag.source.dragValue && drag.source.dragValue.kind === "available"
                        }
                        onDropped: function (ev) {
                            if (ev.source && ev.source.dragValue && ev.source.dragValue.entry)
                                root._addEntry(ev.source.dragValue.entry)
                        }
                    }
                }
            }

            // ===== Center pane: Available Spectres =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4

                RowLayout {
                    spacing: 6
                    Button {
                        objectName: "pob.spectres.addBtn"
                        implicitWidth: 50; implicitHeight: 20
                        label: "Add"
                        controlEnabled: root.hasAvailSel
                        onClicked: root._addSelected()
                    }
                    EditControl {
                        id: searchEdit
                        objectName: "pob.spectres.searchEdit"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        placeholder: "Search spectres..."
                        onEdited: (t) => {
                            root.searchText = t
                            root._requery()
                        }
                    }
                    DropDownControl {
                        id: searchModeDrop
                        objectName: "pob.spectres.searchMode"
                        Layout.preferredWidth: 85
                        Layout.preferredHeight: 20
                        model: root.searchModes
                        onSelected: (i) => {
                            root.searchMode = i + 1
                            root._requery()
                        }
                    }
                    DropDownControl {
                        id: sortModeDrop
                        objectName: "pob.spectres.sortMode"
                        Layout.preferredWidth: 165
                        Layout.preferredHeight: 20
                        model: root.sortModes
                        onSelected: (i) => {
                            root.sortMode = i + 1
                            root._requery()
                        }
                    }
                }

                // Category toggles + Corpse Only / Show All
                RowLayout {
                    spacing: 6
                    Layout.fillWidth: true

                    Repeater {
                        model: root.categories
                        delegate: Rectangle {
                            objectName: "pob.spectres.catToggle"
                            readonly property bool active: root.enabledCats[modelData.key] === true
                            width: 24
                            height: 24
                            radius: theme.radiusControl
                            color: active ? theme.active : "transparent"
                            border.width: 1
                            border.color: catMa.containsMouse ? theme.borderStrong
                                        : active ? theme.accent : theme.border

                            Image {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                source: root.fileUrl(modelData.icon)
                                fillMode: Image.PreserveAspectFit
                                opacity: parent.active ? 1.0 : 0.4
                            }

                            MouseArea {
                                id: catMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root._toggleCategory(modelData.key)
                                onContainsMouseChanged: {
                                    if (!containsMouse) { catTip.hide(); return }
                                    catTip.clear()
                                    catTip.addLine(14, modelData.label + (parent.active ? " (Shown)" : " (Hidden)"))
                                    root._showTipAt(catTip, catMa)
                                }
                            }
                            Tooltip { id: catTip }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    CheckBox {
                        id: corpseCheck
                        objectName: "pob.spectres.corpseCheck"
                        implicitHeight: 18; implicitWidth: 18
                        label: "Corpse Only"
                        onToggled: (s) => {
                            root.corpseOnly = s
                            root._requery()
                        }
                    }

                    Item { Layout.preferredWidth: 8 }

                    CheckBox {
                        id: showAllCheck
                        objectName: "pob.spectres.showAllCheck"
                        implicitHeight: 18; implicitWidth: 18
                        label: "Show All"
                        onToggled: (s) => {
                            root.showAll = s
                            root._requery()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "transparent"
                    border.width: 1
                    border.color: theme.border
                    clip: true

                    ListView {
                        id: availListView
                        objectName: "pob.spectres.availList"
                        anchors.fill: parent
                        anchors.margins: 2
                        cacheBuffer: 0
                        model: root.available
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            width: availListView.width
                            height: 18
                            color: index === root.availSel ? theme.active
                                 : availRowMa.containsMouse ? theme.hover : "transparent"

                            Label {
                                anchors.left: parent.left
                                anchors.leftMargin: 4
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                label: (modelData.recommended ? "^7" : "^8") + (modelData.name || modelData.id)
                                size: 14
                            }

                            MouseArea {
                                id: availRowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                property real pressX: 0
                                property real pressY: 0
                                onPressed: function (mouse) {
                                    pressX = mouse.x
                                    pressY = mouse.y
                                    availTip.hide()
                                }
                                onPositionChanged: function (mouse) {
                                    if (ghost.active) { availTip.hide(); ghost.moveTo(availRowMa, mouse.x, mouse.y); return }
                                    var dx = mouse.x - pressX, dy = mouse.y - pressY
                                    if (pressed && dx * dx + dy * dy > 100) {
                                        availTip.hide()
                                        ghost.start(availRowMa, mouse.x, mouse.y, "Spectre",
                                                    { kind: "available", entry: modelData },
                                                    modelData.name || modelData.id)
                                    }
                                }
                                onReleased: if (ghost.active) ghost.finish()
                                onClicked: {
                                    root.availSel = index
                                    root.buildSel = -1
                                    root._selectMinion(modelData.id)
                                }
                                onDoubleClicked: root._addEntry(modelData)
                                onContainsMouseChanged: {
                                    if (!containsMouse || ghost.active) { availTip.hide(); return }
                                    root._fillTooltipLines(availTip, luaEngine.invoke("pob_spectresGetMinionTooltip", [modelData.id]))
                                    if (availTip.lines.length > 0) root._showTipAt(availTip, availRowMa)
                                }
                            }
                            Tooltip { id: availTip }
                        }
                    }
                }

                Label {
                    label: "^8Showing " + root.filteredCount + " / " + root.totalSpectres + " spectres"
                    size: 13
                }
            }

            // ===== Right pane: Minion Stats =====
            ColumnLayout {
                Layout.preferredWidth: 260
                Layout.fillHeight: true
                spacing: 6

                RowLayout {
                    spacing: 6
                    Label { label: "^7Minion Stats"; size: 14 }
                    Item { Layout.fillWidth: true }
                    Label { label: "^7Gem Level:"; size: 13 }
                    EditControl {
                        id: gemLevelEdit
                        objectName: "pob.spectres.gemLevel"
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 20
                        isNumeric: true
                        numericMin: 1
                        numericMax: 40
                        maxChars: 2
                        horizontalAlignment: TextInput.AlignHCenter
                        onCommitted: (val) => {
                            var n = parseInt(val, 10)
                            if (isNaN(n)) n = 20
                            n = Math.max(1, Math.min(40, n))
                            root.gemLevel = n
                            gemLevelEdit.text = String(n)
                            if (root.selectedMinionId.length > 0)
                                root._selectMinion(root.selectedMinionId)
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "transparent"
                    border.width: 1
                    border.color: theme.border

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            label: root.minionStats.name ? ("^7" + root.minionStats.name) : "^8Select a spectre"
                            size: 15
                        }

                        Label {
                            visible: root.minionStats.minionLevel !== undefined
                            label: "^8Monster Level: ^7" + (root.minionStats.minionLevel || "")
                            size: 13
                        }

                        GridLayout {
                            columns: 2
                            columnSpacing: 8
                            rowSpacing: 3
                            Layout.fillWidth: true
                            visible: root.minionStats.life !== undefined

                            Label { label: "^8Life:"; size: 13 }
                            Label { label: "^7" + (root.minionStats.life !== undefined ? root.minionStats.life : ""); size: 13 }

                            Label { label: "^8Energy Shield:"; size: 13 }
                            Label { label: "^7" + (root.minionStats.energyShield !== undefined ? root.minionStats.energyShield : ""); size: 13 }

                            Label { label: "^8Armour:"; size: 13 }
                            Label { label: "^7" + (root.minionStats.armour !== undefined ? root.minionStats.armour : ""); size: 13 }

                            Label { label: "^8Evasion:"; size: 13 }
                            Label { label: "^7" + (root.minionStats.evasion !== undefined ? root.minionStats.evasion : ""); size: 13 }

                            Label { label: "^8Block:"; size: 13 }
                            Label { label: "^7" + (root.minionStats.blockText || ""); size: 13 }

                            Label { label: "^8Resists:"; size: 13 }
                            Label { label: root.minionStats.resistsText || ""; size: 13 }

                            Label { label: "^8Movement Speed:"; size: 13 }
                            Label { label: "^7" + (root.minionStats.movementSpeedText || ""); size: 13 }
                        }

                        Label {
                            Layout.topMargin: 4
                            label: "^7Spawns:"
                            size: 13
                            visible: root.spawnLocations.length > 0
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "transparent"
                            border.width: 1
                            border.color: theme.border
                            visible: root.spawnLocations.length > 0
                            clip: true

                            ListView {
                                id: spawnListView
                                anchors.fill: parent
                                anchors.margins: 2
                                cacheBuffer: 0
                                model: root.spawnLocations
                                boundsBehavior: Flickable.StopAtBounds

                                delegate: Rectangle {
                                    width: spawnListView.width
                                    height: 16
                                    color: spawnMa.containsMouse ? theme.hover : "transparent"

                                    Label {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 4
                                        anchors.right: parent.right
                                        anchors.rightMargin: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        label: "^7" + modelData
                                        size: 13
                                    }

                                    MouseArea {
                                        id: spawnMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onContainsMouseChanged: {
                                            if (!containsMouse) { spawnTip.hide(); return }
                                            root._fillTooltipLines(spawnTip, luaEngine.invoke("pob_spectresGetSpawnTooltip", [modelData]))
                                            if (spawnTip.lines.length > 0) root._showTipAt(spawnTip, spawnMa)
                                        }
                                    }
                                    Tooltip { id: spawnTip }
                                }
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                            visible: root.spawnLocations.length === 0
                        }

                        Label { label: "^8Double-click or drag to add a spectre."; size: 12 }
                        Label { label: "^8Hover a spectre or spawn area for details."; size: 12 }
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            PopupButton {
                objectName: "pob.spectres.saveBtn"
                label: "Save"
                onClicked: root._save()
            }
            PopupButton {
                label: "Cancel"
                onClicked: root.reject()
            }
        }
    }

    DragGhost { id: ghost }
}
