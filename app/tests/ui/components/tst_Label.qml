import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.Label {
        id: lbl
        x: 20
        y: 20
        label: "Test Label"
    }

    TestCase {
        id: tc
        name: "LabelTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            lbl.label = "Test Label"
            lbl.size = theme.fontSize
            wait(10)
        }

        function test_ac01_initial_render() {
            Oracle.findRequired(tc, uiTest, lbl, "pob.label.root")
            verify(lbl.height >= theme.fontSize)
            verify(lbl.width > 0)
            Oracle.assertMultiResLayout(tc, container, lbl, uiTest, "Label")
            Oracle.assertZeroWarnings(tc, uiTest, "Label AC-01")
        }

        function test_ac02_color_codes() {
            lbl.label = "^1Red ^2Green"
            wait(10)
            compare(lbl.textFormat, Text.StyledText)
            verify(lbl.text.indexOf("<font") >= 0)
            verify(lbl.text.indexOf("^1") < 0)
            Oracle.assertZeroWarnings(tc, uiTest, "Label AC-02")
        }

        function test_ac03_textmetrics_parity_and_ac04_dynamic_resize() {
            lbl.label = "A"
            wait(10)
            var w1 = lbl.width
            verify(w1 >= textMetrics.width(lbl.size, "VAR", "A"))
            lbl.label = "A much longer string"
            wait(10)
            verify(lbl.width > w1)
            verify(lbl.width >= textMetrics.width(lbl.size, "VAR", "A much longer string"))
            Oracle.assertZeroWarnings(tc, uiTest, "Label AC-03/04")
        }
    }
}
