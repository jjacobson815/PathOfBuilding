import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    property var startArgs: null
    property var endArgs: null
    property var rightArgs: null

    Widgets.Dragger {
        id: dragger
        x: 100
        y: 100
        label: "//"
        onDragStart: function(px, py) { container.startArgs = [px, py] }
        onDragEnd: function(dx, dy) { container.endArgs = [dx, dy] }
        onRightClick: function(rx, ry) { container.rightArgs = [rx, ry] }
    }

    TestCase {
        id: tc
        name: "DraggerTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dragger.label = "//"
            dragger.locked = false
            dragger.controlEnabled = true
            container.startArgs = null
            container.endArgs = null
            container.rightArgs = null
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, dragger, "pob.dragger.root")
            Oracle.findRequired(tc, uiTest, dragger, "pob.dragger.chrome")
            Oracle.findRequired(tc, uiTest, dragger, "pob.dragger.glyph")
            Oracle.findRequired(tc, uiTest, dragger, "pob.dragger.ma")

            verify(dragger.isGlyph)
            compare(dragger.implicitWidth, 24)

            // AC-02 & AC-03: Drag start & delta polarity
            mousePress(dragger, 5, 5, Qt.LeftButton)
            verify(container.startArgs !== null)
            verify(dragger.dragging)
            mouseMove(dragger, 25, 55, 10, Qt.LeftButton)
            mouseRelease(dragger, 25, 55, Qt.LeftButton)
            verify(!dragger.dragging)
            verify(container.endArgs !== null)
            compare(container.endArgs[0], -20)
            compare(container.endArgs[1], -50)

            // AC-04: Right click
            container.startArgs = null
            mouseClick(dragger, 10, 10, Qt.RightButton)
            verify(container.rightArgs !== null)
            verify(container.startArgs === null)

            // AC-05: Locked blocks input
            dragger.locked = true
            container.startArgs = null
            container.endArgs = null
            mousePress(dragger, 5, 5, Qt.LeftButton)
            mouseRelease(dragger, 15, 15, Qt.LeftButton)
            verify(container.startArgs === null)
            verify(container.endArgs === null)

            Oracle.assertMultiResLayout(tc, container, dragger, uiTest, "Dragger")
            Oracle.assertZeroWarnings(tc, uiTest, "Dragger")
        }
    }
}
