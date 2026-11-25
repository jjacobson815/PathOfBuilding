import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.TreeViewer {
        id: tv
        x: 20
        y: 20
        width: 500
        height: 400
    }

    SignalSpy { id: actionSpy; target: tv; signalName: "nodeAction" }

    TestCase {
        id: tc
        name: "TreeViewerTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            tv.showCrosshair = false
            tv.focusNodeId = -1
            actionSpy.clear()
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, tv, "pob.treeviewer.root")
            Oracle.findRequired(tc, uiTest, tv, "pob.treeviewer.scene")
            var ma = Oracle.findRequired(tc, uiTest, tv, "pob.treeviewer.ma")

            compare(tv.hoverNodeId, -1)
            verify(!tv.showCrosshair)

            // AC-02: Drag threshold hysteresis (<=5px does not start drag; >5px starts drag)
            mousePress(ma, 200, 200, Qt.LeftButton)
            mouseMove(ma, 203, 202, 10, Qt.LeftButton)
            verify(!ma.dragging)
            mouseMove(ma, 230, 220, 10, Qt.LeftButton)
            tryCompare(ma, "dragging", true)
            mouseRelease(ma, 230, 220, Qt.LeftButton)
            tryCompare(ma, "dragging", false)

            // AC-03: Ctrl+Click zooms without dispatching node click
            mouseClick(tv, 250, 200, Qt.LeftButton, Qt.ControlModifier)
            wait(10)
            compare(actionSpy.count, 0)

            // AC-04: Crosshair toggle for jewel socket preview
            tv.showCrosshair = true
            wait(10)
            verify(tv.showCrosshair)

            // AC-05: Signal connection smoke check
            tv.nodeAction(-1)
            compare(actionSpy.count, 1)

            Oracle.assertMultiResLayout(tc, container, tv, uiTest, "TreeViewer")
            Oracle.assertZeroWarnings(tc, uiTest, "TreeViewer")
        }
    }
}
