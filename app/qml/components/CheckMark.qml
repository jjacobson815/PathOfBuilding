import QtQuick

// CheckMark — the checkbox tick glyph. Geometry mirrors legacy
// `main:DrawCheckMark` (Modules/Main.lua:1456) — two filled quads (a short
// down-left stroke + a long up-right stroke) inside a square box, re-based
// here from center+size to a top-left (x,y)+size box (same fractional
// coordinates, so the shape is identical). Fills the item's own bounding
// box, using the smaller of width/height as the square side.
Canvas {
    id: root

    property color glyphColor: theme.text

    onGlyphColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var size = Math.min(width, height)
        var x = (width - size) / 2
        var y = (height - size) / 2
        ctx.fillStyle = glyphColor
        ctx.beginPath()
        ctx.moveTo(x + size * 0.15, y + size * 0.50)
        ctx.lineTo(x + size * 0.30, y + size * 0.45)
        ctx.lineTo(x + size * 0.50, y + size * 0.80)
        ctx.lineTo(x + size * 0.40, y + size * 0.90)
        ctx.closePath()
        ctx.fill()
        ctx.beginPath()
        ctx.moveTo(x + size * 0.40, y + size * 0.90)
        ctx.lineTo(x + size * 0.35, y + size * 0.75)
        ctx.lineTo(x + size * 0.80, y + size * 0.10)
        ctx.lineTo(x + size * 0.90, y + size * 0.20)
        ctx.closePath()
        ctx.fill()
    }
}
