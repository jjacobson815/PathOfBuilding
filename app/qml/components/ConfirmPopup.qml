import QtQuick
import QtQuick.Layouts

// ConfirmPopup — canned dialog, ports legacy main:OpenConfirmPopup. Two-
// button (Confirm/Cancel) by default; set `extraLabel` for the legacy
// three-button layout (Confirm/Extra/Cancel, e.g. "Continue" / "Connect
// Path" / "Cancel"). Caller wires the standard Dialog signals:
//   onAccepted: <the confirm action>   (fires on Confirm click OR Enter)
//   onExtraClicked: <the extra action> (fires on the optional 3rd button)
// Cancel/Escape both just close (Dialog.rejected) with no callback, matching
// legacy's Cancel button (`function() end`).
PopupBase {
    id: root

    property string message: ""
    property string confirmLabel: "Confirm"
    property string extraLabel: ""   // non-empty => 3-button layout

    signal extraClicked()

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
        Item { Layout.preferredHeight: 8 }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            PopupButton {
                label: root.confirmLabel
                onClicked: root.accept()
            }
            PopupButton {
                label: root.extraLabel
                visible: root.extraLabel !== ""
                onClicked: root.extraClicked()
            }
            PopupButton {
                label: "Cancel"
                onClicked: root.reject()
            }
        }
    }
}
