import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.WarningsBar {
        id: wb
        x: 20
        y: 20
    }

    TestCase {
        id: tc
        name: "WarningsBarTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            wb.warnings = []
            wb.showWarnings = true
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, wb, "pob.warningsbar.root")
            var lbl = Oracle.findRequired(tc, uiTest, wb, "pob.warningsbar.count")
            var ma = Oracle.findRequired(tc, uiTest, wb, "pob.warningsbar.ma")
            var tt = Oracle.findRequired(tc, uiTest, wb, "pob.warningsbar.tooltip")

            // AC-01: Empty warnings collapses
            verify(!wb.visible)
            compare(wb.implicitHeight, 0)

            // AC-02: Singular vs plural grammar
            wb.warnings = ["Single warning"]
            wait(10)
            verify(wb.visible)
            compare(wb.implicitHeight, 18)
            verify(lbl.label.indexOf("1 Warning") >= 0)
            verify(lbl.label.indexOf("1 Warnings") < 0)

            wb.warnings = ["First warning", "Second warning"]
            wait(10)
            verify(lbl.label.indexOf("2 Warnings") >= 0)

            // AC-04: Hover shows tooltip
            mouseMove(ma, ma.width / 2, ma.height / 2)
            tryCompare(tt, "visible", true)
            compare(tt.lines.length, 2)

            // AC-05: showWarnings=false hides bar
            wb.showWarnings = false
            wait(10)
            verify(!wb.visible)

            wb.showWarnings = true
            Oracle.assertMultiResLayout(tc, container, wb, uiTest, "WarningsBar")
            Oracle.assertZeroWarnings(tc, uiTest, "WarningsBar")
        }
    }
}
