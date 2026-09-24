import QtQuick
import QtQuick.Window
import QtQuick.Layouts

// TopBar — Phase 3, ports buildMode's anchorTopBar control block
// (Modules/Build.lua:121-308): `toggleSideBar` / `back` / `save` / `saveAs`,
// the `buildName` plate with its unsaved marker, and the right-hand cluster
// `pointDisplay` / `levelScalingButton` / `characterLevel` / `classDrop` /
// `ascendDrop` / `secondaryAscendDrop`, plus the mode readout. Replaces the
// inline RowLayout main.qml carried through Phases 1-2.
//
// QtQuick.Controls is deliberately NOT imported. This directory owns
// Button.qml, and same-directory types resolve implicitly, so an unqualified
// `import QtQuick.Controls` makes the bare name `Button` AMBIGUOUS — a hard
// QML-load error that surfaces as a silent empty window, not a console
// message. Nothing here needs Controls directly: DropDownControl,
// EditControl and ConfirmPopup already encapsulate (and namespace) the
// Controls types they use.
//
// STATE MODEL — the load-bearing part. getShellState() is not a pure getter:
// it runs EstimatePlayerProgress, which MUTATES characterLevel in auto mode
// and appends point-overflow warnings (LuaEngine.h, Phase 3 note). It is
// therefore called exactly once per refresh() and cached into `shell`;
// nothing below binds to it. refresh() runs on completion and from the
// explicit engine-signal handlers at the bottom of this file.
//
// The dropdowns' `currentIndex` and the level field's `text` are pushed in
// imperatively (_syncControls) rather than bound, because both widgets write
// those properties themselves on a user interaction (DropDownControl._pick,
// EditControl.onTextEdited) — which would clobber a declarative binding for
// the rest of the session.
//
// Deviations from legacy (documented, not gaps):
//   - The `buildLoadouts` dropdown (Build.lua:308) is not ported here; build
//     loadouts are their own work item.
//   - Legacy's buildName control derives its width by subtracting every
//     sibling's width from the bar (Build.lua:150-155). RowLayout does that
//     natively with a spacer plus a maximum width, so the arithmetic is gone.
//   - This component owns no file dialogs and no unsaved-changes prompt: Back
//     / Save / Save As raise signals and the shell wires them, matching the
//     BottomBar convention. The class-change confirm is the one exception —
//     it is a canned ConfirmPopup with no host-side state.
Rectangle {
    id: root

    // --- parent contract ---------------------------------------------------
    signal collapseToggled(bool collapsed)
    signal saveAsRequested()
    signal saveFailed(string error)
    signal savePromptRequested(string mode)

    // --- cached engine state (never bound; see header) ---------------------
    property var shell: ({})
    property var classList: ({ classes: [], secondaryAscendancies: [] })

    // Every read below goes through these guards: getShellState()/getClassList()
    // both return null in LIST mode (no build), and a null payload must degrade
    // to an inert bar rather than throw out of a binding.
    // NOTE: main.modes.BUILD (and its spec) OUTLIVE CloseBuild, so
    // getShellState() still returns a full payload while the app is in LIST
    // mode. Testing the payload alone therefore left Back/Save/level/class
    // live on top of the build library. The mode itself is the real gate.
    readonly property bool inBuildMode: luaEngine.currentMode === "BUILD"
    readonly property bool hasBuild: inBuildMode && shell.level !== undefined
    readonly property bool collapsed: shell.sideBarCollapsed === true
    readonly property bool unsaved: shell.unsaved === true
    readonly property string buildName: shell.buildName ? shell.buildName : ""
    readonly property string subPath: shell.dbFileSubPath ? shell.dbFileSubPath : ""
    readonly property var points: shell.points ? shell.points : ({})
    readonly property string pointsStr: points.str ? points.str : ""
    readonly property string pointsTooltip: points.tooltip ? points.tooltip : ""

    readonly property var classes: classList.classes ? classList.classes : []
    readonly property var secondaries:
        classList.secondaryAscendancies ? classList.secondaryAscendancies : []
    readonly property var curClass: (function () {
        var cs = root.classes
        for (var i = 0; i < cs.length; i++)
            if (cs[i].classId === root.classList.curClassId) return cs[i]
        return null
    })()
    readonly property var ascendancies:
        (curClass && curClass.ascendancies) ? curClass.ascendancies : []

    // Window handle, for tooltip viewport math and for reparenting the confirm
    // dialog out of this 32px strip.
    readonly property var _win: Window.window
    // Re-entrancy latch: refresh() calls into the engine, and a recalc can emit
    // calcsChanged() synchronously straight back into our own handler.
    property bool _refreshing: false
    property int _pendingClassId: -1

    color: theme.titleBar
    implicitHeight: theme.topBarHeight
    // Tooltips raised by the controls below hang BELOW the bar, into whatever
    // sibling the shell stacks underneath it. Same caveat Button.qml documents;
    // lifting the whole bar is the cheap fix at this level.
    z: 1

    // --- state ------------------------------------------------------------

    function refresh() {
        if (root._refreshing) return
        root._refreshing = true
        var s = luaEngine.getShellState()
        root.shell = s ? s : ({})
        root.refreshClasses()
        root._refreshing = false
    }

    function refreshClasses() {
        var cl = luaEngine.getClassList()
        root.classList = cl ? cl : ({ classes: [], secondaryAscendancies: [] })
        root._syncControls()
    }

    function _syncControls() {
        classDrop.currentIndex =
            root._indexOfKey(root.classes, "classId", root.classList.curClassId)
        ascendDrop.currentIndex =
            root._indexOfKey(root.ascendancies, "ascendClassId", root.classList.curAscendClassId)
        secondaryDrop.currentIndex =
            root._indexOfKey(root.secondaries, "ascendClassId",
                             root.classList.curSecondaryAscendClassId)
        // Never overwrite a half-typed value under the user's caret.
        if (!levelEdit.editing)
            levelEdit.text = root.hasBuild ? String(root.shell.level) : ""
    }

    function _indexOfKey(list, key, value) {
        if (value === undefined) return -1
        for (var i = 0; i < list.length; i++)
            if (list[i][key] === value) return i
        return -1
    }

    // --- helpers ------------------------------------------------------------

    // Same placement contract as Button._showTooltip: local coordinates, with
    // the window mapped back into them as the flip viewport.
    function _showTip(tip, item) {
        var win = root._win
        var origin = win ? item.mapToItem(win.contentItem, 0, 0) : Qt.point(0, 0)
        var viewport = win ? Qt.rect(-origin.x, -origin.y, win.width, win.height)
                           : Qt.rect(0, 0, item.width, item.height)
        tip.showAt(0, 0, item.width, item.height, viewport)
    }

    // Button renders its label at (height - 4), not theme.fontSize — legacy
    // passes the control height straight through as the DrawString size — so
    // content-derived widths must measure at that size.
    function _btnWidth(text) {
        return textMetrics.width(Math.max(8, theme.controlSize - 4), "VAR", text)
             + 2 * theme.space2
    }

    function _applyClass(mode) {
        if (root._pendingClassId < 0) return
        luaEngine.setClass(root._pendingClassId, mode)
        root._pendingClassId = -1
        root.refresh()
    }

    function _onClassPicked(index) {
        var item = root.classes[index]
        if (!item) return
        var res = luaEngine.setClass(item.classId, "check")
        if (res && res.needsConfirm) {
            // "check" deliberately mutated nothing, so the dropdown is now
            // showing a class the engine has not adopted — put it back before
            // the modal goes up, and leave it correct if the user cancels.
            root._pendingClassId = item.classId
            classConfirm.message =
                "Changing class to " + res.label + " will reset your passive tree.\n" +
                "This can be avoided by connecting one of the " + res.label +
                " starting nodes to your tree."
            classConfirm.extraLabel = (res.canConnect === false) ? "" : "Connect Path"
            root._syncControls()
            classConfirm.open()
            return
        }
        root.refresh()
    }

    function _updateNameTip() {
        nameTip.clear()
        if (!nameMa.containsMouse || root.subPath.length === 0) { nameTip.hide(); return }
        nameTip.addLine(theme.fontSize, root.subPath)
        root._showTip(nameTip, namePlate)
    }

    function _updatePointsTip() {
        pointsTip.clear()
        if (!pointsMa.containsMouse || root.pointsTooltip.length === 0) {
            pointsTip.hide()
            return
        }
        var lines = root.pointsTooltip.split("\n")
        for (var i = 0; i < lines.length; i++)
            pointsTip.addLine(theme.fontSize, lines[i])
        root._showTip(pointsTip, pointsPlate)
    }

    onPointsTooltipChanged: _updatePointsTip()

    // --- layout -------------------------------------------------------------

    // Sized to exactly one control row and centred, so children need no
    // per-item Layout.alignment to sit on the bar's midline.
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: theme.space2
        anchors.rightMargin: theme.space2
        height: theme.controlSize
        spacing: theme.space2

        // ===== left group =====

        Button {
            visible: root.hasBuild
            label: root.collapsed ? ">>" : "<<"
            Layout.preferredWidth: root._btnWidth(">>")
            Layout.preferredHeight: theme.controlSize
            tooltipText: "Collapse / expand the sidebar"
            onClicked: {
                var res = luaEngine.setSideBarCollapsed(!root.collapsed)
                var now = (res && res.collapsed !== undefined) ? res.collapsed : !root.collapsed
                root.refresh()
                root.collapseToggled(now)
            }
        }

        Button {
            visible: root.hasBuild
            label: "<< Back"
            controlEnabled: root.hasBuild
            Layout.preferredWidth: root._btnWidth("<< Back")
            Layout.preferredHeight: theme.controlSize
            tooltipText: "Return to the build list"
            onClicked: {
                if (root.unsaved) root.savePromptRequested("LIST")
                else luaEngine.closeBuild()
            }
        }

        Button {
            visible: root.hasBuild
            label: "Save"
            controlEnabled: root.hasBuild && root.shell.canSave !== false
            Layout.preferredWidth: root._btnWidth("Save")
            Layout.preferredHeight: theme.controlSize
            tooltipText: "Save this build"
            onClicked: {
                // A build that has never been written has no target path;
                // saveDBFile("") would just come back "no file name".
                if (!root.shell.dbFileName || root.shell.dbFileName.length === 0) {
                    root.saveAsRequested()
                    return
                }
                var res = luaEngine.saveDBFile("")
                if (!res || res.ok === false) {
                    root.saveFailed((res && res.error) ? res.error : "save failed")
                    return
                }
                root.refresh()
            }
        }

        Button {
            visible: root.hasBuild
            label: "Save As"
            controlEnabled: root.hasBuild
            Layout.preferredWidth: root._btnWidth("Save As")
            Layout.preferredHeight: theme.controlSize
            tooltipText: "Save this build to a new file"
            onClicked: root.saveAsRequested()
        }

        // Build-name plate. Plain Text (not Label) — a build name is user
        // input, so a stray "^7" in it must render literally rather than be
        // eaten as a colour escape.
        Item {
            visible: root.hasBuild
            id: namePlate

            readonly property string displayName: root.buildName.length > 0 ? root.buildName
                                                                            : "Unnamed build"
            readonly property real markW: unsavedMark.visible ? unsavedMark.width : 0

            Layout.preferredHeight: theme.controlSize
            Layout.minimumWidth: 60
            Layout.maximumWidth: 260
            Layout.preferredWidth:
                textMetrics.width(theme.fontSize, "VAR", displayName) + markW + theme.space1

            Text {
                id: nameText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, namePlate.width - namePlate.markW)
                elide: Text.ElideRight
                text: namePlate.displayName
                color: theme.text
                font.family: theme.fontVar
                font.bold: true
                font.pixelSize: theme.fontSize
            }

            Text {
                id: unsavedMark
                anchors.left: nameText.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.unsaved
                // Text-derived items have READ-ONLY implicitWidth/implicitHeight;
                // width is the assignable one (same rule Label.qml documents).
                width: visible ? textMetrics.width(theme.fontSize, "VAR", " *") : 0
                text: " *"
                color: theme.warning
                font.family: theme.fontVar
                font.bold: true
                font.pixelSize: theme.fontSize
            }

            MouseArea {
                id: nameMa
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onContainsMouseChanged: root._updateNameTip()
            }

            Tooltip { id: nameTip }
        }

        Item { Layout.fillWidth: true }

        // ===== right group =====

        // pointDisplay (Build.lua:196-217). `str` carries legacy colour codes
        // ("^7  0 / 123   ^70 / 8"), which is exactly what Label parses.
        Rectangle {
            visible: root.hasBuild
            id: pointsPlate

            Layout.preferredHeight: theme.controlSize
            Layout.preferredWidth: pointsLabel.width + 2 * theme.space2
            radius: theme.radiusControl
            color: "transparent"
            border.width: 1
            border.color: pointsMa.containsMouse ? theme.borderStrong : theme.border

            Label {
                id: pointsLabel
                anchors.centerIn: parent
                label: root.pointsStr
                size: theme.fontSize
                defaultColor: theme.text
            }

            MouseArea {
                id: pointsMa
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onContainsMouseChanged: root._updatePointsTip()
            }

            Tooltip { id: pointsTip }
        }

        Button {
            visible: root.hasBuild
            id: levelModeButton
            label: root.shell.levelAutoMode ? "Auto" : "Manual"
            controlEnabled: root.hasBuild
            Layout.preferredWidth: root._btnWidth("Manual")
            Layout.preferredHeight: theme.controlSize
            tooltipText: root.shell.levelAutoMode
                ? "Level is estimated from passive point usage. Click to set it manually."
                : "Level is set manually. Click to estimate it from passive point usage."
            onClicked: {
                luaEngine.setLevelAutoMode(!root.shell.levelAutoMode)
                root.refresh()
            }
        }

        EditControl {
            visible: root.hasBuild
            id: levelEdit

            Layout.preferredWidth: 50
            Layout.preferredHeight: theme.controlSize
            controlEnabled: root.hasBuild
            isNumeric: true
            numericMin: 1
            numericMax: 100
            maxChars: 3
            horizontalAlignment: TextInput.AlignHCenter
            placeholder: "Level"
            tooltipText: "Character level (1-100). Editing it switches level tracking to Manual."

            onCommitted: (value) => {
                var n = parseInt(value, 10)
                if (isNaN(n)) { root._syncControls(); return }
                luaEngine.setCharacterLevel(n)
                root.refresh()
            }
            onReverted: root._syncControls()
        }

        DropDownControl {
            visible: root.hasBuild
            id: classDrop

            Layout.preferredWidth: 95
            Layout.preferredHeight: theme.controlSize
            controlEnabled: root.hasBuild
            placeholder: "Class"
            tooltipText: "Character class"
            model: root.classes
            labelFor: function (c) { return c ? c.label : "" }

            onSelected: (index) => root._onClassPicked(index)
        }

        DropDownControl {
            visible: root.hasBuild
            id: ascendDrop

            Layout.preferredWidth: 120
            Layout.preferredHeight: theme.controlSize
            controlEnabled: root.hasBuild && root.ascendancies.length > 0
            placeholder: "Ascendancy"
            tooltipText: "Ascendancy class"
            model: root.ascendancies
            labelFor: function (a) { return a ? a.label : "" }

            onSelected: (index) => {
                var item = root.ascendancies[index]
                if (!item) return
                luaEngine.setAscendClass(item.ascendClassId)
                root.refresh()
            }
        }

        DropDownControl {
            visible: root.hasBuild
            id: secondaryDrop

            Layout.preferredWidth: 150
            Layout.preferredHeight: theme.controlSize
            controlEnabled: root.hasBuild && root.classList.secondaryEnabled === true
            placeholder: "Alt. Ascendancy"
            tooltipText: "Secondary (alternate) ascendancy"
            model: root.secondaries
            labelFor: function (a) { return a ? a.label : "" }

            onSelected: (index) => {
                var item = root.secondaries[index]
                if (!item) return
                luaEngine.setSecondaryAscendClass(item.ascendClassId)
                root.refresh()
            }
        }

        Text {
            text: "Mode: " + luaEngine.currentMode
            color: theme.accent
            verticalAlignment: Text.AlignVCenter
            font.family: theme.fontVar
            font.bold: true
            font.pixelSize: theme.fontSize
        }
    }

    // --- class-change confirm -------------------------------------------------

    // PopupBase centres itself in `parent`; left at the default (this 32px
    // strip) the dialog would hang off the top of the window, so it is
    // reparented onto the window's content item.
    ConfirmPopup {
        id: classConfirm

        parent: root._win ? root._win.contentItem : null
        title: "Class Change"
        confirmLabel: "Continue"
        extraLabel: "Connect Path"

        onAccepted: root._applyClass("force")
        // ConfirmPopup's extra button only reports the click; closing is ours.
        onExtraClicked: { classConfirm.close(); root._applyClass("connect") }
        onRejected: { root._pendingClassId = -1; root._syncControls() }
    }

    // --- engine wiring ---------------------------------------------------------

    Component.onCompleted: root.refresh()

    Connections {
        target: luaEngine
        function onBuildDataChanged() { root.refresh() }
        function onCalcsChanged() { root.refresh() }
        function onModeChanged() { root.refresh() }
        // Allocating/deallocating passives moves the point counters, which are
        // the whole content of pointDisplay — the _refreshing latch keeps the
        // recalc that getShellState() runs from looping back through here.
        function onTreeChanged() { root.refresh() }
    }
}
