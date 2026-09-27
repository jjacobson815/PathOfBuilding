import QtQuick
import QtQuick.Layouts

// TreeImportPopup — Phase 4 Part 4.2, ports TreeTab:OpenImportPopup
// (TreeTab.lua:709-837): name + link fields, an error line, Import/Cancel.
// Import is enabled only while both fields hold a non-space character, and
// editing either clears the message (legacy's EditControl changeFuncs).
// All link parsing lives in the bridge (pob_importTree); a failed import keeps
// the popup open with the engine's message, a successful one closes it and
// raises `imported(index)`.
PopupBase {
    id: root

    signal imported(int index)

    property string msg: ""
    readonly property bool canImport: nameInput.text.match(/\S/) !== null
                                      && linkInput.text.match(/\S/) !== null

    title: "Import Tree"
    padding: 16

    function openFresh() {
        nameInput.text = ""
        linkInput.text = ""
        msg = ""
        open()
        nameInput.forceActiveFocus()
    }

    function doImport() {
        if (!canImport) return
        var r = luaEngine.invoke("pob_importTree", [nameInput.text, linkInput.text])
        if (r && r.ok) {
            close()
            imported(r.index)
        } else {
            msg = (r && r.msg) ? r.msg : "^1Import failed"
        }
    }

    Keys.onReturnPressed: doImport()
    Keys.onEnterPressed: doImport()

    ColumnLayout {
        width: 540
        spacing: 8

        GridLayout {
            columns: 2
            columnSpacing: 8
            rowSpacing: 6
            Layout.fillWidth: true

            ColorText {
                sourceText: "Enter name for this passive tree:"
                font.pixelSize: theme.fontSize
            }
            Chrome {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                controlEnabled: true
                TextInput {
                    id: nameInput
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    verticalAlignment: TextInput.AlignVCenter
                    color: theme.text
                    font.pixelSize: theme.fontSize
                    selectByMouse: true
                    clip: true
                    KeyNavigation.tab: linkInput
                    onTextChanged: root.msg = ""
                }
            }

            ColorText {
                sourceText: "Enter passive tree link:"
                font.pixelSize: theme.fontSize
            }
            Chrome {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                controlEnabled: true
                TextInput {
                    id: linkInput
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    verticalAlignment: TextInput.AlignVCenter
                    color: theme.text
                    font.pixelSize: theme.fontSize
                    selectByMouse: true
                    clip: true
                    KeyNavigation.tab: nameInput
                    onTextChanged: root.msg = ""
                }
            }
        }

        ColorText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: 540
            sourceText: root.msg
            font.pixelSize: theme.fontSize
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            Button {
                implicitWidth: 80; implicitHeight: 20
                label: "Import"
                controlEnabled: root.canImport
                onClicked: root.doImport()
            }
            Button {
                implicitWidth: 80; implicitHeight: 20
                label: "Cancel"
                onClicked: root.reject()
            }
        }
    }
}
