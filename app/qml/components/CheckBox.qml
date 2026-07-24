import QtQuick
import QtQuick.Window

// CheckBox — Tier 1, ported from legacy CheckBoxControl.lua: a square box
// with a CheckMark glyph when checked, a label to the LEFT living inside the
// same hit area (legacy IsMouseOver extends the hit-test left by
// labelWidth), an optional `borderFunc` border-color override (e.g. a
// per-row zebra/warn tint), and a state-aware tooltip (`tooltipFunc`
// receives the CURRENT state, mirroring `DrawTooltip(..., self.state)`).
Item {
    id: root

    property string label: ""
    property bool state: false
    property bool controlEnabled: true
    property var borderFunc: null       // function(): [r,g,b] 0..1, border override when enabled+unhovered
    property bool noTooltip: false
    property string tooltipText: ""
    property var tooltipFunc: null      // function(tooltip, state) {...}

    readonly property bool hovered: ma.containsMouse
    readonly property int boxSize: height
    readonly property real labelWidth: root.label.length > 0
        ? textMetrics.width(Math.max(1, root.boxSize - 4), "VAR", root.label) + 5 : 0

    signal toggled(bool newState)

    implicitWidth: 18
    implicitHeight: 18

    readonly property color _borderColor:
        !root.controlEnabled ? theme.border
        : root.hovered ? theme.borderStrong
        : root.borderFunc ? Qt.rgba(root.borderFunc()[0], root.borderFunc()[1], root.borderFunc()[2], 1)
        : theme.border

    Chrome {
        id: chrome
        anchors.fill: parent
        hovered: root.hovered
        pressed: ma.pressed && ma.containsMouse
        controlEnabled: root.controlEnabled
        border.color: root._borderColor
    }

    CheckMark {
        visible: root.state
        anchors.fill: parent
        anchors.margins: root.boxSize * 0.1
        glyphColor: !root.controlEnabled ? theme.background : root.hovered ? theme.text : theme.muted
    }

    Label {
        id: labelText
        visible: root.label.length > 0
        anchors.right: parent.left
        anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        label: root.label
        size: Math.max(1, root.boxSize - 4)
        // Unlike the box's own CheckMark glyph (drawn ON the disabled Chrome
        // fill, where theme.background contrasts), this label sits on the
        // ordinary page background — theme.muted reads correctly there.
        defaultColor: root.controlEnabled ? theme.text : theme.muted
    }

    // Hit area covers the box PLUS the label to its left (legacy IsMouseOver).
    MouseArea {
        id: ma
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.width + root.labelWidth
        hoverEnabled: true
        enabled: root.controlEnabled
        onClicked: {
            root.state = !root.state;
            root.toggled(root.state);
        }
    }

    Tooltip {
        id: tt
    }

    function _showTooltip() {
        if (!root.hovered || !root.controlEnabled) { tt.hide(); return; }
        if (!root.noTooltip) {
            tt.clear();
            if (root.tooltipFunc) root.tooltipFunc(tt, root.state);
            else if (root.tooltipText) tt.addLine(14, root.tooltipText);
            if (tt.lines.length > 0) {
                var win = Window.window;
                var origin = win ? root.mapToItem(win.contentItem, 0, 0) : Qt.point(0, 0);
                var viewport = win ? Qt.rect(-origin.x, -origin.y, win.width, win.height)
                                    : Qt.rect(0, 0, root.width, root.height);
                tt.showAt(0, 0, root.width, root.height, viewport);
                return;
            }
        }
        tt.hide();
    }

    onHoveredChanged: _showTooltip()
    onStateChanged: if (hovered) _showTooltip()
    onNoTooltipChanged: _showTooltip()
    onTooltipTextChanged: _showTooltip()
}
