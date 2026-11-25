import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.CalcRadiusVisual {
        id: rv
        x: 20
        y: 20
        radiusValue: 20
        polygonPoints: []
    }

    TestCase {
        id: tc
        name: "CalcRadiusVisualTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            rv.polygonPoints = []
            wait(10)
        }

        function test_all_ac() {
            var guide = Oracle.findRequired(tc, uiTest, rv, "pob.radiusVisual.guide")
            var canvas = Oracle.findRequired(tc, uiTest, rv, "pob.radiusVisual.canvas")
            var uiImg = Oracle.findRequired(tc, uiTest, rv, "pob.radiusVisual.ui")

            compare(rv.width, 484)
            compare(rv.height, 274)

            // AC-04: Windows path backslash normalization
            compare(rv._fileUrl("C:\\PoB\\Assets\\range_guide.png"), "file:///C:/PoB/Assets/range_guide.png")
            compare(rv._fileUrl("/opt/pob/Assets/range_guide.png"), "file:///opt/pob/Assets/range_guide.png")

            // AC-02: 36-vertex AoE circle polygon
            var pts = []
            for (var i = 0; i < 36; i++) {
                var ang = i * Math.PI * 2 / 36
                pts.push(240 + Math.cos(ang) * 60)
                pts.push(135 + Math.sin(ang) * 60)
            }
            rv.polygonPoints = pts
            wait(20)

            verify(guide.visible && canvas.visible && uiImg.visible)
            Oracle.assertMultiResLayout(tc, container, rv, uiTest, "CalcRadiusVisual")
            Oracle.assertZeroWarnings(tc, uiTest, "CalcRadiusVisual")
        }
    }
}
