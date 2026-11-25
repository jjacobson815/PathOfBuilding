import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.Button {
        id: btn
        x: 20
        y: 20
        label: "Save Build"
    }

    SignalSpy {
        id: clickedSpy
        target: btn
        signalName: "clicked"
    }

    TestCase {
        id: tc
        name: "ButtonTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            btn.label = "Save Build"
            btn.width = Qt.binding(function() { return btn.implicitWidth })
            btn.height = Qt.binding(function() { return btn.implicitHeight })
            btn.controlEnabled = true
            btn.locked = false
            btn.noTooltip = false
            btn.tooltipText = ""
            btn.tooltipFunc = null
            btn.imageSource = ""
            clickedSpy.clear()
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_ac01_initial_render_and_zero_warnings() {
            var root = Oracle.findRequired(tc, uiTest, btn, "pob.button.root")
            Oracle.findRequired(tc, uiTest, btn, "pob.button.chrome")
            var txt = Oracle.findRequired(tc, uiTest, btn, "pob.button.text")
            Oracle.findRequired(tc, uiTest, btn, "pob.button.glyph")
            Oracle.findRequired(tc, uiTest, btn, "pob.button.image")
            Oracle.findRequired(tc, uiTest, btn, "pob.button.ma")

            compare(root.implicitHeight, 24)
            verify(root.implicitWidth > 24)
            verify(txt.visible)
            Oracle.assertMultiResLayout(tc, container, btn, uiTest, "Button")
            Oracle.assertZeroWarnings(tc, uiTest, "Button AC-01")
        }

        function test_ac02_click_and_disabled_suppression() {
            mouseClick(btn)
            compare(clickedSpy.count, 1)

            btn.controlEnabled = false
            wait(10)
            var chrome = Oracle.findRequired(tc, uiTest, btn, "pob.button.chrome")
            compare(chrome.color, theme.disabled)

            mouseClick(btn)
            compare(clickedSpy.count, 1)
            Oracle.assertZeroWarnings(tc, uiTest, "Button AC-02")
        }

        function test_ac03_disabled_tooltip_preservation() {
            btn.controlEnabled = false
            btn.tooltipText = "Disabled Reason"
            wait(10)
            mouseMove(btn, btn.width / 2, btn.height / 2)
            wait(20)
            verify(btn.hovered)
            var tt = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.button.tt")
            verify(tt.visible)
            verify(tt.lines.length > 0)
            compare(tt.lines[0].text, "Disabled Reason")
            Oracle.assertZeroWarnings(tc, uiTest, "Button AC-03")
        }

        function test_ac04_auto_tooltip_on_truncation() {
            btn.label = "Very Long Button Text That Must Truncate"
            btn.width = 40
            wait(10)
            var txt = Oracle.findRequired(tc, uiTest, btn, "pob.button.text")
            verify(txt.truncated)
            mouseMove(btn, btn.width / 2, btn.height / 2)
            wait(20)
            var tt = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.button.tt")
            verify(tt.visible)
            verify(tt.lines.length > 0)
            compare(tt.lines[0].text, "Very Long Button Text That Must Truncate")
            Oracle.assertZeroWarnings(tc, uiTest, "Button AC-04")
        }

        function test_ac05_glyph_rendering() {
            btn.label = "+"
            wait(10)
            verify(btn.isGlyph)
            var txt = Oracle.findRequired(tc, uiTest, btn, "pob.button.text")
            var glyph = Oracle.findRequired(tc, uiTest, btn, "pob.button.glyph")
            verify(!txt.visible)
            verify(glyph.visible)
            compare(glyph.glyphColor, theme.text)

            btn.controlEnabled = false
            wait(10)
            compare(glyph.glyphColor, theme.muted)
            Oracle.assertZeroWarnings(tc, uiTest, "Button AC-05")
        }
    }
}
