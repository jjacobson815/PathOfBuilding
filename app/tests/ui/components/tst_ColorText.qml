import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.ColorText {
        id: ct
        x: 20
        y: 20
        sourceText: "Hello World"
    }

    TestCase {
        id: tc
        name: "ColorTextTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            ct.sourceText = "Hello World"
            wait(10)
        }

        function test_ac01_initial_render() {
            Oracle.findRequired(tc, uiTest, ct, "pob.colortext.root")
            verify(ct.text.indexOf("Hello World") >= 0)
            Oracle.assertMultiResLayout(tc, container, ct, uiTest, "ColorText")
            Oracle.assertZeroWarnings(tc, uiTest, "ColorText AC-01")
        }

        function test_ac02_hex_color() {
            ct.sourceText = "^xFFFF00Yellow"
            wait(10)
            verify(ct.text.toUpperCase().indexOf("#FFFF00") >= 0)
            verify(ct.text.indexOf("Yellow") >= 0)
            Oracle.assertZeroWarnings(tc, uiTest, "ColorText AC-02")
        }

        function test_ac03_palette_and_ac04_entity_escaping() {
            ct.sourceText = "^1Error"
            wait(10)
            verify(ct.text.indexOf("<font") >= 0)

            ct.sourceText = "^7Life < 50%"
            wait(10)
            verify(ct.text.indexOf("&lt;") >= 0)
            Oracle.assertZeroWarnings(tc, uiTest, "ColorText AC-03/04")
        }
    }
}
