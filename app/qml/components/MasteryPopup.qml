import QtQuick
import QtQuick.Layouts
import QtQuick.Window

// MasteryPopup — Phase 4 Part 4.4, ports TreeTab:OpenMasteryPopup
// (TreeTab.lua:1038-1063) + PassiveMasteryControl. One row per effect not
// already taken by another mastery ("stat / stat"); hovering a row shows the
// node's full tooltip AS IF that effect were chosen (stat diff included,
// PassiveMasteryControl:AddValueTooltip); clicking a row selects it and
// allocates the node (TreeTab:SaveMasteryPopup). Cancel leaves it untouched.
PopupBase {
    id: root

    property int nodeId: -1
    property var tracePath: []
    property var effects: []
    // PassiveMasteryControl's "automagical width": the widest label + 5.
    property real listWidth: 300
    signal selectedEffect()

    padding: 8

    function openFor(id, trace) {
        const m = luaEngine.invoke("pob_getMasteryEffects", [id])
        if (!m || !m.effects || m.effects.length === undefined || m.effects.length === 0) return false
        nodeId = id
        tracePath = trace || []
        effects = m.effects
        let w = 0
        for (let i = 0; i < effects.length; i++) w = Math.max(w, textMetrics.width(16, "VAR", effects[i].label) + 5)
        listWidth = w + 12
        title = m.name
        open()
        return true
    }

    function _showPreview(index, rowItem) {
        const t = luaEngine.invoke("pob_previewMasteryEffect", [nodeId, effects[index].id, tracePath])
        tip.clear()
        tip.maxWidth = 800
        if (t && t.lines) {
            for (let i = 0; i < t.lines.length; i++) {
                const l = t.lines[i]
                if (l.sep) { tip.addSeparator(l.size); continue }
                tip.center = !!l.center
                tip.addLine(l.size, l.text.length > 0 ? l.text : " ")
            }
        }
        const host = root.contentItem.parent
        tip.parent = host
        const p = rowItem.mapToItem(host, 0, 0)
        const win = rowItem.Window.window
        const o = host.mapFromItem(null, 0, 0)
        tip.showAt(p.x, p.y, rowItem.width, rowItem.height,
                   Qt.rect(o.x, o.y, win ? win.width : host.width, win ? win.height : host.height))
    }

    onClosed: tip.hide()

    ColumnLayout {
        spacing: 6

        Rectangle {
            Layout.preferredWidth: root.listWidth
            Layout.preferredHeight: root.effects.length * 16 + 4
            color: "transparent"
            border.color: theme.border
            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: 2
                interactive: false
                model: root.effects
                delegate: Rectangle {
                    id: row
                    width: list.width
                    height: 16
                    color: rowMa.containsMouse ? theme.hover : (modelData.selected ? theme.active : "transparent")
                    Label {
                        id: rowLabel
                        x: 4
                        anchors.verticalCenter: parent.verticalCenter
                        label: modelData.label
                        size: 14
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onContainsMouseChanged: {
                            if (containsMouse) root._showPreview(index, row)
                            else tip.hide()
                        }
                        onClicked: {
                            luaEngine.invoke("pob_selectMasteryEffect", [root.nodeId, modelData.id, root.tracePath])
                            root.selectedEffect()
                            root.close()
                        }
                    }
                }
            }
        }
        Button {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 90; implicitHeight: 20
            label: "Cancel"
            onClicked: root.reject()
        }
    }

    // Parented to the popup's own visual item when shown, so it draws above
    // the modal dimming (a child of the window's content item is drawn UNDER
    // it); held as a property so it takes no part in the content layout.
    property Tooltip tip: Tooltip { z: 1000 }
}
