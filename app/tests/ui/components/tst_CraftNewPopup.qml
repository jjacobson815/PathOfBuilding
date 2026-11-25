import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.CraftNewPopup {
        id: dlg
    }

    SignalSpy { id: createdSpy; target: dlg; signalName: "created" }

    TestCase {
        id: tc
        name: "CraftNewPopupTest"
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
            createdSpy.clear()
            wait(10)
        }

        function test_all_ac() {
            dlg.openFresh()
            tryCompare(dlg, "visible", true)

            var rarDrop = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftNew.rarityDrop")
            var titleEd = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftNew.titleEdit")
            var typeDrop = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftNew.typeDrop")
            var baseDrop = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftNew.baseDrop")
            var createBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftNew.createBtn")
            var cancelBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftNew.cancelBtn")

            verify(rarDrop.model.length >= 4)
            verify(typeDrop.model.length > 0)
            verify(baseDrop.model.length > 0)

            // AC-02: Title hidden for Normal, visible for Rare
            rarDrop.currentIndex = 0
            wait(5)
            verify(!titleEd.visible)
            rarDrop.currentIndex = 2
            wait(5)
            verify(titleEd.visible)

            // AC-03: Switch type re-populates bases cleanly
            if (typeDrop.model.length > 1) {
                typeDrop.currentIndex = 1
                typeDrop.selected(1)
                wait(10)
                verify(baseDrop.currentIndex >= 0 && baseDrop.currentIndex < baseDrop.model.length)
            }

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "CraftNewPopup")

            // AC-05: Create emits created and closes
            mouseClick(createBtn)
            tryCompare(dlg, "visible", false)
            compare(createdSpy.count, 1)

            // Verify cancel path too
            dlg.openFresh()
            tryCompare(dlg, "visible", true)
            mouseClick(cancelBtn)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "CraftNewPopup")
        }
    }
}
