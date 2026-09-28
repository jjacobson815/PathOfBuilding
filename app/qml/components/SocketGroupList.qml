import QtQuick
import QtQuick.Window

// SocketGroupList — Phase 5 Part 5.1, ports SkillListControl.lua (a
// ListControl, rows 16px, header "^7Socket Groups:", New / Delete All /
// Delete buttons above the right edge).
//
// Row text is the bridge's legacy GetRowValue string (grey "(Disabled)",
// RELIC "(Active)" / "(Forced Active)", CUSTOM "(FullDPS)", R-G-B-W link
// colours); the icon is the lifted GetRowIcon slot icon (16x16, text at +18).
//
// Mouse (SkillListControl:OnHoverKeyUp 203-225): click selects, Ctrl+click
// enables/disables, right-click sets the main group, Ctrl+right-click
// includes/excludes it from FullDPS. Drag a row to reorder (ListControl
// drag: insertion index, then OnOrderChange). Keys while focused: Up/Down/
// Home/End move the selection, Ctrl+C copies the selected group,
// Delete/Backspace deletes it. Hover shows AddSocketGroupTooltip.
//
// Deletions that need a question go out as signals; the view owns the popups.
FocusScope {
    id: root

    property var groups: []
    property int selIndex: -1                      // 0-based; the detail group
    readonly property int count: groups && groups.length !== undefined ? groups.length : 0
    readonly property bool hasSel: selIndex >= 0 && selIndex < count
    readonly property int rowHeight: 16

    signal deleteRequested(int index)              // 0-based; group has gems
    signal deleteAllRequested()
    signal messageRequested(string title, string text)

    implicitWidth: 360
    implicitHeight: 320
    z: tip.visible ? 50 : 0

    function _call(name, args) { return luaEngine.invoke(name, args || []) }

    function select(i) {
        if (i < 0 || i >= count) return
        _call("pob_skillsSelectGroup", [i + 1])
        list.positionViewAtIndex(i, ListView.Contain)
    }

    // SkillListControl:OnSelDelete — no question for an empty group, a
    // message for an item-provided one.
    function deleteAt(i) {
        if (i < 0 || i >= count) return
        const g = groups[i]
        if (g.source) {
            messageRequested("Delete Socket Group", "This socket group cannot be deleted as it is created by an equipped item.")
        } else if (!g.hasGems) {
            _call("pob_skillsDeleteGroup", [i + 1])
        } else {
            deleteRequested(i)
        }
    }

    Keys.onPressed: function (event) {
        const ctrl = event.modifiers & Qt.ControlModifier
        if (event.key === Qt.Key_Up && count > 0) {
            select(hasSel ? (selIndex > 0 ? selIndex - 1 : count - 1) : count - 1)
        } else if (event.key === Qt.Key_Down && count > 0) {
            select(hasSel ? (selIndex < count - 1 ? selIndex + 1 : 0) : 0)
        } else if (event.key === Qt.Key_Home && count > 0) {
            select(0)
        } else if (event.key === Qt.Key_End && count > 0) {
            select(count - 1)
        } else if (ctrl && event.key === Qt.Key_C && hasSel) {
            _call("pob_skillsCopyGroup", [selIndex + 1])
        } else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && hasSel) {
            deleteAt(selIndex)
        } else {
            return
        }
        event.accepted = true
    }

    Label {
        x: 0
        y: 2
        label: "^7Socket Groups:"
        size: 16
    }
    Row {
        anchors.right: box.right
        y: 0
        spacing: 4
        Button { width: 60; height: 18; label: "New"
            onClicked: { root._call("pob_skillsNewGroup"); root.forceActiveFocus() } }
        Button { width: 70; height: 18; label: "Delete All"; controlEnabled: root.count > 0
            onClicked: root.deleteAllRequested() }
        Button { width: 60; height: 18; label: "Delete"
            controlEnabled: root.hasSel && !root.groups[root.selIndex].source
            onClicked: root.deleteAt(root.selIndex) }
    }

    Rectangle {
        id: box
        y: 20
        width: root.width
        height: root.height - 20
        color: theme.background
        border.width: 1
        border.color: root.activeFocus ? theme.text : theme.border
        clip: true

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 2
            anchors.rightMargin: sb.visible ? 18 : 2
            model: root.groups
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                width: list.width
                height: root.rowHeight
                color: index === root.selIndex ? theme.active
                     : index === ma.hoverIndex ? theme.hover : "transparent"
                Image {
                    id: icon
                    x: 0
                    width: 16; height: 16
                    visible: modelData.icon !== ""
                    source: modelData.icon !== "" ? "file://" + modelData.icon : ""
                    smooth: true
                }
                Label {
                    x: icon.visible ? 18 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    label: modelData.label
                    size: 14
                }
            }
            onContentYChanged: sb.setOffset(contentY)
        }

        // Drop marker for a drag reorder (ListControl draws a line at the gap).
        Rectangle {
            visible: ma.dragging
            x: 2
            width: list.width
            height: 2
            y: 2 + ma.dropIndex * root.rowHeight - list.contentY - 1
            color: theme.text
        }

        ScrollBar {
            id: sb
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 1
            width: 16
            visible: active
            dir: "VERTICAL"
            contentDim: root.count * root.rowHeight
            viewDim: list.height
            onOffsetChanged: list.contentY = offset
        }

        MouseArea {
            id: ma
            anchors.fill: list
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            property int hoverIndex: -1
            property int pressIndex: -1
            property real pressY: 0
            property bool dragging: false
            property int dropIndex: 0                  // 0-based insertion gap

            function rowAt(y) {
                const i = Math.floor((y + list.contentY) / root.rowHeight)
                return i >= 0 && i < root.count ? i : -1
            }
            onPositionChanged: function (mouse) {
                hoverIndex = rowAt(mouse.y)
                if (pressed && pressIndex >= 0 && (mouse.buttons & Qt.LeftButton)
                        && !(mouse.modifiers & Qt.ControlModifier) && Math.abs(mouse.y - pressY) > 4) {
                    dragging = true
                    dropIndex = Math.max(0, Math.min(root.count,
                        Math.round((mouse.y + list.contentY) / root.rowHeight)))
                }
            }
            onExited: hoverIndex = -1
            onHoverIndexChanged: root._showTip()
            onPressed: function (mouse) {
                root.forceActiveFocus()
                pressIndex = rowAt(mouse.y)
                pressY = mouse.y
                dragging = false
            }
            onReleased: function (mouse) {
                const i = pressIndex
                pressIndex = -1
                if (dragging) {
                    dragging = false
                    // ListControl: t_remove(sel); if drag > sel then drag - 1; t_insert(drag).
                    let to = dropIndex > i ? dropIndex - 1 : dropIndex
                    if (i >= 0 && to !== i) root._call("pob_skillsMoveGroup", [i + 1, to + 1])
                    return
                }
                if (i < 0 || rowAt(mouse.y) !== i) return
                const ctrl = mouse.modifiers & Qt.ControlModifier
                if (mouse.button === Qt.LeftButton) {
                    root.select(i)
                    if (ctrl) root._call("pob_skillsToggleGroupEnabled", [i + 1])
                } else if (ctrl) {
                    root._call("pob_skillsToggleGroupFullDPS", [i + 1])
                } else {
                    root._call("pob_skillsSetMainGroup", [i + 1])
                }
            }
            onWheel: function (wheel) { sb.handleWheel(wheel.angleDelta.y) }
        }
    }

    // SkillListControl:AddValueTooltip -> SkillsTab:AddSocketGroupTooltip.
    function _showTip() {
        const i = ma.hoverIndex
        if (i < 0 || ma.dragging || !groups[i].hasTooltip) { tip.hide(); return }
        const t = _call("pob_skillsGroupTooltip", [i + 1])
        tip.clear()
        if (!t || !t.lines || !t.lines.length) { tip.hide(); return }
        for (let k = 0; k < t.lines.length; k++) {
            const l = t.lines[k]
            if (l.sep) tip.addSeparator(l.size)
            else tip.addLine(l.size, l.text.length > 0 ? l.text : " ")
        }
        const win = Window.window
        const o = win ? root.mapToItem(win.contentItem, 0, 0) : Qt.point(0, 0)
        const rowY = box.y + 2 + i * rowHeight - list.contentY
        tip.showAt(box.x, rowY, box.width, rowHeight,
                   win ? Qt.rect(-o.x, -o.y, win.width, win.height) : Qt.rect(0, 0, width, height))
    }

    onGroupsChanged: if (ma.hoverIndex >= 0) Qt.callLater(_showTip)

    Tooltip { id: tip }
}
