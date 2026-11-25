import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Item {
        id: host
        x: 20; y: 20; width: 120; height: 60
        property int clicks: 0
        MouseArea {
            anchors.fill: parent
            onClicked: host.clicks++
        }
        Widgets.RectangleOutline {
            id: outline
            anchors.fill: parent
        }
    }

    TestCase {
        id: tc
        name: "RectangleOutlineTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            outline.colors = [1, 1, 1]
            outline.stroke = 1
            host.clicks = 0
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, outline, "pob.outline.root")
            compare(outline.border.width, 1)
            compare(outline.color, Qt.rgba(0, 0, 0, 0))

            outline.colors = [1, 0, 0]
            outline.stroke = 3
            wait(10)
            compare(outline.border.color, Qt.rgba(1, 0, 0, 1))
            compare(outline.border.width, 3)

            // Malformed/null color fallback without TypeError
            outline.colors = null
            wait(10)
            compare(outline.border.color, theme.border)

            // Click passes through to underlying MouseArea
            mouseClick(host)
            compare(host.clicks, 1)

            Oracle.assertMultiResLayout(tc, container, host, uiTest, "RectangleOutline")
            Oracle.assertZeroWarnings(tc, uiTest, "RectangleOutline")
        }
    }
}
