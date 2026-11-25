import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    property var lastTipState: undefined

    MouseArea {
        id: parkArea
        x: 10; y: 10; width: 20; height: 20
        hoverEnabled: true
    }

    Widgets.CheckBox {
        id: cb
        x: 240
        y: 40
        label: "Test Checkbox"
        state: false
    }

    SignalSpy { id: toggledSpy; target: cb; signalName: "toggled" }

    TestCase {
        id: tc
        name: "CheckBoxTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            cb.label = "Test Checkbox"
            cb.state = false
            cb.controlEnabled = true
            cb.borderFunc = null
            cb.tooltipFunc = null
            cb.noTooltip = false
            container.lastTipState = undefined
            toggledSpy.clear()
            mouseMove(parkArea, 10, 10, 10)
            wait(15)
            tryCompare(cb, "hovered", false)
        }

        function test_ac01_initial_render_and_zero_warnings() {
            Oracle.findRequired(tc, uiTest, cb, "pob.checkbox.root")
            Oracle.findRequired(tc, uiTest, cb, "pob.checkbox.chrome")
            Oracle.findRequired(tc, uiTest, cb, "pob.checkbox.mark")
            Oracle.findRequired(tc, uiTest, cb, "pob.checkbox.label")
            Oracle.findRequired(tc, uiTest, cb, "pob.checkbox.ma")

            compare(cb.implicitWidth, 18)
            compare(cb.implicitHeight, 18)
            verify(cb.labelWidth > 0)
            Oracle.assertMultiResLayout(tc, container, cb, uiTest, "CheckBox")
            Oracle.assertZeroWarnings(tc, uiTest, "CheckBox AC-01")
        }

        function test_ac02_toggle_on_click() {
            // Click square
            mouseClick(cb, cb.width / 2, cb.height / 2)
            compare(toggledSpy.count, 1)
            compare(toggledSpy.signalArguments[0][0], true)
            compare(cb.state, true)

            // Click label area to the left
            var lbl = Oracle.findRequired(tc, uiTest, cb, "pob.checkbox.label")
            mouseClick(lbl, lbl.width / 2, lbl.height / 2)
            compare(toggledSpy.count, 2)
            compare(toggledSpy.signalArguments[1][0], false)
            mouseMove(cb, cb.width / 2, cb.height / 2, 10)
            mouseMove(parkArea, 10, 10, 10)
            wait(15)
            Oracle.assertZeroWarnings(tc, uiTest, "CheckBox AC-02")
        }

        function test_ac03_state_aware_tooltip() {
            cb.state = true
            cb.tooltipFunc = function(tt, st) {
                container.lastTipState = st
                tt.addLine(14, "State: " + st)
            }
            mouseMove(cb, cb.width / 2, cb.height / 2)
            tryCompare(cb, "hovered", true)
            tryCompare(container, "lastTipState", true)
            Oracle.assertZeroWarnings(tc, uiTest, "CheckBox AC-03")
        }

        function test_ac04_disabled_click_suppression() {
            cb.controlEnabled = false
            cb.state = true
            wait(10)
            var mark = Oracle.findRequired(tc, uiTest, cb, "pob.checkbox.mark")
            compare(mark.glyphColor, theme.muted)
            mouseClick(cb, cb.width / 2, cb.height / 2)
            compare(toggledSpy.count, 0)
            Oracle.assertZeroWarnings(tc, uiTest, "CheckBox AC-04")
        }

        function test_ac05_dynamic_border_color() {
            cb.borderFunc = function() { return [1, 0, 0] }
            wait(10)
            var chrome = Oracle.findRequired(tc, uiTest, cb, "pob.checkbox.chrome")
            compare(chrome.border.color, Qt.rgba(1, 0, 0, 1))
            mouseMove(cb, cb.width / 2, cb.height / 2)
            wait(15)
            compare(chrome.border.color, theme.borderStrong)
            Oracle.assertZeroWarnings(tc, uiTest, "CheckBox AC-05")
        }
    }
}
