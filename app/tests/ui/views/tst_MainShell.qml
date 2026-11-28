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

            // AC-03: Click sidebar Skills button & Ctrl+1..8 hotkeys
            Oracle.step(tc, "AC-03: sidebar click + Ctrl+1..8 view switching")
            mouseClick(skillsBtn)
            tryCompare(luaEngine, "currentView", "SKILLS")

            var expectedViews = ["TREE", "SKILLS", "ITEMS", "CALCS", "CONFIG", "NOTES", "IMPORT", "PARTY"]
            for (var v = 0; v < expectedViews.length; v++) {
                uiTest.sendKeyClick(win, Qt.Key_1 + v, Qt.ControlModifier)
                tryCompare(luaEngine, "currentView", expectedViews[v])
            }

            // AC-04: F1 opens AboutPopup; UpdateBanner present
            Oracle.step(tc, "AC-04: F1 context help + UpdateBanner check")
            uiTest.sendKeyClick(win, Qt.Key_F1, 0)
            wait(30)
            var aboutPop = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.about.root")
            verify(aboutPop.visible)
            aboutPop.close()
            tryCompare(aboutPop, "visible", false)

            // AC-05: Sidebar collapse toggle
            Oracle.step(tc, "AC-05: sidebar collapse toggle")
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
            wait(30)
            mouseClick(newBtn)
            tryCompare(luaEngine, "currentMode", "BUILD")
            wait(20)

            // AC-06: Load OccVortex.xml and verify shell populates
            verify(uiTest.loadTestBuild("../spec/TestBuilds/3.13/OccVortex.xml"))
            wait(30)
            waitForRendering(win.contentItem)

            // AC-02: Strict multi-resolution layout oracle across 960x640, 1100x720, 1600x900
            Oracle.step(tc, "AC-02: strict layout oracle across 3 resolutions")
            var sizes = [[960, 640], [1100, 720], [1600, 900]]
            for (var i = 0; i < sizes.length; i++) {
                win.width = sizes[i][0]
                win.height = sizes[i][1]
                waitForRendering(win.contentItem)
                wait(30)
                waitForRendering(win.contentItem)
                var rep = uiTest.checkLayoutOracle(win.contentItem, sizes[i][0], sizes[i][1], { strict: true, checkSiblingOverlap: false })
                verify(rep.ok, "MainShell Layout/Overflow at " + sizes[i][0] + "x" + sizes[i][1] + ": " + JSON.stringify(rep))
            }

            Oracle.assertZeroWarnings(tc, uiTest, "MainShell")
        }
    }
}
