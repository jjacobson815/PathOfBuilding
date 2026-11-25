import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.GemSelect {
        id: gs
        x: 40
        y: 40
        width: 300
        height: 20
        groupIndex: 1
        row: 1
        text: ""
    }

    SignalSpy { id: pickedSpy; target: gs; signalName: "picked" }

    TestCase {
        id: tc
        name: "GemSelectTest"
        when: windowShown

        function initTestCase() {
            uiTest.resetEngineForTest()
            luaEngine.invoke("pob_skillsNewGroup", [])
        }

        function cleanupTestCase() {
            uiTest.resetEngineForTest()
        }

        function init() {
            uiTest.resetWarnings()
            gs.y = 40
            gs.text = "Fireball"
            gs.filter = ""
            pickedSpy.clear()
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            var inputObj = Oracle.findRequired(tc, uiTest, gs, "pob.gemSelect.input")
            var filtA = Oracle.findRequired(tc, uiTest, gs, "pob.gemSelect.filterActive")
            var filtS = Oracle.findRequired(tc, uiTest, gs, "pob.gemSelect.filterSupport")
            Oracle.findRequired(tc, uiTest, gs, "pob.gemSelect.listPopup")
            Oracle.findRequired(tc, uiTest, gs, "pob.gemSelect.candidateList")

            // AC-01: Committed gem name shown without warnings
            compare(inputObj.text, "Fireball")

            // AC-02: Focus + type "ctf" opens popup & navigates Down
            mouseClick(inputObj)
            tryCompare(gs, "dropped", true)
            keyClick(Qt.Key_Backspace)
            inputObj.text = "ctf"
            inputObj.textEdited()
            wait(20)
            verify(gs.rows.length > 0)
            keyClick(Qt.Key_Down)
            compare(gs.selIndex, 1)

            // AC-03: Enter commits & emits picked
            keyClick(Qt.Key_Return)
            tryCompare(gs, "dropped", false)
            compare(pickedSpy.count, 1)
            verify(pickedSpy.signalArguments[0][0].length > 0)

            // AC-04: Filter S & click text body clears filter
            mouseClick(filtS)
            compare(gs.filter, "support")
            tryCompare(gs, "dropped", true)
            mouseClick(inputObj)
            compare(gs.filter, "")

            // AC-05: Escape reverts to _initial
            inputObj.text = "TempText"
            inputObj.textEdited()
            keyClick(Qt.Key_Escape)
            tryCompare(gs, "dropped", false)
            compare(inputObj.text, gs._initial)

            // AC-06: Viewport boundary flip when near bottom
            gs.y = 690
            gs.openList()
            tryCompare(gs, "dropped", true)
            var listPopup = Oracle.findRequired(tc, uiTest, gs, "pob.gemSelect.listPopup")
            verify(listPopup._flipUp)
            gs._escape()

            Oracle.assertMultiResLayout(tc, container, gs, uiTest, "GemSelect")
            Oracle.assertZeroWarnings(tc, uiTest, "GemSelect")
        }
    }
}
