import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Item {
        id: homeHost
        width: 1000
        height: 600
        Widgets.Tooltip {
            id: tt
        }
    }

    TestCase {
        id: tc
        name: "TooltipTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            homeHost.visible = true
            tt.floating = false
            tt.clear()
            tt.hide()
            wait(10)
        }

        function test_ac01_initial_render_and_zero_warnings() {
            Oracle.findRequired(tc, uiTest, tt, "pob.tooltip.root")
            Oracle.findRequired(tc, uiTest, tt, "pob.tooltip.header")
            Oracle.findRequired(tc, uiTest, tt, "pob.tooltip.lines")
            verify(!tt.visible)
            compare(tt.lines.length, 0)
            Oracle.assertMultiResLayout(tc, container, tt, uiTest, "Tooltip")
            Oracle.assertZeroWarnings(tc, uiTest, "Tooltip AC-01")
        }

        function test_ac02_text_wrapping() {
            tt.maxWidth = 200
            tt.addLine(14, "This is a very long description that exceeds maximum width and must wrap cleanly")
            verify(tt.lines.length > 1)
            Oracle.assertZeroWarnings(tc, uiTest, "Tooltip AC-02")
        }

        function test_ac03_consecutive_separator_suppression() {
            tt.addLine(14, "Header")
            tt.addSeparator(8)
            tt.addSeparator(8)
            compare(tt.lines.length, 2)
            Oracle.assertZeroWarnings(tc, uiTest, "Tooltip AC-03")
        }

        function test_ac04_memoization_checkforupdate() {
            verify(tt.checkForUpdate(["Item A", 20]))
            tt.addLine(14, "Cached line")
            verify(!tt.checkForUpdate(["Item A", 20]))
            compare(tt.lines.length, 1)
            Oracle.assertZeroWarnings(tc, uiTest, "Tooltip AC-04")
        }

        function test_ac05_viewport_flipping_and_windows_url() {
            tt.addLine(14, "Right edge tooltip text")
            tt.showAt(900, 100, 40, 20, Qt.rect(0, 0, 1000, 600))
            verify(tt.visible)
            verify(tt.x < 900)
            compare(tt._fileUrl("C:\\path\\to\\icon.png"), "file:///C:/path/to/icon.png")
            Oracle.assertZeroWarnings(tc, uiTest, "Tooltip AC-05")
        }
    }
}
