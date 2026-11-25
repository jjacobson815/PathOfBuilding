import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    property int childClicks: 0
    property string lastDropType: ""
    property var lastDropVal: null

    Widgets.DragSource {
        id: gemSrc
        x: 20; y: 20; width: 60; height: 24
        dragType: "GEM"
        dragValue: ({ name: "Arc" })
    }

    Widgets.DragSource {
        id: itemSrc
        x: 20; y: 60; width: 60; height: 24
        dragType: "ITEM"
        dragValue: ({ name: "Wand" })
    }

    Widgets.DropTarget {
        id: target
        x: 200; y: 20; width: 120; height: 60
        canReceiveDrag: function(t, v) { return t === "GEM" }
        receiveDrag: function(t, v, s) {
            container.lastDropType = t
            container.lastDropVal = v
        }
        Widgets.Button {
            id: innerBtn
            label: "Inner"
            onClicked: container.childClicks++
        }
    }

    TestCase {
        id: tc
        name: "DropTargetTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            gemSrc.x = 20; gemSrc.y = 20
            itemSrc.x = 20; itemSrc.y = 60
            container.childClicks = 0
            container.lastDropType = ""
            container.lastDropVal = null
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, target, "pob.droptarget.root")
            Oracle.findRequired(tc, uiTest, target, "pob.droptarget.area")
            verify(!target.highlighted)

            // AC-05: Child click works
            mouseClick(innerBtn)
            compare(container.childClicks, 1)

            // AC-02: Incompatible drag rejected
            mousePress(itemSrc, 10, 10, Qt.LeftButton)
            mouseMove(container, 80, 70, 10, Qt.LeftButton)
            mouseMove(container, 220, 40, 10, Qt.LeftButton)
            wait(15)
            verify(!target.highlighted)
            mouseRelease(container, 220, 40, Qt.LeftButton)
            compare(container.lastDropType, "")

            // AC-03 & AC-04: Compatible drag highlights and drops
            mousePress(gemSrc, 10, 10, Qt.LeftButton)
            mouseMove(container, 80, 30, 10, Qt.LeftButton)
            mouseMove(container, 230, 40, 10, Qt.LeftButton)
            tryCompare(target, "highlighted", true)
            mouseRelease(container, 230, 40, Qt.LeftButton)
            compare(container.lastDropType, "GEM")
            compare(container.lastDropVal.name, "Arc")

            Oracle.assertMultiResLayout(tc, container, target, uiTest, "DropTarget")
            Oracle.assertZeroWarnings(tc, uiTest, "DropTarget")
        }
    }
}
