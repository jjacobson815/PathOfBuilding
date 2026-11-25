import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    property var receivedPayload: null

    Item {
        id: srcItem
        x: 30
        y: 40
        width: 80
        height: 20
        Widgets.DragGhost { id: ghost }
    }

    DropArea {
        x: 200
        y: 200
        width: 100
        height: 60
        keys: ["Item"]
        onDropped: function(drop) {
            container.receivedPayload = drop.source.dragValue
        }
    }

    TestCase {
        id: tc
        name: "DragGhostTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            ghost.cancel()
            container.receivedPayload = null
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.dragghost.root")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.dragghost.label")
            verify(!ghost.visible)
            verify(!ghost.active)

            ghost.start(srcItem, 10, 10, "Item", { id: 1 }, "Test Item")
            verify(ghost.visible)
            compare(ghost.text, "Test Item")
            verify(ghost.active)

            ghost.moveTo(srcItem, 190, 180)
            verify(ghost.x >= 200)
            verify(ghost.y >= 200)

            ghost.finish()
            verify(!ghost.visible)
            verify(!ghost.active)
            verify(container.receivedPayload !== null)
            compare(container.receivedPayload.id, 1)

            ghost.start(srcItem, 10, 10, "Item", { id: 2 }, "Cancelled")
            verify(ghost.visible)
            ghost.cancel()
            verify(!ghost.visible)

            Oracle.assertMultiResLayout(tc, container, srcItem, uiTest, "DragGhost")
            Oracle.assertZeroWarnings(tc, uiTest, "DragGhost")
        }
    }
}
