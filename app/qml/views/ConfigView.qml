import QtQuick
import QtQuick.Controls as QC
import "../components" as Widgets
import "../components/QmlBridge.js" as QmlBridge

// CONFIG view — Phase 7, ports src/Classes/ConfigTab.lua over the live
// build.configTab via app/lua/pob_config.lua.
//
// Features:
//   - Config sets: dropdown (enabled when > 1 set) + "Manage..." popup
//     reusing components/SetManagePopup.qml.
//   - Search box (Ctrl+F, Lua-pattern-tolerant) + "Show All Configurations"
//     toggle button.
//   - Multi-column collapsible Section flow populated from ConfigOptions via
//     components/ConfigOptionRow.qml (check/count/countAllowZero/integer/
//     float/list/text, placeholders, dynamic tooltips, red invalid non-default
//     labels + colored borders).
//   - Custom Modifiers section (add/remove/edit/enable custom modifier groups).
//   - Ctrl+Z / Ctrl+Y undo/redo on the active config set.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property var st: ({})
    property string searchQuery: ""
    property bool _pending: false

    readonly property var sets: QmlBridge.toArray(st ? st.sets : null)
    readonly property var sections: QmlBridge.toArray(st ? st.sections : null)
    readonly property var customMods: QmlBridge.toArray(st ? st.customMods : null)
    readonly property bool toggleConfigs: !!(st && st.toggleConfigs)

    // Compute number of 360px columns that fit in the viewport (legacy: (w - 10) / 370).
    readonly property int colCount: Math.max(1, Math.min(3, Math.floor((flick.width - 10) / 370)))

    // Bucket sections into columns [0..colCount-1] respecting legacy `sec.col`.
    readonly property var columns: {
        var cols = []
        for (var c = 0; c < colCount; c++) cols.push([])
        var list = sections
        var n = (list && list.length !== undefined) ? list.length : 0
        for (var i = 0; i < n; i++) {
            var sec = list[i]
            var desired = (sec && sec.col !== undefined) ? Number(sec.col) : 1
            var targetCol = Math.max(0, Math.min(colCount - 1, desired - 1))
            cols[targetCol].push(sec)
        }
        return cols
    }

    function call(name, args) {
        return luaEngine.invoke(name, args || [])
    }

    function refresh() {
        if (_pending) return
        _pending = true
        Qt.callLater(_doRefresh)
    }

    function _doRefresh() {
        _pending = false
        if (luaEngine.currentMode !== "BUILD") return
        var s = luaEngine.invoke("pob_configGetState", [root.searchQuery])
        st = s ? s : ({})
        setSelect.model = sets
        setSelect.currentIndex = (st.activeSetIndex !== undefined ? Number(st.activeSetIndex) : 1) - 1
    }

    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()

    Connections {
        target: luaEngine
        function onConfigChanged() { root.refresh() }
        function onCalcsChanged() { root.refresh() }
        function onTreeChanged() { root.refresh() }
        function onItemsChanged() { root.refresh() }
        function onSkillsChanged() { root.refresh() }
        function onModeChanged() { root.refresh() }
    }

    Timer {
        id: searchDebounce
        interval: 120
        onTriggered: root.refresh()
    }

    Shortcut {
        sequence: "Ctrl+F"
        enabled: root.visible && luaEngine.currentMode === "BUILD"
        onActivated: {
            searchEdit.forceEditFocus()
            searchEdit.selectAll()
        }
    }

    Shortcut {
        sequence: "Ctrl+Z"
        enabled: root.visible && luaEngine.currentMode === "BUILD"
        onActivated: root.call("pob_configUndo")
    }

    Shortcut {
        sequence: "Ctrl+Y"
        enabled: root.visible && luaEngine.currentMode === "BUILD"
        onActivated: root.call("pob_configRedo")
    }

    Rectangle {
        anchors.fill: parent
        color: theme.background
    }

    // Top controls header (Config set row + Search / Show All row)
    Item {
        id: headerBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 60

        // Row 1: Config set dropdown + Manage...
        Widgets.Label {
            id: setLabel
            x: 10
            y: 10
            label: "^7Config set:"
            size: 14
        }

        Widgets.DropDownControl {
            id: setSelect
            objectName: "pob.config.drop_set"
            x: 82
            y: 8
            width: 210
            height: 20
            size: 14
            controlEnabled: root.sets.length > 1
            labelFor: function(item) { return item && item.title ? String(item.title) : "Default" }
            onSelected: function(idx) {
                root.call("pob_configSetActiveSet", [idx + 1])
            }
        }

        Widgets.Button {
            id: manageBtn
            objectName: "pob.config.btn_manage_set"
            x: 296
            y: 8
            width: 90
            height: 20
            label: "Manage..."
            onClicked: setManagePopup.openFresh()
        }

        // Row 2: Search + Show All Configurations toggle
        Widgets.EditControl {
            id: searchEdit
            objectName: "pob.config.input_search"
            x: 10
            y: 34
            width: 360
            height: 20
            placeholder: "Search"
            size: 14
            maxChars: 100
            onEdited: function(txt) {
                root.searchQuery = txt
                searchDebounce.restart()
            }
            onCommitted: function(txt) {
                searchDebounce.stop()
                root.searchQuery = txt
                root.refresh()
            }
            onReverted: {
                searchDebounce.stop()
                root.searchQuery = ""
                root.refresh()
            }
        }

        Widgets.Button {
            id: showAllBtn
            objectName: "pob.config.btn_show_all"
            x: 380
            y: 34
            width: 210
            height: 20
            label: root.toggleConfigs ? "Hide Ineligible Configurations" : "Show All Configurations"
            onClicked: root.call("pob_configSetToggleAll", [!root.toggleConfigs])
        }
    }

    // Multi-column scrollable sections area
    Flickable {
        id: flick
        anchors.top: headerBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: vScroll.left
        anchors.topMargin: 4
        contentWidth: Math.max(width, colRow.implicitWidth + 20)
        contentHeight: Math.max(colRow.implicitHeight + 40, 100)
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        onContentYChanged: if (Math.abs(vScroll.offset - contentY) > 1) vScroll.setOffset(contentY)

        Row {
            id: colRow
            x: 10
            y: 10
            spacing: 10

            Repeater {
                model: root.colCount
                delegate: Column {
                    id: colBox
                    readonly property int colIdx: index
                    readonly property var colSections: (root.columns && root.columns[colIdx] && root.columns[colIdx].length !== undefined)
                        ? root.columns[colIdx] : []
                    width: 360
                    spacing: 18

                    Repeater {
                        model: colBox.colSections.length
                        delegate: Item {
                            id: secWrapper
                            readonly property var sec: colBox.colSections[index]
                            readonly property string secName: sec && sec.name ? String(sec.name) : ""
                            readonly property bool secCollapsed: !!(sec && sec.collapsed)
                            readonly property bool isCustom: !!(sec && sec.isCustomMods)
                            readonly property var secItems: QmlBridge.toArray(sec ? sec.items : null)

                            width: 360
                            height: secCollapsed ? 22 : Math.max(36, secContent.implicitHeight + 22)

                            Widgets.Section {
                                anchors.fill: parent
                                label: secWrapper.secName

                                Column {
                                    id: secContent
                                    visible: !secWrapper.secCollapsed
                                    x: 0
                                    y: 10
                                    width: 352
                                    spacing: 4

                                    // Standard ConfigOptions rows (COUNT model preserves EditControl focus)
                                    Repeater {
                                        model: secWrapper.isCustom ? 0 : secWrapper.secItems.length
                                        delegate: Widgets.ConfigOptionRow {
                                            option: secWrapper.secItems[index]
                                            onValueChanged: function(varName, newValue) {
                                                root.call("pob_configSetOption", [varName, newValue])
                                            }
                                        }
                                    }

                                    // Custom Modifiers blocks
                                    Widgets.Button {
                                        objectName: secWrapper.isCustom ? "pob.config.btn_add_custom_mod" : ""
                                        visible: secWrapper.isCustom
                                        x: 4
                                        width: 120
                                        height: 20
                                        label: "^7Add Mod Group"
                                        onClicked: root.call("pob_configAddCustomMod")
                                    }

                                    Repeater {
                                        model: secWrapper.isCustom ? root.customMods.length : 0
                                        delegate: Column {
                                            id: cmBlock
                                            readonly property int blkIdx: index + 1
                                            readonly property var blk: root.customMods[index]
                                            width: 344
                                            x: 4
                                            spacing: 4

                                            function syncBlock() {
                                                if (!blk) return
                                                if (!cmTitle.editing) cmTitle.text = blk.title !== undefined ? String(blk.title) : "Default"
                                                cmEnable.state = (blk.enabled !== false)
                                                if (!cmArea.activeFocus) cmArea.text = blk.text !== undefined ? String(blk.text) : ""
                                            }
                                            onBlkChanged: syncBlock()
                                            Component.onCompleted: syncBlock()

                                            Row {
                                                spacing: 6
                                                width: parent.width

                                                Widgets.Button {
                                                    objectName: "pob.config.btn_delete_mod_" + cmBlock.blkIdx
                                                    width: 20
                                                    height: 18
                                                    label: "^1X"
                                                    onClicked: root.call("pob_configRemoveCustomMod", [cmBlock.blkIdx])
                                                }

                                                Widgets.EditControl {
                                                    id: cmTitle
                                                    objectName: "pob.config.input_mod_title_" + cmBlock.blkIdx
                                                    width: 294
                                                    height: 18
                                                    size: 14
                                                    onCommitted: function(txt) {
                                                        root.call("pob_configUpdateCustomMod", [cmBlock.blkIdx, txt, null, null])
                                                    }
                                                }

                                                Widgets.CheckBox {
                                                    id: cmEnable
                                                    objectName: "pob.config.check_mod_enable_" + cmBlock.blkIdx
                                                    width: 18
                                                    height: 18
                                                    onToggled: function(newState) {
                                                        root.call("pob_configUpdateCustomMod", [cmBlock.blkIdx, null, newState, null])
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                width: 344
                                                height: 84
                                                color: theme.titleBar
                                                border.width: 1
                                                border.color: cmArea.activeFocus ? theme.borderStrong : theme.border
                                                radius: theme.radiusControl
                                                clip: true

                                                QC.ScrollView {
                                                    anchors.fill: parent
                                                    anchors.margins: 2
                                                    clip: true

                                                    QC.TextArea {
                                                        id: cmArea
                                                        objectName: "pob.config.text_mod_body_" + cmBlock.blkIdx
                                                        color: theme.text
                                                        font.pixelSize: 13
                                                        wrapMode: TextEdit.Wrap
                                                        selectByMouse: true
                                                        background: null
                                                        onActiveFocusChanged: {
                                                            if (!activeFocus && cmBlock.blk && text !== (cmBlock.blk.text || "")) {
                                                                root.call("pob_configUpdateCustomMod", [cmBlock.blkIdx, null, null, text])
                                                            }
                                                        }
                                                        Component.onDestruction: {
                                                            if (cmBlock.blk && text !== (cmBlock.blk.text || "")) {
                                                                root.call("pob_configUpdateCustomMod", [cmBlock.blkIdx, null, null, text])
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Collapse toggle '-' / '+' on top-right section border (ConfigTab.lua:285)
                            Widgets.Button {
                                objectName: "pob.config.sec_collapse_" + secWrapper.secName
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: -7
                                anchors.rightMargin: 6
                                width: 16
                                height: 16
                                label: secWrapper.secCollapsed ? "+" : "-"
                                onClicked: root.call("pob_configToggleSection", [secWrapper.secName])
                            }
                        }
                    }
                }
            }
        }
    }

    Widgets.ScrollBar {
        id: vScroll
        anchors.top: headerBar.bottom
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.topMargin: 4
        width: 18
        dir: "VERTICAL"
        step: 50
        contentDim: flick.contentHeight
        viewDim: flick.height
        onOffsetChanged: if (Math.abs(flick.contentY - offset) > 1) flick.contentY = offset
    }

    // Generic SetManagePopup reused for Config Sets (Part 7.1)
    Widgets.SetManagePopup {
        id: setManagePopup
        title: "Manage Config Sets"
        noun: "config set"
        deleteTitle: "Delete Config Set"
        fn: ({
            list:      "pob_configListSets",
            setActive: "pob_configSetActiveSet",
            create:    "pob_configCreateSet",
            copy:      "pob_configCopySet",
            rename:    "pob_configRenameSet",
            remove:    "pob_configDeleteSet",
            move:      "pob_configMoveSet",
        })
        onListEdited: root.refresh()
    }
}
