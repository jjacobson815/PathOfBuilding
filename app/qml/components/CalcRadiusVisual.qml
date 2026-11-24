import QtQuick

// CalcRadiusVisual — Phase 8 Part 8.2.
// Ports CalcBreakdownControl:DrawRadiusVisual (CalcBreakdownControl.lua:665):
// draws Assets/range_guide.png (dimmed 0.75), overlays the game-screen-scaled
// AoE circle polygon computed by main:WorldToScreen in pob_calcs.lua (green
// fill 0.5, 1.0, 0.5, alpha 0.33), then draws Assets/game_ui_small.png on top.
Rectangle {
    id: root

    property real radiusValue: 0
    property string guidePath: ""
    property string overlayPath: ""
    // Flat [x0, y0, x1, y1, ...] in the 480x270 image coordinate space.
    property var polygonPoints: []

    readonly property int imgWidth: 480
    readonly property int imgHeight: 270

    implicitWidth: imgWidth + 4
    implicitHeight: imgHeight + 4
    width: implicitWidth
    height: implicitHeight
    color: "#FFFFFF"

    function _fileUrl(p) {
        if (!p || p.length === 0) return ""
        return (p.charAt(0) === "/" ? "file://" : "file:///") + p
    }

    onPolygonPointsChanged: aoeCanvas.requestPaint()
    onRadiusValueChanged: aoeCanvas.requestPaint()

    Rectangle {
        id: frame
        x: 2
        y: 2
        width: root.imgWidth
        height: root.imgHeight
        color: "#000000"
        clip: true

        Image {
            id: guideImg
            anchors.fill: parent
            source: root._fileUrl(root.guidePath)
            opacity: 0.75
            fillMode: Image.Stretch
            asynchronous: false
        }

        Canvas {
            id: aoeCanvas
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var pts = root.polygonPoints
                if (!pts || pts.length === undefined || pts.length < 6) return
                ctx.beginPath()
                ctx.moveTo(pts[0], pts[1])
                for (var i = 2; i < pts.length - 1; i += 2) {
                    ctx.lineTo(pts[i], pts[i + 1])
                }
                ctx.closePath()
                ctx.fillStyle = "rgba(128, 255, 128, 0.33)"
                ctx.fill()
                ctx.lineWidth = 1
                ctx.strokeStyle = "rgba(128, 255, 128, 0.75)"
                ctx.stroke()
            }
            Component.onCompleted: requestPaint()
        }

        Image {
            id: uiImg
            anchors.fill: parent
            source: root._fileUrl(root.overlayPath)
            fillMode: Image.Stretch
            asynchronous: false
        }
    }
}
