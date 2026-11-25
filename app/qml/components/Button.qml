import QtQuick
import QtQuick.Window

// Button — Tier 1, ported from legacy ButtonControl.lua (~250 call sites):
// label OR image OR a +/-/x glyph shorthand, locked/hover/pressed states,
// onHover, and hover-tooltip integration mirroring the TooltipHost contract
// (`tooltipFunc(tooltip)` for custom multi-line content, else a plain
// `tooltipText` single line — see TooltipHost.lua:DrawTooltip). Built on
// Chrome, NOT literal legacy bevel greys (Tier 0 "Cyber Citrus" decision).
//
// Deviations from the immediate-mode original (documented, not gaps):
//   - `onHover` fires once per hover-enter, not every Draw frame (legacy's
//     polled `self.onHover()` per-frame has no retained-mode equivalent;
//     callers that need continuous polling should use `hovered` directly).
//   - The tooltip is a child Item positioned in the button's own local
//     coordinate space (see `_showTooltip`) rather than a window-global
//     overlay layer — correct as long as no ancestor clips (true for now;
//     a future ListControl row embedding this may need to reparent the
//     tooltip to an overlay, same caveat as DragSource).
Item {
    id: root
    objectName: "pob.button.root"

    property string label: ""
    property url imageSource: ""
    property bool locked: false
    property bool controlEnabled: true
    property bool noTooltip: false
    property bool forceTooltip: false
    property string tooltipText: ""
    property var tooltipFunc: null     // function(tooltip) { tooltip.addLine(...) }
    property var onHover: null         // function() {}
    property int fontSize: 0           // 0 = auto (capped at theme.fontSize)
    property int horizontalPadding: 10

    readonly property bool hovered: ma.containsMouse
    readonly property bool pressedLook: ma.pressed && ma.containsMouse
    readonly property bool isGlyph: label === "+" || label === "-" || label === "x"
    readonly property int _labelSize: fontSize > 0
        ? fontSize
        : Math.max(8, Math.min(theme.fontSize, (root.height > 0 ? root.height : root.implicitHeight) - 4))
    readonly property bool _hasTextLabel: root.label.length > 0 && !root.isGlyph && !img.visible

    signal clicked()

    implicitWidth: _hasTextLabel
        ? Math.max(24, Math.ceil(labelText.implicitWidth) + root.horizontalPadding * 2)
        : 80
    implicitHeight: 24

    Chrome {
        objectName: "pob.button.chrome"
        anchors.fill: parent
        hovered: root.hovered
        pressed: root.pressedLook
        locked: root.locked
        controlEnabled: root.controlEnabled
    }

    Image {
        id: img
        objectName: "pob.button.image"
        visible: root.imageSource.toString().length > 0
        anchors.fill: parent
        anchors.margins: 2
        source: root.imageSource
        opacity: root.controlEnabled ? 1.0 : 0.33
        fillMode: Image.PreserveAspectFit
    }

    // +/-/x glyph shorthand — geometry mirrors ButtonClass:Draw's DrawImage/
    // DrawImageQuad fractional coordinates exactly.
    Canvas {
        id: glyph
        objectName: "pob.button.glyph"
        visible: root.isGlyph
        anchors.fill: parent

        // Disabled glyphs use theme.muted, not theme.background: the disabled
        // Chrome fill (#141822) and theme.background (#0F172A) are nearly
        // identical dark navies, so background-on-disabled-fill is unreadable
        // (found via a real BottomBar screenshot — Part 1.3's original
        // contrast rule mis-assumed theme.disabled was a lighter grey).
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
            }
        }
    }

    ColorText {
        id: labelText
        objectName: "pob.button.text"
        visible: root._hasTextLabel
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 3
        anchors.rightMargin: 3
        sourceText: root.label
        font.pixelSize: root._labelSize
        defaultColor: root.controlEnabled ? theme.text : theme.muted
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }

    MouseArea {
        id: ma
        objectName: "pob.button.ma"
        anchors.fill: parent
        hoverEnabled: true
        // Always enabled so hover (and thus a disabled-explains-why tooltip)
        // still works when controlEnabled is false; the click itself is
        // gated below. Chrome's own controlEnabled coloring is unaffected —
        // it ignores hover state while disabled (see Chrome.qml).
        onClicked: if (root.controlEnabled) root.clicked()
    }

    Tooltip {
        id: tt
        objectName: "pob.button.tt"
    }

    function _showTooltip() {
        // A disabled button can still show a tooltip (e.g. explaining why it's
        // disabled) — only click is gated by controlEnabled, not hover/tooltip.
        if (!root.hovered) { tt.hide(); return; }
        if (!root.noTooltip || root.forceTooltip) {
            tt.clear();
            if (root.tooltipFunc) root.tooltipFunc(tt);
            else if (root.tooltipText) tt.addLine(14, root.tooltipText);
            else if (labelText.visible && labelText.truncated) tt.addLine(14, root.label);
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
