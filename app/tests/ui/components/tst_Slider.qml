import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    property real lastPreviewVal: -1

    Widgets.Slider {
        id: slider
        x: 40
        y: 40
        width: 160
        height: 18
        value: 0.5
    }

    TestCase {
        id: tc
        name: "SliderTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            slider.value = 0.5
            slider.divCount = 0
            slider.controlEnabled = true
            slider.invertScroll = false
            slider.noTooltip = false
            slider.tooltipFunc = null
            container.lastPreviewVal = -1
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_ac01_initial_render_and_zero_warnings() {
            Oracle.findRequired(tc, uiTest, slider, "pob.slider.root")
            Oracle.findRequired(tc, uiTest, slider, "pob.slider.knob")
            Oracle.findRequired(tc, uiTest, slider, "pob.slider.ma")
            compare(slider.knobSize, 16)
            Oracle.assertMultiResLayout(tc, container, slider, uiTest, "Slider")
            Oracle.assertZeroWarnings(tc, uiTest, "Slider AC-01")
        }

        function test_ac02_clamping() {
            slider.setVal(1.5)
            compare(slider.value, 1.0)
            slider.setVal(-0.2)
            compare(slider.value, 0.0)
            Oracle.assertZeroWarnings(tc, uiTest, "Slider AC-02")
        }

        function test_ac03_divval_detents() {
            slider.divCount = 4
            slider.value = 0.5
            wait(10)
            Oracle.findRequired(tc, uiTest, slider, "pob.slider.knob")
            var dv = slider.divVal()
            compare(dv[0], 2)
            compare(dv[1], 1.0)
            Oracle.assertZeroWarnings(tc, uiTest, "Slider AC-03")
        }

        function test_ac04_wheel_acceleration() {
            slider.value = 0.2
            mouseMove(slider, slider.width / 2, slider.height / 2)
            mouseWheel(slider, slider.width / 2, slider.height / 2, 0, 120)
            verify(Math.abs(slider.value - 0.25) < 0.001)

            mouseWheel(slider, slider.width / 2, slider.height / 2, 0, 120, Qt.LeftButton, Qt.ShiftModifier)
            verify(Math.abs(slider.value - 0.50) < 0.001)

            mouseWheel(slider, slider.width / 2, slider.height / 2, 0, 120, Qt.LeftButton, Qt.ControlModifier)
            verify(Math.abs(slider.value - 0.51) < 0.001)

            slider.invertScroll = true
            mouseWheel(slider, slider.width / 2, slider.height / 2, 0, 120)
            verify(Math.abs(slider.value - 0.46) < 0.001)
            Oracle.assertZeroWarnings(tc, uiTest, "Slider AC-04")
        }

        function test_ac05_hover_preview_tooltip() {
            slider.value = 0.2
            slider.tooltipFunc = function(tt, val) {
                container.lastPreviewVal = val
                tt.addLine(14, "Val: " + val.toFixed(2))
            }
            var targetX = 1 + slider.knobSize / 2 + slider.knobTravelPx * 0.75
            mouseMove(slider, targetX, slider.height / 2)
            wait(20)
            verify(Math.abs(container.lastPreviewVal - 0.75) < 0.05)
            verify(Math.abs(slider.value - 0.2) < 0.001)
            Oracle.assertZeroWarnings(tc, uiTest, "Slider AC-05")
        }
    }
}
