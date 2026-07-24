import QtQuick

// Arrow — directional triangle glyph (DropDown expand indicator, ScrollBar
// step buttons, PathControl breadcrumb chevrons, ...). Geometry mirrors
// legacy `main:DrawArrow` (Modules/Main.lua:1438) — an isoceles triangle
// spanning the item's full width/height, apex pointing `direction`.
Canvas {
    id: root

    property string direction: "down" // "up" | "down" | "left" | "right"
    property color glyphColor: theme.text

    onDirectionChanged: requestPaint()
    onGlyphColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.fillStyle = glyphColor
        var x1 = 0, x2 = width, xMid = width / 2
        var y1 = 0, y2 = height, yMid = height / 2
        ctx.beginPath()
        if (direction === "up") {
            ctx.moveTo(xMid, y1); ctx.lineTo(x2, y2); ctx.lineTo(x1, y2)
        } else if (direction === "left") {
            ctx.moveTo(x2, y1); ctx.lineTo(x2, y2); ctx.lineTo(x1, yMid)
        } else if (direction === "right") {
            ctx.moveTo(x1, y1); ctx.lineTo(x1, y2); ctx.lineTo(x2, yMid)
        } else { // "down" (default)
            ctx.moveTo(x1, y1); ctx.lineTo(x2, y1); ctx.lineTo(xMid, y2)
        }
        ctx.closePath()
        ctx.fill()
    }
}
