import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    property string droppedType: ""
    property var droppedVal: null

    Widgets.DragSource {
        id: ds
        x: 10
        y: 20
        width: 80
        height: 24
        dragType: "GEM"
        dragValue: ({ id: 42 })
        Rectangle { anchors.fill: parent; color: "#1e293b" }
    }

    DropArea {
        id: dropZone
        x: 150
        y: 160
        width: 120
        height: 80
        keys: ["GEM"]
        onDropped: function(drop) {
            container.droppedType = drop.source.dragType
            container.droppedVal = drop.source.dragValue
        }
    }

    TestCase {
        id: tc
        name: "DragSourceTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            ds.x = 10
            ds.y = 20
            container.droppedType = ""
            container.droppedVal = null
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, ds, "pob.dragsource.root")
            Oracle.findRequired(tc, uiTest, ds, "pob.dragsource.ma")
            compare(ds.opacity, 1.0)
            verify(!ds.dragging)

            // AC-02, AC-03, AC-04, AC-05
            mousePress(ds, 10, 10, Qt.LeftButton)
            mouseMove(container, 25, 30, 10, Qt.LeftButton)
            verify(!ds.dragging)

            mouseMove(container, 50, 30, 10, Qt.LeftButton)
            mouseMove(container, 200, 200, 10, Qt.LeftButton)
            tryCompare(ds, "dragging", true)
            compare(ds.opacity, 0.5)
            compare(ds.z, 200)

            mouseRelease(container, 200, 200, Qt.LeftButton)
            tryCompare(ds, "dragging", false)
            compare(ds.x, 10)
            compare(ds.y, 20)
            compare(container.droppedType, "GEM")
            compare(container.droppedVal.id, 42)

            Oracle.assertMultiResLayout(tc, container, ds, uiTest, "DragSource")
            Oracle.assertZeroWarnings(tc, uiTest, "DragSource")
        }
    }
}
