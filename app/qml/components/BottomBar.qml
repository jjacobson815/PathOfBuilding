import QtQuick
import QtQuick.Layouts

// BottomBar — Tier 1.4, ports main:Init's anchorMain control block
// (Modules/Main.lua:205-240): Options / About buttons, the fork/version
// labels (^8-coded, matching legacy exactly), the Dev Mode label gated on
// devMode, and an inert "Check for Update" button. Networking (the real
// update check) is Phase 10/14 scope — the button stays present but
// disabled with an explanatory tooltip, matching the plan's "keep the UI,
// defer the wiring" approach.
//
// Owns no popups itself (matches the existing MessagePopup/OptionsDialog
// convention in main.qml): emits optionsRequested()/aboutRequested(section)
// and the parent wires them to the real dialogs.
Item {
    id: root

    signal optionsRequested()
    signal aboutRequested(string section)

    // Static per-session content (changelog.txt/help.txt don't change while
    // running) — fetched once here and reused; AboutPopup.qml also reads
    // this instead of re-fetching, since main.qml passes it down.
    readonly property var aboutContent: luaEngine.getAboutContent()
    readonly property string versionNumber: aboutContent ? aboutContent.versionNumber : ""
    readonly property string versionBranch: aboutContent ? aboutContent.versionBranch : ""
    readonly property bool devMode: aboutContent ? !!aboutContent.devMode : false

    implicitHeight: 24

    RowLayout {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 4
        spacing: 4

        Button {
            label: "Options"
            Layout.preferredWidth: 68
            Layout.preferredHeight: 20
            onClicked: root.optionsRequested()
        }
        Button {
            label: "About"
            Layout.preferredWidth: 68
            Layout.preferredHeight: 20
            onClicked: root.aboutRequested("")
        }
        Button {
            label: "Check for Update"
            Layout.preferredWidth: 140
            Layout.preferredHeight: 20
            controlEnabled: false
            tooltipText: "Update checking is not yet implemented in this port (Phase 10/14)."
        }
        ColumnLayout {
            spacing: 0
            ColorText {
                sourceText: "^8PoB Community Fork"
                defaultColor: theme.text
                font.pixelSize: theme.fontSizeSm
            }
            ColorText {
                sourceText: "^8" + (root.versionBranch === "beta" ? "Beta: " : "Version: ") +
                            root.versionNumber + (root.versionBranch === "dev" ? " (Dev)" : "")
                defaultColor: theme.text
                font.pixelSize: theme.fontSizeSm
            }
        }
        ColorText {
            visible: root.devMode
            sourceText: "^1Dev Mode"
            defaultColor: theme.danger
            font.pixelSize: theme.fontSizeSm
        }
    }
}
