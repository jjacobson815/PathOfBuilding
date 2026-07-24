import QtQuick

// ScrollBar — Tier 2, ported from legacy ScrollBarControl.lua (323 lines):
// up/down step buttons, a draggable knob sized to the content/view ratio,
// click-track page-jump (SLIDEUP/SLIDEDOWN), hold-to-repeat with the exact
// legacy timing (500ms initial delay, then a 50ms-interval repeat),
// `scrollIntoView`, `autoHide` (hidden entirely when content already fits —
// legacy ties this to the SAME flag Draw uses to grey out the bar), and a
// `dir` (VERTICAL/HORIZONTAL) axis switch.
//
// Deviations (documented, not gaps): legacy's hold-repeat "pauses" while the
// cursor drifts off the held button and resumes on return (`holdPauseTime`);
// here a Qt MouseArea press-grab means the repeat just keeps running
// regardless of cursor position until release — simpler, functionally
// equivalent for the common case. Region hit-testing (`IsMouseOver`'s
// UP/DOWN/KNOB/SLIDEUP/SLIDEDOWN zones) is realized as real child Items with
// their own MouseAreas rather than manual coordinate math.
Item {
    id: root

    property string dir: "VERTICAL"       // "VERTICAL" | "HORIZONTAL"
    property real step: 40
    property bool autoHide: false
    property bool controlEnabled: true

    property real contentDim: 0           // conDim
    property real viewDim: 0
    property real offset: 0
    // Computed, not imperatively set — legacy recomputes offsetMax any time
    // SetContentDimension runs; making it a binding lets callers just bind
    // contentDim/viewDim declaratively (e.g. to a reactive content height)
    // instead of having to call setContentDimension() on every change.
    readonly property real offsetMax: Math.max(0, contentDim - viewDim)

    readonly property bool horizontal: dir === "HORIZONTAL"
    readonly property bool active: contentDim > viewDim
    readonly property real shortDim: horizontal ? height : width
    readonly property real longDim: horizontal ? width : height
    readonly property real knobDim: active ? Math.max(shortDim, (longDim - shortDim * 2) * viewDim / Math.max(1, contentDim)) : shortDim
    readonly property real knobTravel: active ? Math.max(0, (longDim - shortDim * 2) - knobDim) : 0

    visible: !autoHide || active
    implicitWidth: horizontal ? 160 : 18
    implicitHeight: horizontal ? 18 : 160

    onOffsetMaxChanged: if (offset > offsetMax) offset = offsetMax

    // Convenience imperative setter mirroring the legacy call site
    // (`scrollBar:SetContentDimension(conDim, viewDim)`) — equivalent to
    // binding contentDim/viewDim directly.
    function setContentDimension(conDim, vDim) {
        contentDim = conDim;
        viewDim = vDim;
    }
    function setOffset(o) {
        offset = Math.floor(Math.max(0, Math.min(offsetMax, o)));
    }
    function scroll(mult) {
        setOffset(offset + step * mult);
    }
    function scrollIntoView(minDim, size) {
        if (offset > minDim) setOffset(minDim);
        else if (offset + viewDim < minDim + size) setOffset(minDim + size - viewDim);
    }
    function setOffsetFromKnobPos(knobPos) {
        if (knobTravel <= 0) return;
        setOffset(offsetMax * (knobPos / knobTravel));
    }
    function knobPosForOffset() {
        return offsetMax > 0 ? knobTravel * (offset / offsetMax) : 0;
    }
    // Centralized input mapping, mirrors legacy IsScrollDownKey/IsScrollUpKey.
    function handleWheel(angleDeltaY) {
        if (angleDeltaY < 0) scroll(1); else if (angleDeltaY > 0) scroll(-1);
    }

    Chrome {
        anchors.fill: parent
        controlEnabled: root.controlEnabled && root.active
    }

    // --- Up/Left step button ------------------------------------------------
    Rectangle {
        id: upBtn
        x: 0; y: 0
        width: root.horizontal ? root.shortDim : root.width
        height: root.horizontal ? root.height : root.shortDim
        color: upMa.pressed && upMa.containsMouse ? theme.active : upMa.containsMouse ? theme.hover : "transparent"
        border.width: 1
        border.color: theme.border
        Arrow {
            anchors.fill: parent
            anchors.margins: 2
            direction: root.horizontal ? "left" : "up"
            glyphColor: root.active ? theme.text : theme.muted
        }
        MouseArea {
            id: upMa
            anchors.fill: parent
            enabled: root.controlEnabled && root.active
            onPressed: { root.scroll(-1); holdDelay.dir = -1; holdDelay.restart(); }
            onReleased: { holdDelay.stop(); holdRepeat.stop(); }
            onCanceled: { holdDelay.stop(); holdRepeat.stop(); }
        }
    }

    // --- Down/Right step button ---------------------------------------------
    Rectangle {
        id: downBtn
        x: root.horizontal ? root.width - root.shortDim : 0
        y: root.horizontal ? 0 : root.height - root.shortDim
        width: root.horizontal ? root.shortDim : root.width
        height: root.horizontal ? root.height : root.shortDim
        color: downMa.pressed && downMa.containsMouse ? theme.active : downMa.containsMouse ? theme.hover : "transparent"
        border.width: 1
        border.color: theme.border
        Arrow {
            anchors.fill: parent
            anchors.margins: 2
            direction: root.horizontal ? "right" : "down"
            glyphColor: root.active ? theme.text : theme.muted
        }
        MouseArea {
            id: downMa
            anchors.fill: parent
            enabled: root.controlEnabled && root.active
            onPressed: { root.scroll(1); holdDelay.dir = 1; holdDelay.restart(); }
            onReleased: { holdDelay.stop(); holdRepeat.stop(); }
            onCanceled: { holdDelay.stop(); holdRepeat.stop(); }
        }
    }

    // 500ms initial delay, then a 50ms-interval repeat — legacy's exact timing.
    Timer {
        id: holdDelay
        property int dir: 0
        interval: 500; repeat: false
        onTriggered: holdRepeat.start()
    }
    Timer {
        id: holdRepeat
        interval: 50; repeat: true
        onTriggered: root.scroll(holdDelay.dir)
    }

    // --- Track + knob --------------------------------------------------------
    Item {
        id: track
        x: root.horizontal ? root.shortDim : 0
        y: root.horizontal ? 0 : root.shortDim
        width: root.horizontal ? root.longDim - root.shortDim * 2 : root.width
        height: root.horizontal ? root.height : root.longDim - root.shortDim * 2

        MouseArea {
            id: trackMa
            anchors.fill: parent
            enabled: root.controlEnabled && root.active
            onPressed: (mouse) => {
                var pos = root.horizontal ? mouse.x : mouse.y;
                var knobPos = root.knobPosForOffset();
                if (pos < knobPos) root.setOffsetFromKnobPos(knobPos - root.knobDim);
                else if (pos >= knobPos + root.knobDim) root.setOffsetFromKnobPos(knobPos + root.knobDim);
            }
        }

        Rectangle {
            id: knob
            x: root.horizontal ? root.knobPosForOffset() : 0
            y: root.horizontal ? 0 : root.knobPosForOffset()
            width: root.horizontal ? root.knobDim : track.width
            height: root.horizontal ? track.height : root.knobDim
            visible: root.active
            radius: theme.radiusControl
            color: knobMa.pressed ? theme.text : knobMa.containsMouse ? theme.borderStrong : theme.muted

            MouseArea {
                id: knobMa
                anchors.fill: parent
                enabled: root.controlEnabled && root.active
                hoverEnabled: true

                property real pressCoord: 0
                property real pressKnobPos: 0

                onPressed: (mouse) => {
                    var p = knobMa.mapToItem(track, mouse.x, mouse.y);
                    pressCoord = root.horizontal ? p.x : p.y;
                    pressKnobPos = root.knobPosForOffset();
                }
                onPositionChanged: (mouse) => {
                    if (pressed) {
                        var p = knobMa.mapToItem(track, mouse.x, mouse.y);
                        var cur = root.horizontal ? p.x : p.y;
                        root.setOffsetFromKnobPos((cur - pressCoord) + pressKnobPos);
                    }
                }
            }
        }
    }
}
