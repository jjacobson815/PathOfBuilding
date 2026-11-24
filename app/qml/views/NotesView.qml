import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import "../components" as Widgets

// NOTES view — Phase 9, ports src/Classes/NotesTab.lua over the live notesTab
// (bridge: app/lua/pob_notes_party.lua).
//
// Legacy layout:
//   - 3-line instruction header (Label single-line split)
//   - 4x3 grid of color-code insert buttons (100x18, 120px X step, 18px Y step)
//   - "Show Color Codes" / "Hide Color Codes" toggle button on the right
//   - Full-tab 16pt multiline editor (Ctrl+Z/Y undo/redo, Ctrl +/-/0 & Ctrl+Wheel zoom)
//   - Rendered ColorText preview pane so color codes display visually alongside editing.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property var st: ({})
    property var colorButtons: st && st.colors && st.colors.length !== undefined ? st.colors : []
    property bool showColorCodes: !!(st && st.showColorCodes)
    property int editorFontSize: 16
    property bool showPreview: true
    property bool _syncing: false
    property bool _pending: false

    readonly property var _descLines: [
        "^7You can use Ctrl +/- (or Ctrl+Scroll) to zoom in and out and Ctrl+0 to reset.",
        "^7This field also supports different colors.  Using the caret symbol (^) followed by a Hex code or a number (0-9) will set the color.",
        "^7Below are some common color codes PoB uses:"
    ]

    function refresh() {
        if (_pending) return
        _pending = true
        Qt.callLater(_doRefresh)
    }

    function _doRefresh() {
        _pending = false
        if (luaEngine.currentMode !== "BUILD") return
        const s = luaEngine.invoke("pob_notesGetState", [])
        if (!s || !s.ok) return
        st = s
        _syncing = true
        if (notesEdit.text !== (s.text || "")) {
            const cur = notesEdit.cursorPosition
            notesEdit.text = s.text || ""
            notesEdit.cursorPosition = Math.min(cur, notesEdit.text.length)
        }
        _syncing = false
    }

    function _zoom(delta) {
        editorFontSize = Math.max(8, Math.min(48, editorFontSize + delta))
    }

    function _insertColor(btn) {
        const start = notesEdit.selectionStart
        const end = notesEdit.selectionEnd
        const sel = (start !== end) ? notesEdit.text.substring(start, end) : ""
        const replacement = luaEngine.invoke("pob_notesWrapSelection", [sel, btn.code])
        if (typeof replacement !== "string") return

        const before = notesEdit.text.substring(0, start)
        const after = notesEdit.text.substring(end)
        const nextText = before + replacement + after
        _syncing = true
        notesEdit.text = nextText
        notesEdit.cursorPosition = before.length + replacement.length
        _syncing = false
        notesEdit.forceActiveFocus()
        luaEngine.invoke("pob_notesSetText", [nextText])
    }

    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: if (visible) refresh()

    Connections {
        target: luaEngine
        function onModeChanged() { if (root.visible) root.refresh() }
        function onNotesChanged() { if (root.visible && !notesEdit.activeFocus) root.refresh() }
    }

    Timer {
        id: syncTimer
        interval: 120
        onTriggered: {
            if (!root._syncing) {
                luaEngine.invoke("pob_notesSetText", [notesEdit.text])
            }
        }
    }

    Shortcut {
        sequences: ["Ctrl+=", "Ctrl++"]
        enabled: root.visible
        onActivated: root._zoom(2)
    }
    Shortcut {
        sequence: "Ctrl+-"
        enabled: root.visible
        onActivated: root._zoom(-2)
    }
    Shortcut {
        sequence: "Ctrl+0"
        enabled: root.visible
        onActivated: root.editorFontSize = 16
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        // Instruction lines (single-line Label splitting)
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

        // 4x3 color buttons + right-aligned toggles
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            GridLayout {
                columns: 4
                columnSpacing: 16
                rowSpacing: 4

                Repeater {
                    model: root.colorButtons.length
                    delegate: Widgets.Button {
                        required property int index
                        readonly property var btn: root.colorButtons[index]
                        implicitWidth: 108
                        implicitHeight: 20
                        label: (btn.code || "^7") + (btn.label || "")
                        onClicked: root._insertColor(btn)
                    }
                }
            }

            Item { Layout.fillWidth: true }

            ColumnLayout {
                spacing: 4
                Layout.alignment: Qt.AlignBottom
                Widgets.Button {
                    implicitWidth: 160
                    implicitHeight: 20
                    label: root.showColorCodes ? "Hide Color Codes" : "Show Color Codes"
                    onClicked: {
                        const s = luaEngine.invoke("pob_notesToggleColorCodes", [])
                        if (s && s.ok) {
                            root.st = s
                            root._syncing = true
                            notesEdit.text = s.text || ""
                            root._syncing = false
                        }
                    }
                }
                Widgets.Button {
                    implicitWidth: 160
                    implicitHeight: 20
                    label: root.showPreview ? "Hide Color Preview" : "Show Color Preview"
                    onClicked: root.showPreview = !root.showPreview
                }
            }
        }

        // Main editor + optional live ColorText preview split
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: theme.background
                border.width: 1
                border.color: notesEdit.activeFocus ? theme.text : theme.border

                QC.ScrollView {
                    anchors.fill: parent
                    anchors.margins: 4

                    QC.TextArea {
                        id: notesEdit
                        color: theme.text
                        font.family: theme.fontVar
                        font.pixelSize: root.editorFontSize
                        wrapMode: TextEdit.Wrap
                        tabStopDistance: 32
                        selectByMouse: true
                        background: null

                        onTextChanged: {
                            if (!root._syncing) {
                                syncTimer.restart()
                            }
                        }

                        Keys.onPressed: function(event) {
                            if ((event.modifiers & Qt.ControlModifier)) {
                                if (event.key === Qt.Key_Z) {
                                    undo()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Y) {
                                    redo()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
                                    root._zoom(2)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Minus) {
                                    root._zoom(-2)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_0) {
                                    root.editorFontSize = 16
                                    event.accepted = true
                                }
                            }
                        }
                    }
                }

                WheelHandler {
                    acceptedModifiers: Qt.ControlModifier
                    onWheel: function(event) {
                        root._zoom(event.angleDelta.y > 0 ? 2 : -2)
                    }
                }
            }

            Rectangle {
                visible: root.showPreview
                Layout.preferredWidth: Math.max(260, parent.width * 0.38)
                Layout.fillHeight: true
                color: theme.background
                border.width: 1
                border.color: theme.border

                QC.ScrollView {
                    anchors.fill: parent
                    anchors.margins: 6

                    Widgets.ColorText {
                        width: parent.width - 12
                        sourceText: notesEdit.text
                        font.pixelSize: root.editorFontSize
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
