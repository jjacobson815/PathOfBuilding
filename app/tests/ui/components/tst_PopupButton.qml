import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.PopupButton {
        id: pb
        x: 20
        y: 20
        label: "Cancel"
    }

    SignalSpy { id: clickSpy; target: pb; signalName: "clicked" }

    TestCase {
        id: tc
        name: "PopupButtonTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            pb.label = "Cancel"
            clickSpy.clear()
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, pb, "pob.popupbutton.root")
            Oracle.findRequired(tc, uiTest, pb, "pob.popupbutton.text")
            Oracle.findRequired(tc, uiTest, pb, "pob.popupbutton.ma")

            compare(pb.implicitHeight, 24)
            compare(pb.implicitWidth, 80)

            pb.label = "Connect Path Automatically"
            wait(10)
            verify(pb.implicitWidth > 80)

            mouseMove(pb, pb.width / 2, pb.height / 2)
            tryCompare(pb, "hovered", true)
            mouseClick(pb)
            compare(clickSpy.count, 1)

            Oracle.assertMultiResLayout(tc, container, pb, uiTest, "PopupButton")
            Oracle.assertZeroWarnings(tc, uiTest, "PopupButton")
        }
    }
}
