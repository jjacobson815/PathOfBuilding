import QtQuick
import QtQuick.Layouts
// Namespaced: an unqualified QtQuick.Controls import would make the bare type
// name `Button` ambiguous against this directory's own Button.qml.
import QtQuick.Controls as QC

// ConversionPopup — Phase 3, ports buildMode:OpenConversionPopup
// (src/Modules/Build.lua:1287-1312).
//
// THIS POPUP FIXES A LIVE HANG, it is not cosmetic. Build:Init
// (Build.lua:104-108) sets `self.targetVersion = nil` and RETURNS EARLY when a
// build's targetVersion differs from liveTargetVersion, delegating recovery to
// OpenConversionPopup's SimpleGraphic buttons. Those controls are inert under
// QML (invariant #1 — the draw globals are stubbed), so opening any build made
// for an older game version dropped the app into a half-initialised BUILD mode
// that buildMode:OnFrame then refused to advance (Build.lua:1164-1167), with no
// visible dialog and no way back to the build list. Mounting this popup and
// auto-opening it on `needsConversion` is the QML-side replacement.
//
// The two body paragraphs are legacy's verbatim text (Build.lua:1290-1301).
// Deviation: legacy embeds colorCodes.TIP / colorCodes.WARNING inline in the
// string; here the "Info:" / "Warning:" leads are separate Texts coloured from
// theme.info / theme.warning, so the popup follows the app's design tokens
// instead of pinning two literal hex values that would drift from the theme.
PopupBase {
    id: root

    title: " Game Version "

    // Filled by the caller from luaEngine.getConversionState().
    property string liveDisplay: ""
    property string buildName: ""

    // Emitted after a successful conversion so the shell can refresh its models.
    signal converted()
    // Emitted when the user declines — the caller must leave BUILD mode, since
    // the engine is sitting in the half-initialised state described above and
    // there is nothing else to do with it.
    signal declined()

    padding: 16
    // A dead BUILD mode must not be dismissible by Escape or a click-away:
    // the only two exits are Convert or Cancel, both of which resolve the state.
    closePolicy: QC.Popup.NoAutoClose

    ColumnLayout {
        spacing: 6

        Text {
            text: "Info:"
            color: theme.info
            font.bold: true
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize
        }
        Repeater {
            model: [
                "You are trying to load a build created for a version of Path of Exile that is",
                "not supported by us. You will have to convert it to the current game version to load it.",
                "To use a build newer than the current supported game version, you may have to update.",
                "To use a build older than the current supported game version, we recommend loading it",
                "in an older version of Path of Building Community instead."
            ]
            delegate: ColorText {
                sourceText: modelData
                defaultColor: theme.text
                font.pixelSize: theme.fontSize
            }
        }

        Item { Layout.preferredHeight: 10 }

        Text {
            text: "Warning:"
            color: theme.warning
            font.bold: true
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize
        }
        Repeater {
            model: [
                "Converting a build to a different game version may have side effects.",
                "For example, if the passive tree has changed, then some passives may be deallocated.",
                "You should create a backup copy of the build before proceeding."
            ]
            delegate: ColorText {
                sourceText: modelData
                defaultColor: theme.text
                font.pixelSize: theme.fontSize
            }
        }

        Item { Layout.preferredHeight: 12 }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            PopupButton {
                label: "Convert to " + (root.liveDisplay.length > 0 ? root.liveDisplay : "current")
                onClicked: {
                    var r = luaEngine.convertBuild()
                    if (r && r.ok) {
                        root.close()
                        root.converted()
                    } else {
                        // Conversion genuinely failed (the engine could not
                        // re-Init at the live version). Leaving the popup open
                        // with a dead build behind it helps nobody — bail to
                        // the build list, which is the only recoverable state.
                        root.close()
                        root.declined()
                    }
                }
            }
            PopupButton {
                label: "Cancel"
                onClicked: {
                    root.close()
                    root.declined()
                }
            }
        }
    }
}
