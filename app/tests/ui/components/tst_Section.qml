import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.Section {
        id: sec
        x: 20
        y: 30
        width: 300
        height: 120
        label: "Settings"

        Widgets.Button {
            id: childBtn
            label: "Action"
        }
    }

    TestCase {
        id: tc
        name: "SectionTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            sec.label = "Settings"
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, sec, "pob.section.root")
            var plate = Oracle.findRequired(tc, uiTest, sec, "pob.section.plate")
            var lbl = Oracle.findRequired(tc, uiTest, sec, "pob.section.label")

            verify(plate.visible)
            compare(plate.y, -9)
            var w1 = plate.width
            verify(w1 >= lbl.width + 10)

            sec.label = "A Much Longer Section Title"
            wait(10)
            verify(plate.width > w1)
            verify(plate.width >= lbl.width + 10)

            sec.label = ""
            wait(10)
            verify(!plate.visible)

            var pt = childBtn.mapToItem(sec, 0, 0)
            verify(pt.x >= 4)
            verify(pt.y >= 4)

            Oracle.assertMultiResLayout(tc, container, sec, uiTest, "Section")
            Oracle.assertZeroWarnings(tc, uiTest, "Section")
        }
    }
}
