import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import "views"
// Namespaced import (avoids the components/Button.qml vs QtQuick.Controls.Button
// ambiguity this file's top bar relies on): reach the component library as
// Widgets.* — here for the real MessagePopup wired to the cloud/path error signals.
import "components" as Widgets

// Phase 1c/2a/3 MainWindow. The top bar is always present. The body swaps
// between the BUILD page (collapsible sidebar + typed-model content) and the
// LIST page (build library browser) depending on luaEngine.currentMode.
// All colours/sizes come from the engine theme singleton (context property
// "theme"); nothing is hardcoded.
//
// Part 1.1 (Phase 1): the monolithic view bodies were extracted into
// app/qml/views/*.qml (imported above). This file is now the app shell:
// window state, the top bar, the sidebar, and the StackLayout that hosts the
// view components. Each view instance's visibility is driven here from
// root.activeView; the components themselves are self-contained.
Window {
    id: root
    visible: true
    width: 1100
    height: 720
    title: "Path of Building"
    color: theme.background

    // Engine state is event-driven: activeMode/activeView are bound to the
    // luaEngine.currentMode/currentView Q_PROPERTYs, which emit
    // currentModeChanged/currentViewChanged on every genuine mutation. No
    // polling Timer is used, so the UI sits at 0% CPU when idle.
    property string activeMode: luaEngine.currentMode
    property string activeView: luaEngine.currentView
    property bool sideBarCollapsed: false

    // Raw view registry from the engine (main.modes.BUILD.viewList).
    property var allViews: luaEngine.viewList()

    // Group the views by `group` ("primary" first, then "utility") for the
    // sidebar. Each entry is { group: string, items: [ {id,label,key,group,tab}, ... ] }.
    property var groups: (function () {
        var buckets = {}
        for (var i = 0; i < allViews.length; i++) {
            var v = allViews[i]
            if (!buckets[v.group]) buckets[v.group] = []
            buckets[v.group].push(v)
        }
        var order = ["primary", "utility"]
        var out = []
        for (var j = 0; j < order.length; j++) {
            if (buckets[order[j]])
                out.push({ group: order[j], items: buckets[order[j]] })
        }
        return out
    })()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- Top bar: title + typed build metadata + current mode + collapse toggle ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: theme.topBarHeight
            color: theme.titleBar
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: theme.space2
                anchors.rightMargin: theme.space2
                spacing: theme.space2
                Button {
                    text: sideBarCollapsed ? ">>" : "<<"
                    onClicked: sideBarCollapsed = !sideBarCollapsed
                    ToolTip.text: "Collapse / expand sidebar"
                    ToolTip.visible: hovered
                    ToolTip.delay: 250
                }
                Text {
                    text: "Path of Building"
                    color: theme.text
                    font.bold: true
                    font.pixelSize: theme.fontSize + 2
                }
                // Phase 3: mode-switch bar (toggle LIST / BUILD). Buttons are
                // generated from luaEngine.modeNames() and call setMode(name).
                Repeater {
                    model: luaEngine.modeNames()
                    delegate: Button {
                        text: modelData
                        highlighted: activeMode === modelData
                        onClicked: luaEngine.setMode(modelData)
                    }
                }
                Item { Layout.fillWidth: true }
                // Phase 2a: typed, signal-driven build metadata.
                Text {
                    text: "Build: " + (buildModel.buildName || "—")
                    color: theme.text
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.maximumWidth: 220
                    Layout.minimumWidth: 60
                }
                Text {
                    text: "Lv " + buildModel.characterLevel
                    color: theme.text
                }
                Text {
                    text: (buildModel.className || "?") +
                          (buildModel.ascendClassName ? " (" + buildModel.ascendClassName + ")" : "")
                    color: theme.text
                }
                Text {
                    text: "Mode: " + activeMode
                    color: theme.accent
                    font.bold: true
                }
            }
        }

        // --- Body: swaps between BUILD page and LIST page by mode ---
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: activeMode === "LIST" ? 1 : 0

            // ===== Page 0: BUILD (sidebar + content) =====
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Sidebar (collapsible; width animates between 0 and theme.sideBarWidth).
                Rectangle {
                    id: sideBar
                    Layout.fillHeight: true
                    // NOTE: never put a Behavior directly on a Layout.* attached
                    // property — it corrupts the layout's size-hint bookkeeping and
                    // starves sibling fillWidth items of space (content collapsed to 0).
                    // Animate a plain proxy property and bind the attached prop to it.
                    property real _sideBarW: sideBarCollapsed ? 0 : theme.sideBarWidth
                    Behavior on _sideBarW { NumberAnimation { duration: 150 } }
                    Layout.preferredWidth: _sideBarW
                    color: theme.sideBarBg
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: theme.space2
                        anchors.topMargin: theme.space2
                        anchors.rightMargin: theme.space2
                        spacing: theme.navRowGap

                        Repeater {
                            model: groups
                            delegate: ColumnLayout {
                                Layout.fillWidth: true
                                spacing: theme.navButtonGap
                                Text {
                                    text: modelData.group === "primary" ? "BUILD" : "TOOLS"
                                    color: theme.section
                                    font.family: theme.fontFamily
                                    font.weight: theme.fontWeightBold
                                    font.pixelSize: theme.fontSizeSm
                                }
                                Repeater {
                                    model: modelData.items
                                    delegate: Rectangle {
                                        id: navBtn
                                        Layout.alignment: Qt.AlignLeft
                                        Layout.preferredWidth: modelData.group === "primary"
                                            ? theme.navWidthPrimary : theme.navWidthUtility
                                        Layout.preferredHeight: theme.navButtonHeight
                                        radius: theme.radiusControl
                                        // Hover background is bound to the MouseArea's
                                        // containsMouse property (event-driven, no Timer).
                                        color: navMa.containsMouse ? theme.hover : "transparent"
                                        // Legacy SimpleGraphic draws a 3px accent bar on
                                        // the LEFT EDGE of the active tab (selection state
                                        // bound to the activeView property).
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            width: 3
                                            color: theme.accent
                                            visible: activeView === modelData.id
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            width: parent.width
                                            elide: Text.ElideRight
                                            clip: true
                                            horizontalAlignment: Text.AlignHCenter
                                            text: modelData.label
                                            color: theme.text
                                            font.family: theme.fontFamily
                                            font.weight: theme.fontWeightNormal
                                            font.pixelSize: theme.fontSize
                                        }
                                        MouseArea {
                                            id: navMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: luaEngine.setActiveView(modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Content area: hosts every BUILD-mode view. Each child view toggles
                // itself via `visible: root.activeView === "X"` (set here, at the
                // instantiation site). Part 1.1 extracted the view bodies into
                // app/qml/views/*.qml; this Rectangle just parents + shows them.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: true
                    color: theme.background

                    // Passive-tree view (Canvas renderer + hover tooltip).
                    TreeView {
                        visible: root.activeView === "TREE"
                    }

                    // Generic placeholder for views without a dedicated UI yet.
                    PlaceholderView {
                        activeView: root.activeView
                        visible: root.activeView !== "TREE" && root.activeView !== "ITEMS"
                                 && root.activeView !== "SKILLS" && root.activeView !== "CALCS"
                                 && root.activeView !== "CONFIG" && root.activeView !== "NOTES"
                                 && root.activeView !== "IMPORT" && root.activeView !== "COMPARE"
                                 && root.activeView !== "PARTY"
                    }

                    SkillsView  { visible: root.activeView === "SKILLS" }
                    ItemsView   { visible: root.activeView === "ITEMS" }
                    CalcsView   { visible: root.activeView === "CALCS" }
                    ConfigView  { visible: root.activeView === "CONFIG" }
                    NotesView   { visible: root.activeView === "NOTES" }
                    ImportView  { visible: root.activeView === "IMPORT" }
                    CompareView { visible: root.activeView === "COMPARE" }
                    PartyView   { visible: root.activeView === "PARTY" }
                }
            }

            // ===== Page 1: LIST (build library browser) =====
            BuildListPage {}
        }

        // --- Bottom bar: Options / About / (inert) Check for Update + version ---
        Rectangle {
            id: bottomBarRow
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            color: theme.titleBar
            Widgets.BottomBar {
                id: bottomBar
                anchors.fill: parent
                onOptionsRequested: optionsDialog.open()
                onAboutRequested: (section) => aboutPopup.openAtSection(section)
            }
        }
    }

    // Part 1.4: toast notification stack — bottom-left, floating just above
    // the bottom bar (matches legacy anchorMain's BOTTOMLEFT anchor).
    // Anchored to `parent` (this Item's actual parent, the Window's content
    // item) rather than to bottomBarRow directly — QML anchors only allow
    // targeting a parent or sibling, and bottomBarRow lives inside the
    // ColumnLayout, several levels away. bottomBarRow.height is a plain
    // property reference (not an anchor), so referencing it in the margin
    // expression is unrestricted and keeps the stack pinned just above the
    // bar regardless of its height.
    Widgets.ToastStack {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: theme.space2
        anchors.bottomMargin: bottomBarRow.height + theme.space1
    }

    // Part 1.4: real cloud/path error dialogs. The engine's OpenCloudErrorPopup /
    // OpenPathPopup build SimpleGraphic control trees that are inert under QML;
    // they now hand off to LuaEngine (pob.cloudErrorPopup / pob.pathErrorPopup),
    // which emits these signals. We open a real MessagePopup (Tier 0) in response.
    Widgets.MessagePopup {
        id: cloudErrorPopup
        title: " Error "
    }
    Widgets.MessagePopup {
        id: pathErrorPopup
        title: " Settings Path Error "
    }
    // Part 1.4: the ~28-setting Options dialog (main:OpenOptionsPopup port). It is
    // driven entirely by the luaEngine.getOptions/previewOption/commitOptions
    // bridge and self-loads current engine state on open. Opened by the
    // BottomBar's Options button via bottomBar.onOptionsRequested above.
    Widgets.OptionsDialog {
        id: optionsDialog
    }

    // Part 1.4: About popup (main:OpenAboutPopup port) — changelog.txt/help.txt
    // viewer. Reuses BottomBar's already-fetched content (avoids re-parsing).
    // Opened by the BottomBar's About button (Version History tab) or F1
    // (Help tab, scrolled to the current view's section) below.
    Widgets.AboutPopup {
        id: aboutPopup
        content: bottomBar.aboutContent
    }

    // Part 1.4: F1 context help, mirroring main:OnFrame's F1 handler
    // (Modules/Main.lua:440): open About on the Help tab, scrolled to the
    // section matching the active view ("<viewId> tab", e.g. "skills tab"),
    // or "build list tab" in LIST mode / when no view is active.
    Shortcut {
        sequence: "F1"
        onActivated: {
            var section = (root.activeMode === "LIST" || !root.activeView)
                ? "build list tab"
                : root.activeView.toLowerCase() + " tab"
            aboutPopup.openAtSection(section)
        }
    }

    Connections {
        target: luaEngine
        function onCloudErrorRequested(path, provider, status) {
            var prov = (provider && provider.length) ? provider : "your cloud provider"
            cloudErrorPopup.message =
                "^7Cannot read settings file.\n\n" +
                "Make sure " + prov + " is running, then restart\n" +
                "Path of Building and try again.\n\n" +
                (path && path.length ? "^8'" + path + "'\n" : "") +
                "^7status: " + status
            cloudErrorPopup.open()
        }
        function onPathErrorRequested(invalidPath, errMsg) {
            pathErrorPopup.message =
                "^7User settings path cannot be loaded:\n" +
                "^1" + errMsg + "\n\n" +
                "^7Current path:\n^8'" + invalidPath + "'"
            pathErrorPopup.open()
        }
    }
}
