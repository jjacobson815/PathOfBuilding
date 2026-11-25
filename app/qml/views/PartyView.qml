import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import "../components" as Widgets
import "../components/QmlBridge.js" as QmlBridge

// PARTY view — Phase 9, ports src/Classes/PartyTab.lua over the live partyTab
// (bridge: app/lua/pob_notes_party.lua).
Item {
    id: root
    anchors.fill: parent
    clip: true

    property var st: ({})
    property bool _pending: false
    property bool _syncing: false

    readonly property var _descLines: [
        "^7To import a build it must be exported with \"Export support\" enabled in the import/export tab",
        "^7Auras with the highest effect will take priority, your curses will take priority over a support's",
        "^7All of these effects can be found in the Calcs tab"
    ]

    function refresh() {
        if (_pending) return
        _pending = true
        Qt.callLater(_doRefresh)
    }

    function _doRefresh() {
        _pending = false
        if (luaEngine.currentMode !== "BUILD") return
        const s = luaEngine.invoke("pob_partyGetState", [])
        if (!s || !s.ok) return
        _applyState(s)
    }

    function _applyState(s) {
        if (!s || !s.ok) return
        _syncing = true
        st = s
        if (!importCodeIn.editing) {
            importCodeIn.text = s.importCode || ""
        }
        const dests = QmlBridge.toArray(s.destinations)
        destSelect.model = dests
        destSelect.currentIndex = (s.destinationIndex || 1) - 1
        appendCheck.state = !!s.append
        advCheck.state = !!s.showAdvanced

        const b = s.buffers || {}
        aurasBox.setBufferText(b.auras || "")
        warcriesBox.setBufferText(b.warcries || "")
        linksBox.setBufferText(b.links || "")
        partyStatsBox.setBufferText(b.partyStats || "")
        enemyCondBox.setBufferText(b.enemyCond || "")
        enemyModsBox.setBufferText(b.enemyMods || "")
        cursesBox.setBufferText(b.curses || "")
        _syncing = false
    }

    function _invoke(fn, args) {
        const s = luaEngine.invoke(fn, args || [])
        if (s && s.ok) _applyState(s)
        return s
    }

    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: if (visible) refresh()

    Connections {
        target: luaEngine
        function onModeChanged() { if (root.visible) root.refresh() }
        function onPartyChanged() { if (root.visible) root.refresh() }
    }

    readonly property bool _adv: !!(st && st.showAdvanced)
    readonly property var _bufs: (st && st.buffers) ? st.buffers : ({})
    readonly property int _leftExpandedH: Math.max(120, root.height - 460)
    readonly property int _rightExpandedH: Math.max(120, root.height - 440)

    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 12

        // Left column: instructions, import controls, Auras, Warcries, Links
        QC.ScrollView {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: Math.max(300, parent.width - 8)
                spacing: 6

                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: root._descLines
                        delegate: Widgets.Label {
                            required property string modelData
                            label: modelData
                            size: 14
                        }
                    }
                }

                Widgets.Label {
                    label: "^7Enter a build code/URL below:"
                    size: 16
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Widgets.EditControl {
                        id: importCodeIn
                        objectName: "pob.party.input_import_code"
                        Layout.preferredWidth: 328
                        Layout.preferredHeight: 20
                        size: 14
                        onEdited: function(t) {
                            if (!root._syncing) {
                                root._invoke("pob_partySetImportCode", [t])
                            }
                        }
                        onCommitted: function(t) {
                            if (!root._syncing) {
                                const s = root._invoke("pob_partySetImportCode", [t])
                                if (s && s.importValid && !s.importIsUrl) {
                                    root._invoke("pob_partyImport", [])
                                }
                            }
                        }
                    }

                    Widgets.Label {
                        objectName: "pob.party.label_import_detail"
                        visible: label.length > 0
                        label: (root.st && root.st.importDetail) ? root.st.importDetail : ""
                        size: 16
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    Widgets.DropDownControl {
                        id: destSelect
                        objectName: "pob.party.drop_destination"
                        width: 160
                        height: 20
                        tooltipText: "Destination for Import/clear\nCurrently Links Skills do not export"
                        onSelected: function(i) {
                            root._invoke("pob_partySetDestination", [i + 1])
                        }
                    }

                    Widgets.Button {
                        objectName: "pob.party.btn_import"
                        implicitWidth: 120
                        implicitHeight: 20
                        label: "Import"
                        controlEnabled: !!(root.st && root.st.importValid && !root.st.importIsUrl)
                        tooltipText: (root.st && root.st.importIsUrl)
                            ? "^1URL fetch requires Phase 10 network; paste a build code instead"
                            : ""
                        onClicked: root._invoke("pob_partyImport", [])
                    }

                    Item {
                        width: appendCheck.labelWidth + 24
                        height: 20
                        Widgets.CheckBox {
                            id: appendCheck
                            objectName: "pob.party.check_append"
                            anchors.right: parent.right
                            height: 20
                            label: "Append"
                            tooltipText: "This sets the import button to append to the current party lists instead of replacing them (curses will still replace)"
                            onToggled: function(ns) { root._invoke("pob_partySetAppend", [ns]) }
                        }
                    }

                    Widgets.Button {
                        objectName: "pob.party.btn_clear"
                        implicitWidth: 120
                        implicitHeight: 20
                        label: "Clear"
                        tooltipText: "^7Clears all the party tab imported data"
                        onClicked: root._invoke("pob_partyClear", [])
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    Item {
                        width: advCheck.labelWidth + 24
                        height: 20
                        Widgets.CheckBox {
                            id: advCheck
                            objectName: "pob.party.check_advanced"
                            anchors.right: parent.right
                            height: 20
                            label: "^7Show Advanced Info"
                            tooltipText: "This shows the advanced info like what stats each aura/curse etc are adding, as well as enables the ability to edit them without a re-export\nDo not edit any boxes unless you know what you are doing, use copy/paste or import instead"
                            onToggled: function(ns) { root._invoke("pob_partySetShowAdvanced", [ns]) }
                        }
                    }

                    Widgets.Button {
                        objectName: "pob.party.btn_disable_effects"
                        implicitWidth: 150
                        implicitHeight: 20
                        label: "Disable Party Effects"
                        tooltipText: "^7Removes the effects of the supports, without removing the data\nUse \"Rebuild All\" to apply the effects again"
                        onClicked: root._invoke("pob_partyDisableEffects", [])
                    }

                    Widgets.Button {
                        objectName: "pob.party.btn_rebuild"
                        implicitWidth: 120
                        implicitHeight: 20
                        label: "^7Rebuild All"
                        tooltipText: "^7Reparse all the inputs in case they have been disabled or they have changed since loading the build or importing"
                        onClicked: root._invoke("pob_partyRebuildAll", [])
                    }
                }

                Widgets.PartyBufferBox {
                    id: aurasBox
                    objectName: "pob.party.box_auras"
                    Layout.fillWidth: true
                    title: "^7Auras"
                    bufferKey: "auras"
                    showAdvanced: root._adv
                    summaryText: root._bufs.simpleAuras || ""
                    editorHeight: (warcriesBox.focused || linksBox.focused) ? 106 : root._leftExpandedH
                    onBufferEdited: function(k, t) { root._invoke("pob_partySetBuffer", [k, t]) }
                }

                Widgets.PartyBufferBox {
                    id: warcriesBox
                    objectName: "pob.party.box_warcries"
                    Layout.fillWidth: true
                    title: "^7Warcry Skills"
                    bufferKey: "warcries"
                    showAdvanced: root._adv
                    summaryText: root._bufs.simpleWarcries || ""
                    editorHeight: warcriesBox.focused ? root._leftExpandedH : 106
                    onBufferEdited: function(k, t) { root._invoke("pob_partySetBuffer", [k, t]) }
                }

                Widgets.PartyBufferBox {
                    id: linksBox
                    objectName: "pob.party.box_links"
                    Layout.fillWidth: true
                    title: "^7Link Skills"
                    bufferKey: "links"
                    showAdvanced: root._adv
                    summaryText: root._bufs.simpleLinks || ""
                    editorHeight: linksBox.focused ? root._leftExpandedH : 106
                    onBufferEdited: function(k, t) { root._invoke("pob_partySetBuffer", [k, t]) }
                }
            }
        }

        // Right column: Party Member Stats, Enemy Conditions, Enemy Modifiers, Curses
        QC.ScrollView {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: Math.max(300, parent.width - 8)
                spacing: 6

                Widgets.PartyBufferBox {
                    id: partyStatsBox
                    objectName: "pob.party.box_party_stats"
                    Layout.fillWidth: true
                    title: "^7Party Member Stats"
                    bufferKey: "partyStats"
                    showAdvanced: root._adv
                    hasSummary: false
                    editorHeight: partyStatsBox.focused ? root._rightExpandedH : 106
                    onBufferEdited: function(k, t) { root._invoke("pob_partySetBuffer", [k, t]) }
                }

                Widgets.PartyBufferBox {
                    id: enemyCondBox
                    objectName: "pob.party.box_enemy_cond"
                    Layout.fillWidth: true
                    title: "^7Enemy Conditions"
                    bufferKey: "enemyCond"
                    showAdvanced: root._adv
                    summaryText: root._bufs.simpleEnemyCond || "^7---------------------------\n"
                    editorHeight: enemyCondBox.focused ? root._rightExpandedH : 106
                    onBufferEdited: function(k, t) { root._invoke("pob_partySetBuffer", [k, t]) }
                }

                Widgets.PartyBufferBox {
                    id: enemyModsBox
                    objectName: "pob.party.box_enemy_mods"
                    Layout.fillWidth: true
                    title: "^7Enemy Modifiers"
                    bufferKey: "enemyMods"
                    showAdvanced: root._adv
                    summaryText: root._bufs.simpleEnemyMods || "\n"
                    editorHeight: enemyModsBox.focused ? root._rightExpandedH : 106
                    onBufferEdited: function(k, t) { root._invoke("pob_partySetBuffer", [k, t]) }
                }

                Widgets.PartyBufferBox {
                    id: cursesBox
                    objectName: "pob.party.box_curses"
                    Layout.fillWidth: true
                    title: "^7Curses"
                    bufferKey: "curses"
                    showAdvanced: root._adv
                    summaryText: root._bufs.simpleCurses || ""
                    editorHeight: (partyStatsBox.focused || enemyCondBox.focused || enemyModsBox.focused) ? 106 : root._rightExpandedH
                    onBufferEdited: function(k, t) { root._invoke("pob_partySetBuffer", [k, t]) }
                }
            }
        }
    }
}
