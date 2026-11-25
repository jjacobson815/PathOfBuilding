import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.EditControl {
        id: edit
        x: 40
        y: 40
        width: 180
        text: "Initial"
        placeholder: "Search..."
    }

    Widgets.Button {
        id: focusStealer
        x: 40
        y: 100
        label: "Other"
    }

    SignalSpy { id: editedSpy; target: edit; signalName: "edited" }
    SignalSpy { id: committedSpy; target: edit; signalName: "committed" }
    SignalSpy { id: revertedSpy; target: edit; signalName: "reverted" }

    TestCase {
        id: tc
        name: "EditControlTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            focusStealer.forceActiveFocus()
            edit.controlEnabled = true
            edit.readOnly = false
            edit.isNumeric = false
            edit.numericMin = undefined
            edit.numericMax = undefined
            edit.selectAllOnFocus = true
            edit.text = "Initial"
            editedSpy.clear()
            committedSpy.clear()
            revertedSpy.clear()
            wait(10)
        }

        function test_ac01_initial_render_and_zero_warnings() {
            Oracle.findRequired(tc, uiTest, edit, "pob.edit.root")
            Oracle.findRequired(tc, uiTest, edit, "pob.edit.chrome")
            var inp = Oracle.findRequired(tc, uiTest, edit, "pob.edit.input")
            Oracle.findRequired(tc, uiTest, edit, "pob.edit.placeholder")

            compare(edit.implicitHeight, theme.controlSize)
            compare(inp.text, "Initial")
            Oracle.assertMultiResLayout(tc, container, edit, uiTest, "EditControl")
            Oracle.assertZeroWarnings(tc, uiTest, "EditControl AC-01")
        }

        function test_ac02_select_all_on_focus() {
            var inp = Oracle.findRequired(tc, uiTest, edit, "pob.edit.input")
            edit.forceEditFocus()
            tryCompare(inp, "activeFocus", true)
            compare(inp.selectedText, "Initial")
            Oracle.assertZeroWarnings(tc, uiTest, "EditControl AC-02")
        }

        function test_ac03_escape_reverts_value() {
            edit.text = "Level 90"
            wait(10)
            var inp = Oracle.findRequired(tc, uiTest, edit, "pob.edit.input")
            edit.forceEditFocus()
            tryCompare(inp, "activeFocus", true)
            keyClick(Qt.Key_Backspace)
            keyClick(Qt.Key_L)
            keyClick(Qt.Key_E)
            keyClick(Qt.Key_V)
            keyClick(Qt.Key_Escape)
            wait(10)
            compare(inp.text, "Level 90")
            compare(revertedSpy.count, 1)
            Oracle.assertZeroWarnings(tc, uiTest, "EditControl AC-03")
        }

        function test_ac04_numeric_clamping_on_commit() {
            edit.isNumeric = true
            edit.numericMin = 1
            edit.numericMax = 100
            edit.text = "10"
            wait(10)
            var inp = Oracle.findRequired(tc, uiTest, edit, "pob.edit.input")
            edit.forceEditFocus()
            tryCompare(inp, "activeFocus", true)
            keyClick(Qt.Key_1)
            keyClick(Qt.Key_5)
            keyClick(Qt.Key_0)
            keyClick(Qt.Key_Return)
            wait(10)
            compare(committedSpy.count, 1)
            compare(committedSpy.signalArguments[0][0], "100")
            compare(inp.text, "100")
            Oracle.assertZeroWarnings(tc, uiTest, "EditControl AC-04")
        }

        function test_ac05_character_filtering() {
            edit.isNumeric = true
            edit.text = "42"
            wait(10)
            var inp = Oracle.findRequired(tc, uiTest, edit, "pob.edit.input")
            edit.forceEditFocus()
            tryCompare(inp, "activeFocus", true)
            inp.deselect()
            inp.cursorPosition = 2
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_B)
            keyClick(Qt.Key_C)
            wait(10)
            compare(inp.text, "42")
            Oracle.assertZeroWarnings(tc, uiTest, "EditControl AC-05")
        }
    }
}
