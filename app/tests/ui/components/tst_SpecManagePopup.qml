import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.SpecManagePopup {
        id: dlg
    }

    TestCase {
        id: tc
        name: "SpecManagePopupTest"
        when: windowShown

        function initTestCase() {
            uiTest.resetEngineForTest()
        }

        function cleanupTestCase() {
            uiTest.resetEngineForTest()
        }

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            wait(10)
        }

        function test_all_ac() {
            dlg.openFresh()
            tryCompare(dlg, "visible", true)

            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.specmanage.root")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.specmanage.btn_new")
            var copyBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.specmanage.btn_copy")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.specmanage.btn_ren")
            var delBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.specmanage.btn_del")
            var upBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.specmanage.btn_up")
            var downBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.specmanage.btn_down")

            verify(dlg.count >= 1)
            verify(!copyBtn.controlEnabled) // selIndex === -1 initially

            // Create second spec via bridge and refresh to test multi-spec boundary states
            luaEngine.invoke("pob_newSpec", ["VeryLongTreeSpecNameToVerifyRightElisionInsideSpecListBox"])
            dlg.refresh()
            wait(10)
            verify(dlg.count >= 2)

            dlg.selIndex = 0
            wait(5)
            verify(copyBtn.controlEnabled)
            verify(delBtn.controlEnabled)
            verify(!upBtn.controlEnabled)
            verify(downBtn.controlEnabled)

            dlg.selIndex = dlg.count - 1
            wait(5)
            verify(upBtn.controlEnabled)
            verify(!downBtn.controlEnabled)

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "SpecManagePopup")

            dlg.close()
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "SpecManagePopup")
        }
    }
}
