import QtQuick
import QtQuick.Layouts

// MessagePopup — canned dialog, ports legacy main:OpenMessagePopup. One OK
// button; ENTER (PopupBase) or clicking OK both close it. Width mirrors
// legacy's `max(DrawStringWidth(msg)+30, 190)` via TextMetrics (which
// already returns the max line width across a multi-line string).
PopupBase {
    id: root

    property string message: ""

    padding: 16

    ColumnLayout {
        width: Math.max(160, textMetrics.width(theme.fontSize, "VAR", root.message))
        spacing: 4

        Repeater {
            model: root.message.split("\n")
            delegate: ColorText {
                sourceText: modelData
                defaultColor: theme.text
                font.pixelSize: theme.fontSize
            }
        }
        Item { Layout.preferredHeight: 8 } // spacer before the button row

        PopupButton {
            label: "Ok"
            Layout.alignment: Qt.AlignHCenter
            onClicked: root.accept()
        }
    }
}
