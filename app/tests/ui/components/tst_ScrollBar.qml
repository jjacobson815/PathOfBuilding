import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.ScrollBar {
        id: sb
        x: 40
        y: 40
        width: 18
        height: 200
        dir: "VERTICAL"
        step: 20
        contentDim: 500
        viewDim: 200
    }

    TestCase {
        id: tc
        name: "ScrollBarTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            sb.autoHide = false
            sb.controlEnabled = true
            sb.contentDim = 500
            sb.viewDim = 200
            sb.setOffset(0)
            wait(10)
        }

        function test_ac01_initial_render_and_zero_warnings() {
            Oracle.findRequired(tc, uiTest, sb, "pob.scrollbar.root")
            Oracle.findRequired(tc, uiTest, sb, "pob.scrollbar.up")
            Oracle.findRequired(tc, uiTest, sb, "pob.scrollbar.down")
            Oracle.findRequired(tc, uiTest, sb, "pob.scrollbar.track")
            Oracle.findRequired(tc, uiTest, sb, "pob.scrollbar.knob")

            verify(sb.active)
            compare(sb.offsetMax, 300)
            Oracle.assertMultiResLayout(tc, container, sb, uiTest, "ScrollBar")
            Oracle.assertZeroWarnings(tc, uiTest, "ScrollBar AC-01")
        }

        function test_ac02_autohide_collapse() {
            sb.autoHide = true
            sb.contentDim = 150
            sb.viewDim = 200
            wait(10)
            verify(!sb.active)
            verify(!sb.visible)
            Oracle.assertZeroWarnings(tc, uiTest, "ScrollBar AC-02")
        }

        function test_ac03_hold_to_repeat() {
            var down = Oracle.findRequired(tc, uiTest, sb, "pob.scrollbar.down")
            mousePress(down, down.width / 2, down.height / 2)
            wait(20)
            compare(sb.offset, 20)
            tryVerify(function() { return sb.offset >= 60 }, 900)
            mouseRelease(down, down.width / 2, down.height / 2)
            Oracle.assertZeroWarnings(tc, uiTest, "ScrollBar AC-03")
        }

        function test_ac04_track_page_jump() {
            var track = Oracle.findRequired(tc, uiTest, sb, "pob.scrollbar.track")
            mouseClick(track, track.width / 2, track.height - 5)
            wait(10)
            verify(sb.offset > 0)
            Oracle.assertZeroWarnings(tc, uiTest, "ScrollBar AC-04")
        }

        function test_ac05_scroll_into_view_and_clamp() {
            sb.scrollIntoView(250, 40)
            compare(sb.offset, 90)
            sb.contentDim = 220
            wait(10)
            verify(sb.offset <= sb.offsetMax)
            Oracle.assertZeroWarnings(tc, uiTest, "ScrollBar AC-05")
        }
    }
}
