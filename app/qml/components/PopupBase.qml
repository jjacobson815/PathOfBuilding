import QtQuick
import QtQuick.Controls

// PopupBase — Tier 0 generic modal dialog shell, ported from legacy
// PopupDialog.lua + the popup-opening half of Modules/Main.lua (OpenPopup/
// ClosePopup/OpenMessagePopup/OpenConfirmPopup/OpenNewFolderPopup, ~108 call
// sites across the legacy codebase). Built on QtQuick.Controls' `Dialog`
// rather than hand-rolled dim/centering/stacking — Dialog already gives a
// modal dim overlay, centering, a popup **stack** (multiple simultaneously-
// open Dialogs z-order correctly via the implicit window Overlay), and
// accept()/reject() (the enter/escape-control wiring legacy did by hand).
// This is the "generic openPopup(controls, enter, escape)" the spec asks
// for: every canned dialog (MessagePopup/ConfirmPopup/TextInputPopup/
// NewFolderPopup) and every future bespoke popup composes THIS rather than
// re-implementing dim+center+title-plate+Escape/Enter each time.
//
// Content: put arbitrary QML as children (Dialog's default property is
// `contentData`) — PopupBase only owns the chrome (background/title plate/
// dim/keys), not the content layout.
//
// Deviation from legacy (documented, not a bug): legacy's `popups` stack
// draws ONLY the topmost popup (covered ones are entirely un-drawn); here,
// stacked Dialogs are still individually visible underneath the topmost
// one's dim overlay (each dims again on top) rather than being hidden
// outright. Functionally equivalent (only the topmost is interactive) but
// not pixel-identical when 2+ popups are open at once — acceptable since
// that's a rare, brief state (e.g. a Confirm opened from within Options).
Dialog {
    id: root

    modal: true
    focus: true
    anchors.centerIn: parent
    closePolicy: Popup.CloseOnEscape

    background: Rectangle {
        color: theme.background
        border.width: 2
        border.color: theme.borderStrong
        radius: theme.radiusCard
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.5)
    }

    // Title plate: a small pill centered above the dialog's top edge,
    // mirroring PopupDialog:Draw's title box (drawn at y-10, outside the
    // main dialog body).
    header: Item {
        implicitHeight: 26
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: titleLabel.implicitWidth + 16
            height: 22
            radius: theme.radiusControl
            color: theme.titleBar
            border.width: 1
            border.color: theme.borderStrong
            Text {
                id: titleLabel
                anchors.centerIn: parent
                text: root.title
                color: theme.text
                font.bold: true
                font.pixelSize: theme.fontSize
            }
        }
    }

    // RETURN/ENTER -> accept() (the legacy `enterControl` click); ESCAPE is
    // already handled by closePolicy above (-> reject(), Dialog default).
    Keys.onReturnPressed: root.accept()
    Keys.onEnterPressed: root.accept()
}
