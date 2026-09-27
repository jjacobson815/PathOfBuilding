import QtQuick
import QtQuick.Layouts

// Toast — Tier 1.4, a single toast notification card, ported from
// ToastNotification.lua's per-toast render block (Render(), ~line 219-247).
// `message`'s first line is the title (drawn larger, matches legacy's
// DrawString size 20 first line); the rest is the body (size 16). Both run
// through ColorText so ^-codes render. Sizing is auto (ColumnLayout content),
// not the fixed Lua `calculateHeight` formula — no pixel-exact call site to
// match against, and content-driven sizing is strictly more correct for
// wrapped/variable text anyway.
Item {
    id: root

    property string toastId: ""
    property string message: ""
    signal dismissRequested()

    readonly property var _lines: message.split("\n")
    readonly property string _title: _lines.length > 0 ? _lines[0] : ""
    readonly property string _body: _lines.length > 1 ? _lines.slice(1).join("\n") : ""

    implicitWidth: 312
    implicitHeight: content.implicitHeight + 16

    Rectangle {
        anchors.fill: parent
        color: theme.background
        border.width: 1
        border.color: theme.borderStrong
        radius: theme.radiusCard
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 8
        spacing: 2

        ColorText {
            sourceText: root._title
            defaultColor: theme.text
            font.family: theme.fontVar
            font.bold: true
            font.pixelSize: theme.fontSizeLg
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        ColorText {
            visible: root._body.length > 0
            sourceText: root._body
            defaultColor: theme.text
            font.family: theme.fontVar
            font.pixelSize: theme.fontSize
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        Button {
            label: "Dismiss"
            Layout.alignment: Qt.AlignRight
            Layout.preferredWidth: 70
            Layout.preferredHeight: 20
            onClicked: root.dismissRequested()
        }
    }
}
