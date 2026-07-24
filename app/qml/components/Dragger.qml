import QtQuick
import QtQuick.Window

// Dragger — Tier 1, ported from legacy DraggerControl.lua: visually a Button
// (chrome + +/-/x/"//" glyph shorthand, same TooltipHost + onHover contract)
// that instead of firing a click, reports drag-start/drag-end EDGE events —
// legacy's OnKeyDown fires once on press with the absolute press position,
// OnKeyUp fires once on release with the press->release delta. CONTINUOUS
// position sampling during the drag is the consumer's own job (legacy
// consumers poll GetCursorPos() each Draw() while `dragger.dragging` is
// true — see ResizableEditControl.lua's SetBoundedDrag). `dragging` is
// exposed for exactly that polling pattern; `onDragStart`/`onDragEnd`/
// `onRightClick` are JS-function properties mirroring the legacy
// onKeyDown/onKeyUp/onRightClick constructor params. Unlike Button's
// `locked` (purely visual there), Dragger's `locked` also disables input —
// matching DraggerClass:OnKeyDown/OnKeyUp's explicit `GetProperty("locked")`
// bail-out.
Item {
    id: root

    property string label: ""
    property url imageSource: ""
    property bool locked: false
    property bool controlEnabled: true
    property bool noTooltip: false
    property bool forceTooltip: false
    property string tooltipText: ""
    property var tooltipFunc: null   // function(tooltip) {...}
    property var onHover: null       // function() {}

    property var onDragStart: null   // function(x, y) {} — press, absolute scene position
    property var onDragEnd: null     // function(dx, dy) {} — release, (pressX-releaseX, pressY-releaseY)
    property var onRightClick: null  // function(x, y) {}

    readonly property bool hovered: ma.containsMouse
    readonly property bool dragging: ma.pressed
    readonly property bool isGlyph: label === "+" || label === "-" || label === "x" || label === "//"

    implicitWidth: 24
    implicitHeight: 24

    Chrome {
        anchors.fill: parent
        hovered: root.hovered
        pressed: ma.pressed && ma.containsMouse
        locked: root.locked || root.dragging
        controlEnabled: root.controlEnabled
    }

    Image {
        id: img
        visible: root.imageSource.toString().length > 0
        anchors.fill: parent
        anchors.margins: 2
        source: root.imageSource
        opacity: root.controlEnabled ? 1.0 : 0.33
        fillMode: Image.PreserveAspectFit
    }

    // +/-/x/"//" glyph shorthand — geometry mirrors DraggerClass:Draw's
    // DrawImage/DrawImageQuad fractional coordinates exactly.
    Canvas {
        id: glyph
        visible: root.isGlyph
        anchors.fill: parent

        // theme.muted, not theme.background — see Button.qml's glyphColor
        // comment (disabled fill and theme.background are nearly identical
        // dark navies; unreadable together).
        property color glyphColor: root.controlEnabled ? theme.text : theme.muted

        onGlyphColorChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = glyphColor
            var w = width, h = height
            if (root.label === "+") {
                ctx.fillRect(w * 0.2, h * 0.45, w * 0.6, h * 0.1)
                ctx.fillRect(w * 0.45, h * 0.2, w * 0.1, h * 0.6)
            } else if (root.label === "-") {
                ctx.fillRect(w * 0.2, h * 0.45, w * 0.6, h * 0.1)
            } else if (root.label === "x") {
                ctx.beginPath()
                ctx.moveTo(w * 0.2, h * 0.3); ctx.lineTo(w * 0.3, h * 0.2)
                ctx.lineTo(w * 0.8, h * 0.7); ctx.lineTo(w * 0.7, h * 0.8)
                ctx.closePath(); ctx.fill()
                ctx.beginPath()
                ctx.moveTo(w * 0.7, h * 0.2); ctx.lineTo(w * 0.8, h * 0.3)
                ctx.lineTo(w * 0.3, h * 0.8); ctx.lineTo(w * 0.2, h * 0.7)
                ctx.closePath(); ctx.fill()
            } else if (root.label === "//") {
                ctx.beginPath()
                ctx.moveTo(w * 0.75, h * 0.15); ctx.lineTo(w * 0.85, h * 0.25)
                ctx.lineTo(w * 0.25, h * 0.85); ctx.lineTo(w * 0.15, h * 0.75)
                ctx.closePath(); ctx.fill()
                ctx.beginPath()
                ctx.moveTo(w * 0.75, h * 0.5); ctx.lineTo(w * 0.85, h * 0.6)
                ctx.lineTo(w * 0.6, h * 0.85); ctx.lineTo(w * 0.5, h * 0.75)
                ctx.closePath(); ctx.fill()
            }
        }
    }

    Label {
        visible: root.label.length > 0 && !root.isGlyph && !img.visible
        anchors.centerIn: parent
        label: root.label
        size: Math.max(8, root.height - 4)
        defaultColor: root.controlEnabled ? theme.text : theme.muted
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.controlEnabled && !root.locked
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        property point pressScenePos

        onPressed: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                pressScenePos = root.mapToItem(null, mouse.x, mouse.y);
                if (root.onDragStart) root.onDragStart(pressScenePos.x, pressScenePos.y);
            }
        }
        onReleased: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                var releaseScenePos = root.mapToItem(null, mouse.x, mouse.y);
                if (root.onDragEnd) root.onDragEnd(pressScenePos.x - releaseScenePos.x, pressScenePos.y - releaseScenePos.y);
            }
        }
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton && root.onRightClick) {
                var p = root.mapToItem(null, mouse.x, mouse.y);
                root.onRightClick(p.x, p.y);
            }
        }
    }

    Tooltip {
        id: tt
    }

    function _showTooltip() {
        if (!root.hovered) { tt.hide(); return; }
        if (!root.noTooltip || root.forceTooltip) {
            tt.clear();
            if (root.tooltipFunc) root.tooltipFunc(tt);
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

    onHoveredChanged: {
        _showTooltip();
        if (hovered && root.onHover) root.onHover();
    }
    onNoTooltipChanged: _showTooltip()
    onTooltipTextChanged: _showTooltip()
}
