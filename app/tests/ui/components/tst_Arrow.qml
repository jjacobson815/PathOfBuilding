import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.Arrow {
        id: arrow
        x: 20
        y: 20
        width: 12
        height: 12
        direction: "down"
    }

    TestCase {
        id: tc
        name: "ArrowTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            arrow.direction = "down"
            arrow.glyphColor = theme.text
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, arrow, "pob.arrow.root")
            compare(arrow.direction, "down")
            arrow.direction = "up"
            wait(15)
            arrow.direction = "left"
            wait(15)
            arrow.direction = "right"
            wait(15)
            arrow.glyphColor = theme.muted
            wait(15)
            compare(arrow.glyphColor, theme.muted)
            Oracle.assertMultiResLayout(tc, container, arrow, uiTest, "Arrow")
            Oracle.assertZeroWarnings(tc, uiTest, "Arrow")
        }
    }
}
