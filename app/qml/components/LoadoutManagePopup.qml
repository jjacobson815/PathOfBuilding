import QtQuick
import QtQuick.Layouts

// LoadoutManagePopup — Phase 3 long-tail, ports BuildSetListControl.lua:
// loadout list with (Current) marker, double-click activate, F2 rename,
// New / Rename / Copy (with duplicate-name guard), Delete (disabled when
// <= 1 loadout), Up / Down reorder, and New/Copy Custom sub-popup with
// 4 set dropdowns (Tree, Skill Set, Item Set, Config Set, each starting
// with "New").
PopupBase {
    id: root

    title: "Manage Loadouts"
    padding: 12

    signal loadoutsChanged()

    property var rows: []
    property int selIndex: -1
    readonly property int count: Array.isArray(rows) ? rows.length : 0
    readonly property bool hasSel: selIndex >= 0 && selIndex < count
    property bool canDelete: false
    property var availableSets: ({ trees: [], skills: [], items: [], configs: [] })
    property var specNameLookup: ({})
    property string _nameMode: ""

    readonly property var _trees: Array.isArray(availableSets.trees) ? availableSets.trees : []
    readonly property var _skills: Array.isArray(availableSets.skills) ? availableSets.skills : []
    readonly property var _items: Array.isArray(availableSets.items) ? availableSets.items : []
    readonly property var _configs: Array.isArray(availableSets.configs) ? availableSets.configs : []

    function openFresh() {
        selIndex = -1
        refresh()
        open()
    }

    function refresh() {
        var st = luaEngine.invoke("pob_loadoutsGetState", [])
        if (!st || !st.ok) {
            rows = []
            canDelete = false
            availableSets = { trees: [], skills: [], items: [], configs: [] }
            specNameLookup = {}
            selIndex = -1
            return
        }
        rows = Array.isArray(st.rows) ? st.rows : []
        canDelete = st.canDelete === true
        availableSets = st.availableSets || { trees: [], skills: [], items: [], configs: [] }
        specNameLookup = st.specNameLookup || {}
        if (selIndex >= count) selIndex = count - 1
        if (selIndex < 0 && st.activeLoadoutIndex0 !== undefined && st.activeLoadoutIndex0 >= 0 && st.activeLoadoutIndex0 < count)
            selIndex = st.activeLoadoutIndex0
    }

    function _isDuplicateName(name) {
        if (!name) return false
        if (specNameLookup && specNameLookup[name] === true) return true
        for (var i = 0; i < count; i++) {
            if (rows[i].title === name) return true
        }
        return false
    }

    function _showError(msg) {
        errorPopup.message = "^1" + (msg || "Operation failed.")
        errorPopup.open()
    }

    function _askName(mode, initial) {
        _nameMode = mode
        if (mode === "new") namePopup.title = "New Loadout"
        else if (mode === "copy") namePopup.title = "Copy Loadout"
        else namePopup.title = "Rename Loadout"
        namePopup.text = initial || ""
        namePopup.open()
    }

    function _nameAccepted(text) {
        var res = null
        if (_nameMode === "new") {
            res = luaEngine.invoke("pob_loadoutsNew", [text])
        } else if (_nameMode === "copy" && hasSel) {
            res = luaEngine.invoke("pob_loadoutsCopy", [rows[selIndex].fullName, text])
        } else if (_nameMode === "rename" && hasSel) {
            res = luaEngine.invoke("pob_loadoutsRename", [rows[selIndex].fullName, text])
        }
        if (res && !res.ok) {
            _showError(res.error)
            return
        }
        refresh()
        loadoutsChanged()
    }

    function _move(delta) {
        if (!hasSel) return
        var to = selIndex + delta
        if (to < 0 || to >= count) return
        var res = luaEngine.invoke("pob_loadoutsReorder", [selIndex + 1, to + 1])
        if (res && !res.ok) {
            _showError(res.error)
            return
        }
        if (res && res.ok) selIndex = to
        refresh()
        loadoutsChanged()
    }

    ColumnLayout {
        implicitWidth: 420
        spacing: 6
        focus: true

        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_F2 && root.hasSel) {
                root._askName("rename", root.rows[root.selIndex].title)
                event.accepted = true
            } else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)
                       && root.hasSel && root.canDelete && root.count > 1) {
                deleteConfirm.openFor(root.selIndex)
                event.accepted = true
            }
        }

        RowLayout {
            spacing: 4
            Button {
                implicitWidth: 54; implicitHeight: 18
                label: "New"
                onClicked: root._askName("new", "")
            }
            Button {
                implicitWidth: 64; implicitHeight: 18
                label: "Rename"
                controlEnabled: root.hasSel
                onClicked: root._askName("rename", root.rows[root.selIndex].title)
            }
            Button {
                implicitWidth: 54; implicitHeight: 18
                label: "Copy"
                controlEnabled: root.hasSel
                onClicked: root._askName("copy", root.rows[root.selIndex].title)
            }
            Button {
                implicitWidth: 60; implicitHeight: 18
                label: "Delete"
                controlEnabled: root.hasSel && root.canDelete && root.count > 1
                onClicked: deleteConfirm.openFor(root.selIndex)
            }
            Item { Layout.fillWidth: true }
            Button {
                implicitWidth: 118; implicitHeight: 18
                label: "New/Copy Custom"
                onClicked: customPopup.openFresh()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 220
            color: "transparent"
            border.width: 1
            border.color: theme.border
            clip: true

            ListView {
                id: listView
                anchors.fill: parent
                anchors.margins: 2
                model: root.rows
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    width: listView.width
                    height: 18
                    color: index === root.selIndex ? theme.active
                         : rowMa.containsMouse ? theme.hover : "transparent"

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        label: modelData.display || modelData.title || ""
                        size: 14
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.selIndex = index
                        onDoubleClicked: {
                            root.selIndex = index
                            var res = luaEngine.invoke("pob_loadoutsSelect", [modelData.fullName])
                            if (res && !res.ok) {
                                root._showError(res.error)
                                return
                            }
                            root.refresh()
                            root.loadoutsChanged()
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            Button {
                implicitWidth: 44; implicitHeight: 20
                label: "Up"
                controlEnabled: root.hasSel && root.selIndex > 0
                tooltipText: "Move the selected loadout up"
                onClicked: root._move(-1)
            }
            Button {
                implicitWidth: 50; implicitHeight: 20
                label: "Down"
                controlEnabled: root.hasSel && root.selIndex < root.count - 1
                tooltipText: "Move the selected loadout down"
                onClicked: root._move(1)
            }
            Button {
                implicitWidth: 90; implicitHeight: 20
                label: "Done"
                onClicked: root.accept()
            }
        }
    }

    TextInputPopup {
        id: namePopup
        parent: root.parent
        prompt: "^7Enter name for this loadout:"
        confirmLabel: "Save"
        confirmEnabled: text.match(/\S/) !== null && !root._isDuplicateName(text)
        onAccepted: root._nameAccepted(text)
    }

    ConfirmPopup {
        id: deleteConfirm
        parent: root.parent
        title: "Delete Loadout"
        confirmLabel: "Delete"
        property int targetIndex: -1

        function openFor(i) {
            targetIndex = i
            message = "Are you sure you want to delete '" + root.rows[i].title + "'?"
            open()
        }

        onAccepted: {
            if (targetIndex < 0 || targetIndex >= root.count) return
            var res = luaEngine.invoke("pob_loadoutsDelete", [targetIndex + 1])
            if (res && !res.ok) {
                root._showError(res.error)
                return
            }
            root.selIndex = -1
            root.refresh()
            root.loadoutsChanged()
        }
    }

    PopupBase {
        id: customPopup
        parent: root.parent
        title: "New/Copy Custom Loadout"
        padding: 14

        readonly property bool canCreate:
            customNameEdit.text.match(/\S/) !== null && !root._isDuplicateName(customNameEdit.text)

        Keys.onReturnPressed: if (canCreate) accept()
        Keys.onEnterPressed: if (canCreate) accept()

        function openFresh() {
            treeDrop.currentIndex = 0
            skillDrop.currentIndex = 0
            itemDrop.currentIndex = 0
            configDrop.currentIndex = 0
            customNameEdit.text = ""
            open()
        }

        onAccepted: {
            if (!canCreate) return
            var tItem = root._trees[treeDrop.currentIndex]
            var sItem = root._skills[skillDrop.currentIndex]
            var iItem = root._items[itemDrop.currentIndex]
            var cItem = root._configs[configDrop.currentIndex]
            var res = luaEngine.invoke("pob_loadoutsCustom", [
                tItem ? tItem.id : -1,
                iItem ? iItem.id : -1,
                sItem ? sItem.id : -1,
                cItem ? cItem.id : -1,
                customNameEdit.text
            ])
            if (res && !res.ok) {
                root._showError(res.error)
                return
            }
            root.refresh()
            root.loadoutsChanged()
        }

        GridLayout {
            columns: 2
            columnSpacing: 8
            rowSpacing: 6
            implicitWidth: 320

            Label { label: "^7Loadout Name:"; size: 14 }
            EditControl {
                id: customNameEdit
                Layout.fillWidth: true
                placeholder: "Loadout name"
            }

            Label { label: "^7Tree:"; size: 14 }
            DropDownControl {
                id: treeDrop
                Layout.fillWidth: true
                model: root._trees
                labelFor: function (x) { return x ? x.label : "" }
            }

            Label { label: "^7Skill Set:"; size: 14 }
            DropDownControl {
                id: skillDrop
                Layout.fillWidth: true
                model: root._skills
                labelFor: function (x) { return x ? x.label : "" }
            }

            Label { label: "^7Item Set:"; size: 14 }
            DropDownControl {
                id: itemDrop
                Layout.fillWidth: true
                model: root._items
                labelFor: function (x) { return x ? x.label : "" }
            }

            Label { label: "^7Config Set:"; size: 14 }
            DropDownControl {
                id: configDrop
                Layout.fillWidth: true
                model: root._configs
                labelFor: function (x) { return x ? x.label : "" }
            }

            RowLayout {
                Layout.columnSpan: 2
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                spacing: 10

                Button {
                    implicitWidth: 80; implicitHeight: 24
                    label: "Create"
                    controlEnabled: customPopup.canCreate
                    onClicked: if (customPopup.canCreate) customPopup.accept()
                }
                PopupButton {
                    label: "Cancel"
                    onClicked: customPopup.reject()
                }
            }
        }
    }

    MessagePopup {
        id: errorPopup
        parent: root.parent
        title: " Loadout Error "
    }
}
