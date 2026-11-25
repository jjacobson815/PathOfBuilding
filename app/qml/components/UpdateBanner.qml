import QtQuick
import QtQuick.Layouts

// UpdateBanner — Phase 14.2: non-intrusive, dismissible update notification
// banner driven by pob_update.lua via luaEngine.onUpdateChanged.
Item {
    id: root
    objectName: "pob.updatebanner.root"

    property var updateState: ({})

    readonly property bool updateAvailable: Boolean(updateState && updateState.available)
    readonly property bool isDismissed: Boolean(updateState && updateState.dismissed)

    visible: updateAvailable && !isDismissed
    implicitHeight: visible ? 30 : 0
    implicitWidth: 600

    function refresh() {
        var st = luaEngine.invoke("pob_getUpdateState")
        if (st) {
            updateState = st
        }
    }

    Component.onCompleted: refresh()

    Connections {
        target: luaEngine
        function onUpdateChanged() { root.refresh() }
    }

    Rectangle {
        anchors.fill: parent
        color: theme.topBarBg
        border.width: 1
        border.color: theme.borderStrong

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: theme.accent
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: theme.space3
            anchors.rightMargin: theme.space3
            spacing: theme.space2

            Label {
                objectName: "pob.updatebanner.msg"
                Layout.fillWidth: true
                elide: Text.ElideRight
                size: theme.fontSize
                label: {
                    var cur = (root.updateState && root.updateState.currentVersion) ? root.updateState.currentVersion : "?"
                    var lat = (root.updateState && root.updateState.latestVersion) ? root.updateState.latestVersion : "?"
                    return "^7Update available: ^2" + cur + " -> " + lat
                }
            }

            Button {
                objectName: "pob.updatebanner.open"
                label: "Open Release Page"
                Layout.preferredWidth: 136
                Layout.preferredHeight: 20
                onClicked: {
                    var url = (root.updateState && root.updateState.releaseUrl) ? root.updateState.releaseUrl : ""
                    if (!url || url.length === 0) {
                        var repo = (root.updateState && root.updateState.repo) ? root.updateState.repo : "jjacobson815/PathOfBuilding"
                        url = "https://github.com/" + repo + "/releases/latest"
                    }
                    Qt.openUrlExternally(url)
                }
            }

            Button {
                objectName: "pob.updatebanner.dismiss"
                label: "Dismiss"
                Layout.preferredWidth: 68
                Layout.preferredHeight: 20
                onClicked: luaEngine.invoke("pob_dismissUpdate")
            }
        }
    }
}
