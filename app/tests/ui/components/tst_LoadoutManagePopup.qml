import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.LoadoutManagePopup {
        id: dlg
    }

    TestCase {
        id: tc
        name: "LoadoutManagePopupTest"
        when: windowShown

        function initTestCase() {
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

            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.loadouts.newBtn")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.loadouts.renameBtn")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.loadouts.copyBtn")
            var delBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.loadouts.deleteBtn")
            var customBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.loadouts.customBtn")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.loadouts.listView")
            var upBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.loadouts.upBtn")
            var downBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.loadouts.downBtn")
            var doneBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.loadouts.doneBtn")

            // BUG-01 regression: real QVariantList values populate count > 0
            verify(dlg.count > 0)
            verify(dlg._trees.length > 0)
            verify(dlg._skills.length > 0)
            verify(dlg._items.length > 0)
            verify(dlg._configs.length > 0)

            // Synthetic QVariantList check
            dlg.rows = uiTest.toVariantList([
                { title: "Default", fullName: "Default", display: "Default (Current)" },
                { title: "Boss", fullName: "Boss", display: "Boss" }
            ])
            dlg.selIndex = 0
            wait(10)
            compare(dlg.count, 2)
            verify(!upBtn.controlEnabled)
            verify(downBtn.controlEnabled)
            verify(dlg._isDuplicateName("Default"))
            verify(!dlg._isDuplicateName("BrandNewLoadout"))

            // Open custom sub-popup
            mouseClick(customBtn)
            wait(15)
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.loadouts.customCreate")
            keyClick(Qt.Key_Escape)
            wait(15)

            dlg.refresh()
            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "LoadoutManagePopup")

            mouseClick(doneBtn)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "LoadoutManagePopup")
        }
    }
}
