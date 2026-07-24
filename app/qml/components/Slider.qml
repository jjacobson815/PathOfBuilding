import QtQuick
import QtQuick.Window

// Slider — Tier 1, ported from legacy SliderControl.lua: knob drag + click-
// to-jump on the track, SHIFT(0.25)/CTRL(0.01)/default(0.05) wheel + arrow-
// key step speeds, optional `divCount` detents (draws tick marks + a split
// up/down-arrow knob instead of a plain knob, per Draw's `self.divCount`
// branch — also exposes `divVal()`, ported from `GetDivVal`, which
// ItemsTab.lua's cluster-jewel node-count slider consumes), a hover-hint
// tooltip that PREVIEWS the value a click would jump to when not dragging
// (mirrors the `else` branch of Draw's tooltip block — shows the live value
// instead while actually dragging), and an `invertScroll` option (legacy
// `main.invertSliderScrollDirection`).
//
// Focus/keys deviation (Tier 0 input-model decision): legacy's capture-by-
// return focus isn't reproduced; a click grants this Item active focus
// (`forceActiveFocus()`), after which arrow keys step the value — the
// nearest native equivalent, not a literal port.
Item {
    id: root

    property real value: 0            // 0..1, mirrors legacy `val`
    property int divCount: 0          // 0 = continuous; >1 = detent count
    property bool controlEnabled: true
    property bool invertScroll: false
    property var scrollWheelSpeeds: ({ SHIFT: 0.25, CTRL: 0.01, DEFAULT: 0.05 })
    property bool noTooltip: false
    property var tooltipFunc: null    // function(tooltip, previewOrLiveVal) {...}

    readonly property int knobSize: Math.max(1, height - 2)
    readonly property real knobTravelPx: Math.max(1, width - knobSize - 2)
    readonly property bool dragging: ma.pressed
    readonly property bool hovered: ma.containsMouse

    implicitWidth: 160
    implicitHeight: 18

    function _clamp(v) { return Math.max(0, Math.min(1, v)); }
    function setVal(newVal) {
        newVal = _clamp(newVal);
        if (newVal !== root.value) root.value = newVal;
    }
    function knobXForVal(v) {
        return root.knobTravelPx * (v === undefined ? root.value : v);
    }
    function setValFromKnobX(knobX) {
        setVal(knobX / root.knobTravelPx);
    }
    // Mirrors GetDivVal — maps the continuous [0,1] value onto a discrete
    // [1,divCount] index + fractional remainder within that segment.
    function divVal(v) {
        v = v === undefined ? root.value : v;
        if (root.divCount && root.divCount > 1) {
            var divIndex = Math.max(Math.ceil(v * root.divCount), 1);
            return [divIndex, v * root.divCount - divIndex + 1];
        }
        return [1, v];
    }
    function knobHitTest() {
        return ma.containsMouse && Math.abs(ma.mouseX - (2 + root.knobXForVal() + (root.knobSize - 2) / 2)) < (root.knobSize - 2) / 2;
    }

    Chrome {
        anchors.fill: parent
        hovered: root.hovered || root.dragging
        controlEnabled: root.controlEnabled
    }

    // Detent tick marks (legacy: `for d = 0, knobTravel+0.5, knobTravel/divCount`).
    Item {
        visible: root.controlEnabled && root.divCount > 1
        x: root.knobSize / 2 + 1
        y: 1
        width: root.knobTravelPx
        height: root.height - 2

        Repeater {
            model: root.divCount > 1 ? root.divCount + 1 : 0
            delegate: Rectangle {
                required property int index
                x: (root.knobTravelPx / Math.max(1, root.divCount)) * index - 1
                width: 2
                height: root.height - 2
                color: theme.border
            }
        }
    }

    // Knob: a plain filled rect for a continuous slider, or a split up/down
    // arrow pair for a detent slider (mirrors legacy's two DrawArrow calls).
    Rectangle {
        visible: root.controlEnabled && root.divCount <= 1
        x: 2 + root.knobXForVal()
        y: 2
        width: root.knobSize - 2
        height: root.knobSize - 2
        color: (root.dragging || root.knobHitTest()) ? theme.text : theme.muted
    }
    Column {
        visible: root.controlEnabled && root.divCount > 1
        x: 1 + root.knobXForVal()
        y: root.height / 2 - root.knobSize / 2
        width: root.knobSize
        height: root.knobSize
        Arrow {
            direction: "up"
            width: root.knobSize
            height: root.knobSize / 2
            glyphColor: (root.dragging || root.knobHitTest()) ? theme.text : theme.muted
        }
        Arrow {
            direction: "down"
            width: root.knobSize
            height: root.knobSize / 2
            glyphColor: (root.dragging || root.knobHitTest()) ? theme.text : theme.muted
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.controlEnabled
        acceptedButtons: Qt.LeftButton

        property real dragCX: 0
        property real dragKnobX: 0

        onPressed: (mouse) => {
            root.forceActiveFocus();
            var overKnob = root.knobHitTest();
            dragCX = mouse.x;
            if (!overKnob) {
                root.setValFromKnobX(mouse.x - 1 - root.knobSize / 2);
            }
            dragKnobX = root.knobXForVal();
        }
        onPositionChanged: (mouse) => {
            if (pressed) root.setValFromKnobX((mouse.x - dragCX) + dragKnobX);
            root._updateTooltip();
        }
        onReleased: (mouse) => {
            root.setValFromKnobX((mouse.x - dragCX) + dragKnobX);
        }
        onWheel: (wheel) => {
            var up = wheel.angleDelta.y > 0;
            if (root.invertScroll) up = !up;
            var step = (wheel.modifiers & Qt.ShiftModifier) ? root.scrollWheelSpeeds.SHIFT
                     : (wheel.modifiers & Qt.ControlModifier) ? root.scrollWheelSpeeds.CTRL
                     : root.scrollWheelSpeeds.DEFAULT;
            root.setVal(root.value + (up ? step : -step));
        }
        onContainsMouseChanged: root._updateTooltip()
    }

    Keys.onLeftPressed: (event) => root._stepKey(false, event.modifiers)
    Keys.onDownPressed: (event) => root._stepKey(false, event.modifiers)
    Keys.onRightPressed: (event) => root._stepKey(true, event.modifiers)
    Keys.onUpPressed: (event) => root._stepKey(true, event.modifiers)

    function _stepKey(up, modifiers) {
        if (root.invertScroll) up = !up;
        var step = (modifiers & Qt.ShiftModifier) ? root.scrollWheelSpeeds.SHIFT
                 : (modifiers & Qt.ControlModifier) ? root.scrollWheelSpeeds.CTRL
                 : root.scrollWheelSpeeds.DEFAULT;
        root.setVal(root.value + (up ? step : -step));
    }

    Tooltip { id: tt }

    function _updateTooltip() {
        if ((!root.hovered && !root.dragging) || root.noTooltip || !root.tooltipFunc) { tt.hide(); return; }
        var previewVal = root.dragging ? root.value
            : root._clamp((ma.mouseX - 1 - root.knobSize / 2) / root.knobTravelPx);
        tt.clear();
        root.tooltipFunc(tt, previewVal);
        if (tt.lines.length === 0) { tt.hide(); return; }
        var win = Window.window;
        var origin = win ? root.mapToItem(win.contentItem, 0, 0) : Qt.point(0, 0);
        var viewport = win ? Qt.rect(-origin.x, -origin.y, win.width, win.height)
                            : Qt.rect(0, 0, root.width, root.height);
        tt.showAt(0, 0, root.width, root.height, viewport);
    }

    onDraggingChanged: _updateTooltip()
}
