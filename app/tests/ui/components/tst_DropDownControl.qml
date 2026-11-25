import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.DropDownControl {
        id: dd
        x: 40
        y: 40
        width: 200
        model: ["Alpha", "Beta", "Gamma", "Deadeye", "Deadly Ailments"]
        currentIndex: 0
    }

    SignalSpy {
        id: selectedSpy
        target: dd
        signalName: "selected"
    }

    TestCase {
        id: tc
        name: "DropDownControlTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dd.closeList()
            dd.searchable = false
            dd.controlEnabled = true
            dd.model = ["Alpha", "Beta", "Gamma", "Deadeye", "Deadly Ailments"]
            dd.currentIndex = 0
            selectedSpy.clear()
            wait(10)
        }

        function test_ac01_initial_render_and_empty_map_safety() {
            Oracle.findRequired(tc, uiTest, dd, "pob.dropdown.root")
            var val = Oracle.findRequired(tc, uiTest, dd, "pob.dropdown.value")
            Oracle.findRequired(tc, uiTest, dd, "pob.dropdown.arrow")
            Oracle.findRequired(tc, uiTest, dd, "pob.dropdown.popup")
            Oracle.findRequired(tc, uiTest, dd, "pob.dropdown.list")
            Oracle.findRequired(tc, uiTest, dd, "pob.dropdown.search")

            compare(dd.count, 5)
            compare(val.sourceText, "Alpha")

            // Empty Lua table marshals as QVariantMap with length === undefined
            dd.model = uiTest.toVariantMap({})
            wait(10)
            compare(dd.count, 0)

            dd.model = uiTest.toVariantList(["Alpha", "Beta", "Gamma"])
            dd.currentIndex = 0
            wait(10)
            compare(dd.count, 3)

            Oracle.assertMultiResLayout(tc, container, dd, uiTest, "DropDownControl")
            Oracle.assertZeroWarnings(tc, uiTest, "DropDownControl AC-01")
        }

        function test_ac02_user_pick_signal() {
            mouseClick(dd)
            tryCompare(dd, "open", true)
            var list = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.dropdown.list")
            mouseClick(list, list.width / 2, dd._rowHeight * 2 + dd._rowHeight / 2)
            tryCompare(dd, "open", false)
            compare(selectedSpy.count, 1)
            compare(selectedSpy.signalArguments[0][0], 2)
            compare(dd.currentIndex, 2)
            Oracle.assertZeroWarnings(tc, uiTest, "DropDownControl AC-02")
        }

        function test_ac03_programmatic_index_silence() {
            dd.currentIndex = 1
            wait(10)
            compare(dd.currentIndex, 1)
            compare(selectedSpy.count, 0)
            Oracle.assertZeroWarnings(tc, uiTest, "DropDownControl AC-03")
        }

        function test_ac04_mouse_wheel() {
            dd.currentIndex = 2
            selectedSpy.clear()
            mouseMove(dd, dd.width / 2, dd.height / 2)
            mouseWheel(dd, dd.width / 2, dd.height / 2, 0, 120)
            wait(10)
            compare(dd.currentIndex, 1)
            compare(selectedSpy.count, 1)
            compare(selectedSpy.signalArguments[0][0], 1)

            // Clamp at 0
            mouseWheel(dd, dd.width / 2, dd.height / 2, 0, 120)
            mouseWheel(dd, dd.width / 2, dd.height / 2, 0, 120)
            wait(10)
            compare(dd.currentIndex, 0)
            Oracle.assertZeroWarnings(tc, uiTest, "DropDownControl AC-04")
        }

        function test_ac05_searchable_filtering() {
            dd.searchable = true
            mouseClick(dd)
            tryCompare(dd, "open", true)
            keyClick(Qt.Key_D)
            keyClick(Qt.Key_E)
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_D)
            wait(10)
            compare(dd.viewCount, 2)
            keyClick(Qt.Key_Return)
            tryCompare(dd, "open", false)
            compare(dd.currentIndex, 3)
            compare(selectedSpy.count, 1)
            compare(selectedSpy.signalArguments[0][0], 3)
            Oracle.assertZeroWarnings(tc, uiTest, "DropDownControl AC-05")
        }
    }
}
