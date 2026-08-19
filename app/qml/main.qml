import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQml            // Instantiator, for the generated Ctrl+N view hotkeys
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

        // --- Top bar (Phase 3) ---------------------------------------
        // Was an inline RowLayout of read-only Texts. Now the real shell bar:
        // Back / Save / Save As, build-name plate with unsaved marker, points
        // plate, Auto|Manual + level edit, and the class / ascendancy /
        // secondary-ascendancy dropdowns. Lives in components/TopBar.qml.
        //
        // NOTE the two Buttons that used to be here resolved to
        // QtQuick.Controls.Button (this file imports Controls unqualified).
        // Inside components/ that same bare name would collide with
        // components/Button.qml, so TopBar.qml uses the library Button with
        // `label:` rather than `text:`.
        Widgets.TopBar {
            id: topBar
            Layout.fillWidth: true
            Layout.preferredHeight: theme.topBarHeight

            onCollapseToggled: (collapsed) => root.sideBarCollapsed = collapsed
            onSaveAsRequested: saveAsPopup.openForCurrentBuild()
            onSavePromptRequested: (mode) => savePrompt.openFor(mode)
            onSaveFailed: (error) => {
                saveErrorPopup.message = "^7Could not save the build. ^1" + error
                saveErrorPopup.open()
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

                        // Phase 3: the live stat panel + warnings row. These are
                        // the first real consumers of Phase 2's output
                        // marshalling -- if a number here is wrong, fix the
                        // marshalling, not the panel.
                        Item { Layout.preferredHeight: theme.space2 }

                        // Part 3.2: socket group / active skill / part / stages /
                        // mines / minion / minion skill. Which of these appear is
                        // decided by the engine payload, not by QML.
                        Widgets.MainSkillPanel {
                            id: mainSkillPanel
                            Layout.fillWidth: true
                            suffix: ""
                            onManageSpectresRequested: spectreNotice.open()
                        }

                        Item { Layout.preferredHeight: theme.space1 }

                        Widgets.StatPanel {
                            id: statPanel
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                        }

                        Widgets.WarningsBar {
                            id: warningsBar
                            Layout.fillWidth: true
                            Layout.bottomMargin: theme.space2
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

    // ===== Phase 3: shell popups ==========================================

    // Save As. A minimal but real implementation: prompt for a name, run it
    // through the engine's own filename filter, refuse to overwrite, then save
    // through the recalc-gated path. The full legacy folder-browser (Build.lua:
    // 1343-1412, with New Folder and a sort mode) is deliberately NOT built
    // here — it is long-tail per the phase plan, and this covers the actual
    // "save a new build somewhere" need.
    Widgets.TextInputPopup {
        id: saveAsPopup
        title: " Save As "
        prompt: "^7Enter build name:"
        confirmLabel: "Save"

        property var _check: ({ valid: false, exists: false, fullPath: "" })
        property string _subPath: ""

        // Legacy's filter is the Lua class [\/:%*%?"<>|%c] (Build.lua:1362) and
        // it enables Save only when io.open(name,"r") returns nil, i.e. it
        // refuses to clobber (Build.lua:1352-1358). Both live in the engine, so
        // ask it rather than re-implementing the rule in QML.
        confirmEnabled: _check.valid && !_check.exists

        function openForCurrentBuild() {
            var shell = luaEngine.getShellState() || {}
            _subPath = shell.dbFileSubPath || ""
            text = shell.buildName || ""
            recheck()
            open()
        }
        function recheck() {
            _check = luaEngine.sanitizeBuildName(text, _subPath) || { valid: false }
        }
        onTextChanged: recheck()
        onAccepted: {
            var r = luaEngine.saveDBFile(_check.fullPath)
            if (!r || !r.ok) {
                saveErrorPopup.message = "^7Could not save the build. ^1" + (r ? r.error : "unknown error")
                saveErrorPopup.open()
            }
        }
    }

    Widgets.MessagePopup {
        id: saveErrorPopup
        title: " Save Failed "
    }

    // The Spectre Library (Build.lua:1415) is explicit Phase 3 long tail — it
    // needs dual-pane drag-between-lists, which --capture cannot verify anyway.
    // The button is wired now so the seam exists; this says so rather than
    // silently doing nothing when it is clicked.
    Widgets.MessagePopup {
        id: spectreNotice
        title: " Manage Spectres "
        message: "^7The Spectre Library is not built yet.^8 It is tracked as Phase 3 long-tail work; spectres already round-trip through the build XML."
    }

    // Save / Don't Save / Cancel (Build.lua:1314-1341). `mode` decides what
    // happens after the save resolves: LIST closes the build, EXIT quits.
    Widgets.ConfirmPopup {
        id: savePrompt
        title: " Unsaved Changes "
        confirmLabel: "Save"
        extraLabel: "Don't Save"

        property string mode: "LIST"

        function openFor(m) {
            mode = m
            message = "^7This build has unsaved changes.\nDo you want to save them before continuing?"
            open()
        }
        function _finish() {
            if (mode === "EXIT") Qt.quit()
            else luaEngine.closeBuild()
        }
        onAccepted: {
            var shell = luaEngine.getShellState() || {}
            if (!shell.dbFileName || shell.dbFileName.length === 0) {
                saveAsPopup.openForCurrentBuild()
                return
            }
            var r = luaEngine.saveDBFile("")
            if (r && r.ok) _finish()
            else {
                saveErrorPopup.message = "^7Could not save the build. ^1" + (r ? r.error : "unknown error")
                saveErrorPopup.open()
            }
        }
        onExtraClicked: { close(); _finish() }
    }

    // Version conversion. This is a HANG FIX, not a nicety — see the header of
    // components/ConversionPopup.qml. Opened automatically whenever the engine
    // reports a build that failed its targetVersion check, because in that
    // state BUILD mode is half-initialised and nothing else can proceed.
    Widgets.ConversionPopup {
        id: conversionPopup
        onConverted: {
            topBar.refresh()
            statPanel.refresh()
            warningsBar.refresh()
        }
        onDeclined: luaEngine.setListMode()
    }

    function checkConversion() {
        if (root.activeMode !== "BUILD") return
        var cs = luaEngine.getConversionState() || {}
        if (cs.needsConversion && !conversionPopup.visible) {
            conversionPopup.liveDisplay = cs.liveDisplay || ""
            conversionPopup.buildName = cs.buildName || ""
            conversionPopup.open()
        }
    }

    onActiveModeChanged: checkConversion()

    Component.onCompleted: {
        // Adopt the persisted sidebar state (Settings.xml via
        // main.sideBarCollapsed) instead of always starting expanded.
        var shell = luaEngine.getShellState()
        if (shell) root.sideBarCollapsed = shell.sideBarCollapsed || false
        checkConversion()
    }

    // ===== Phase 3: hotkeys ================================================
    // Ports the Ctrl-key block of buildMode:OnFrame (Build.lua:1173-1204).
    // That block ran per frame off inputEvents; with no frame loop these are
    // real QML Shortcuts instead. Ctrl+1..9 come from the viewList registry's
    // own `key` field, so the bindings stay correct if the registry changes.
    Instantiator {
        model: root.allViews
        delegate: Shortcut {
            sequence: "Ctrl+" + modelData.key
            enabled: root.activeMode === "BUILD"
            onActivated: luaEngine.setActiveView(modelData.id)
        }
    }

    Shortcut {
        // Not StandardKey.Save: that maps to multiple sequences on Windows and
        // Qt warns it will bind only one of them. Legacy documents Ctrl+S.
        sequence: "Ctrl+S"
        enabled: root.activeMode === "BUILD"
        onActivated: {
            var shell = luaEngine.getShellState() || {}
            if (!shell.dbFileName || shell.dbFileName.length === 0) {
                saveAsPopup.openForCurrentBuild()
                return
            }
            var r = luaEngine.saveDBFile("")
            if (!r || !r.ok) {
                saveErrorPopup.message = "^7Could not save the build. ^1" + (r ? r.error : "unknown error")
                saveErrorPopup.open()
            }
        }
    }

    Shortcut {
        sequence: "Ctrl+W"
        enabled: root.activeMode === "BUILD"
        onActivated: {
            if (luaEngine.getUnsaved().unsaved) savePrompt.openFor("LIST")
            else luaEngine.closeBuild()
        }
    }

    // Closing the window with unsaved work must prompt, mirroring
    // buildMode:CanExit (Build.lua:945).
    onClosing: (close) => {
        if (root.activeMode === "BUILD" && luaEngine.getUnsaved().unsaved) {
            close.accepted = false
            savePrompt.openFor("EXIT")
        }
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
