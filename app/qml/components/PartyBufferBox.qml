import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import "." as Widgets

// PartyBufferBox — reusable buffer panel for one of PartyTab's 7 data buffers.
// Shows a single-line-split summary when showAdvanced is false, or a focus-sized
// multiline editor when showAdvanced is true.
ColumnLayout {
    id: root

    property string title: ""
    property string bufferKey: ""
    property bool showAdvanced: false
    property bool hasSummary: true
    property string summaryText: ""
    property int editorHeight: 106
    readonly property bool focused: area.activeFocus
    property bool _syncing: false

    signal bufferEdited(string key, string text)

    function setBufferText(t) {
        if (area.activeFocus) return
        const next = t || ""
        if (area.text === next) return
        _syncing = true
        area.text = next
        _syncing = false
    }

    visible: root.showAdvanced || root.hasSummary
    spacing: 2

    Widgets.Label {
        objectName: "pob.partyBuffer.title"
        label: root.title
        size: 16
    }

    Timer {
        id: editTimer
        interval: 200
        onTriggered: {
            if (!root._syncing) {
                root.bufferEdited(root.bufferKey, area.text)
            }
        }
    }

    Rectangle {
        visible: root.showAdvanced
        Layout.fillWidth: true
        Layout.preferredHeight: root.editorHeight
        color: theme.background
        border.width: 1
        border.color: area.activeFocus ? theme.accent : theme.border

        QC.ScrollView {
            anchors.fill: parent
            anchors.margins: 2

            QC.TextArea {
                id: area
                objectName: "pob.partyBuffer.editor"
                color: theme.text
                font.family: theme.fontFixed
                font.pixelSize: 14
                wrapMode: TextEdit.NoWrap
                tabStopDistance: 28
                selectByMouse: true
                background: null

                onTextChanged: {
                    if (!root._syncing) {
                        editTimer.restart()
                    }
                }
                onActiveFocusChanged: {
                    if (!activeFocus && editTimer.running) {
                        editTimer.stop()
                        if (!root._syncing) {
                            root.bufferEdited(root.bufferKey, area.text)
                        }
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
                        }
                    }
                }
            }
        }
    }

    Column {
        objectName: "pob.partyBuffer.summary"
        visible: !root.showAdvanced && root.hasSummary
        Layout.fillWidth: true
        spacing: 1

        Repeater {
            model: root.summaryText.trim().length > 0 ? root.summaryText.split("\n") : []
            delegate: Widgets.ColorText {
                required property string modelData
                width: parent.width
                wrapMode: Text.WordWrap
                sourceText: modelData
                defaultColor: theme.text
                font.pixelSize: 14
            }
        }
    }
}
