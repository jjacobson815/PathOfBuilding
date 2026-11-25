import QtQuick
import QtQuick.Layouts

// AboutPopup — Tier 1.4, ports main:OpenAboutPopup (Modules/Main.lua:1356):
// version/fork header, a GitHub link, a Version-history/Help tab toggle, and
// the TextListControl (its first real consumer) rendering changelog.txt /
// help.txt. Content comes from luaEngine.getAboutContent() (parsed by the
// pob_getAboutContent Lua global, mirroring OpenAboutPopup's own file-parsing
// algorithm verbatim — see pob_host.lua).
PopupBase {
    id: root
    title: " About "

    // Set by the parent (BottomBar already fetched it once — avoids
    // re-parsing changelog.txt/help.txt on every open).
    property var content: null
    property bool showHelp: false
    property var updateState: ({})

    function refreshUpdateState() {
        var st = luaEngine.invoke("pob_getUpdateState")
        if (st) {
            updateState = st
        }
    }

    Component.onCompleted: refreshUpdateState()
    onOpened: refreshUpdateState()

    Connections {
        target: luaEngine
        function onUpdateChanged() { root.refreshUpdateState() }
    }

    readonly property var _list: showHelp ? ((content && content.helpList) || []) : ((content && content.changeList) || [])
    readonly property var _sectionHeights: showHelp ? ((content && content.helpSectionHeights) || []) : ((content && content.changeVersionHeights) || [])

    width: 810
    height: 628
    padding: 10

    // Called by main.qml's F1 handler / the About button. tabNameLower === ""
    // opens on Version History (matches the About button's plain OpenAboutPopup()
    // call); otherwise opens on Help, scrolled to the matching section (case-
    // insensitive title match, falling back to the first section — mirrors
    // legacy's helpSectionIndex resolution in OpenAboutPopup).
    function openAtSection(tabNameLower) {
        if (!tabNameLower || tabNameLower.length === 0) {
            showHelp = false;
        } else {
            showHelp = true;
            var sections = (root.content && root.content.helpSections) || [];
            var idx = 0;
            for (var i = 0; i < sections.length; i++) {
                if ((sections[i].title || "").toLowerCase() === tabNameLower) { idx = i; break; }
            }
            var heights = (root.content && root.content.helpSectionHeights) || [];
            var target = idx < heights.length ? heights[idx] : 0;
            Qt.callLater(function() { list.setScrollOffset(target); });
        }
        root.open();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                spacing: 2
                ColorText {
                    sourceText: "^7Path of Building Community Fork v" + ((root.content && root.content.versionNumber) || "")
                    defaultColor: theme.text
                }
                ColorText {
                    sourceText: "^7Based on Openarl's Path of Building"
                    defaultColor: theme.text
                }
                Button {
                    label: "GitHub: github.com/PathOfBuildingCommunity/PathOfBuilding"
                    Layout.preferredWidth: 440
                    Layout.preferredHeight: 20
                    onClicked: luaEngine.openURL("https://github.com/PathOfBuildingCommunity/PathOfBuilding")
                }
                RowLayout {
                    spacing: 8
                    Button {
                        label: "Check for Updates"
                        Layout.preferredWidth: 130
                        Layout.preferredHeight: 20
                        controlEnabled: !(root.updateState && root.updateState.checking)
                        onClicked: luaEngine.invoke("pob_checkForUpdates", [{ force: true }])
                    }
                    Label {
                        size: theme.fontSize
                        label: {
                            var st = root.updateState || {}
                            if (st.checking || st.status === "checking") return "^7Checking..."
                            if (st.status === "available") return "^2Update available: " + (st.latestVersion || "")
                            if (st.status === "up_to_date") return "^7Up to date"
                            if (st.status === "error") return "^1" + (st.error || "Update check failed")
                            return ""
                        }
                    }
                    Button {
                        visible: Boolean(root.updateState && root.updateState.status === "available")
                        label: "Open Release"
                        Layout.preferredWidth: 100
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
                }
            }
            Item { Layout.fillWidth: true }
            Button {
                label: "Close"
                Layout.preferredWidth: 60
                Layout.preferredHeight: 20
                onClicked: root.accept()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Button {
                label: "Version history"
                Layout.preferredWidth: 120
                Layout.preferredHeight: 20
                locked: !root.showHelp
                onClicked: root.showHelp = false
            }
            Button {
                label: "Help"
                Layout.preferredWidth: 60
                Layout.preferredHeight: 20
                locked: root.showHelp
                onClicked: root.showHelp = true
            }
        }

        TextListControl {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: [ { x: 1, align: "LEFT" }, { x: 135, align: "LEFT" } ]
            list: root._list
            sectionHeights: root._sectionHeights
        }
    }
}
