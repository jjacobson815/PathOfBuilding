import QtQuick
import QtTest
import "../UiTestOracle.js" as Oracle

Item {
    id: harness
    width: 100
    height: 100

    TestCase {
        id: tc
        name: "MainShellTest"
        when: windowShown

        property var win: null

        function init() {
            uiTest.resetWarnings()
            uiTest.resetEngineForTest()
            var comp = Qt.createComponent("qrc:/qml/main.qml")
            compare(comp.status, Component.Ready, comp.errorString())
            win = comp.createObject(null, { width: 1100, height: 720, visible: true })
            verify(win !== null)
            win.requestActivate()
            waitForRendering(win.contentItem)
            wait(20)
        }

        function cleanup() {
            if (win) {
                win.visible = false
                win.destroy()
                win = null
                wait(20)
            }
            uiTest.resetEngineForTest()
        }

        function test_ac01_ac02_ac03_ac05_shell() {
            // AC-01: Initial render in BUILD mode after resetEngineForTest()
            compare(luaEngine.currentMode, "BUILD")
            var skillsBtn = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.shell.sidebar.btn_nav_SKILLS")
            verify(skillsBtn.width > 0 && skillsBtn.height > 0)
            Oracle.findRequired(tc, uiTest, win.contentItem, "pob.shell.dialog.save_prompt")

            // AC-03: Click sidebar Skills button
            mouseClick(skillsBtn)
            tryCompare(luaEngine, "currentView", "SKILLS")

            // AC-05: Sidebar collapse toggle
            var collapseBtn = uiTest.findObject(win.contentItem, "pob.topbar.collapse")
            verify(collapseBtn !== null)
            mouseClick(collapseBtn)
            wait(180)
            mouseClick(collapseBtn)
            wait(180)

            // Back button transitions BUILD -> LIST when unsaved === false (or confirm Don't Save)
            var backBtn = uiTest.findObject(win.contentItem, "pob.topbar.back")
            verify(backBtn !== null)
            mouseClick(backBtn)
            wait(20)
            var sp = uiTest.findObject(win.contentItem, "pob.shell.dialog.save_prompt")
            if (sp && sp.visible) sp.extraClicked()
            tryCompare(luaEngine, "currentMode", "LIST")
            var buildList = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.buildlist.root")
            verify(buildList.visible)

            var newBtn = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.buildlist.btn_new")
            mouseClick(newBtn)
            tryCompare(luaEngine, "currentMode", "BUILD")
            wait(20)

            // AC-02: Multi-resolution layout oracle across 960x640, 1100x720, 1600x900
            var sizes = [[960, 640], [1100, 720], [1600, 900]]
            for (var i = 0; i < sizes.length; i++) {
                win.width = sizes[i][0]
                win.height = sizes[i][1]
                wait(30)
                var rep = uiTest.checkLayoutOracle(win.contentItem, sizes[i][0], sizes[i][1])
                verify(rep.ok, "MainShell Layout/Overflow at " + sizes[i][0] + "x" + sizes[i][1] + ": " + JSON.stringify(rep))
            }

            Oracle.assertZeroWarnings(tc, uiTest, "MainShell")
        }
    }
}
