import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.CheckMark {
        id: mark
        x: 20
        y: 20
        width: 24
        height: 16
    }

    TestCase {
        id: tc
        name: "CheckMarkTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            mark.width = 24
            mark.height = 16
            mark.glyphColor = theme.text
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, mark, "pob.checkmark.root")
            compare(Math.min(mark.width, mark.height), 16)
            compare((mark.width - 16) / 2, 4)
            mark.glyphColor = theme.accent
            wait(15)
            compare(mark.glyphColor, theme.accent)
            Oracle.assertMultiResLayout(tc, container, mark, uiTest, "CheckMark")
            Oracle.assertZeroWarnings(tc, uiTest, "CheckMark")
        }
    }
}
