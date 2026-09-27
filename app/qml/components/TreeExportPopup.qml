import QtQuick
import QtQuick.Layouts

// TreeExportPopup — Phase 4 Part 4.2, ports TreeTab:OpenExportPopup
// (TreeTab.lua:839-866): the active spec's link (spec:EncodeURL against the
// version's pathofexile.com URL), Copy and Done. "Shrink with PoEURL" is a
// network call and waits for Phase 10.
PopupBase {
    id: root

    property string link: ""

    title: "Export Tree"
    padding: 16

    function openFresh() {
        var r = luaEngine.invoke("pob_exportTree", [])
        link = (r && r.link) ? r.link : ""
        open()
        linkInput.forceActiveFocus()
        linkInput.selectAll()
    }

    ColumnLayout {
        width: 350
        spacing: 8

        ColorText {
            Layout.alignment: Qt.AlignHCenter
            sourceText: "Passive tree link:"
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
                readOnly: true
                clip: true
                text: root.link
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            Button {
                implicitWidth: 80; implicitHeight: 20
                label: "Copy"
                controlEnabled: root.link.length > 0
                onClicked: luaEngine.copyText(root.link)
            }
            Button {
                implicitWidth: 80; implicitHeight: 20
                label: "Done"
                onClicked: root.accept()
            }
        }
    }
}
