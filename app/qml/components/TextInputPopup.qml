import QtQuick
import QtQuick.Layouts

// TextInputPopup — canned dialog: a prompt label + single-line text field +
// Create/Cancel buttons. Uses a plain QML TextInput (the real EditControl
// port with filter/limit/clipboard/undo is Tier 3, not built yet) inside a
// Chrome frame so it's at least visually consistent. Caller reads the
// entered value from `text` in `onAccepted` (Enter or clicking the confirm
// button); `confirmEnabled` mirrors legacy's create-button-disabled-until-
// non-blank pattern (e.g. NewFolderPopup's `buf:match("%S")` check).
PopupBase {
    id: root

    property string prompt: ""
    property alias text: input.text
    property string confirmLabel: "Ok"
    // Non-blank by default; NewFolderPopup overrides this binding to also
    // reject illegal filename characters.
    property bool confirmEnabled: text.match(/\S/) !== null

    padding: 16

    // Override PopupBase's unconditional Keys.onReturnPressed: Enter
    // shouldn't accept while the field is blank, mirroring legacy's
    // disabled Create button (NewFolderPopup's `buf:match("%S")` check).
    Keys.onReturnPressed: if (confirmEnabled) root.accept()
    Keys.onEnterPressed: if (confirmEnabled) root.accept()

    ColumnLayout {
        width: 280
        spacing: 8

        ColorText {
            sourceText: root.prompt
            defaultColor: theme.text
            font.pixelSize: theme.fontSize
        }

        Chrome {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            controlEnabled: true

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                verticalAlignment: TextInput.AlignVCenter
                color: theme.text
                font.pixelSize: theme.fontSize
                selectByMouse: true
                focus: true
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            PopupButton {
                label: root.confirmLabel
                onClicked: if (root.confirmEnabled) root.accept()
            }
            PopupButton {
                label: "Cancel"
                onClicked: root.reject()
            }
        }
    }
}
