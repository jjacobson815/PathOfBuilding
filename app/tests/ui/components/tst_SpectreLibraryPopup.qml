import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.SpectreLibraryPopup {
        id: dlg
    }

    TestCase {
        id: tc
        name: "SpectreLibraryPopupTest"
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

            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.spectres.removeBtn")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.spectres.buildList")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.spectres.addBtn")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.spectres.searchEdit")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.spectres.searchMode")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.spectres.sortMode")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.spectres.corpseCheck")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.spectres.showAllCheck")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.spectres.availList")
            var gemEdit = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.spectres.gemLevel")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.spectres.saveBtn")

            // BUG-02 & BUG-09 regressions
            verify(dlg.availCount > 0)
            verify(dlg.categories.length === 6)
            compare(dlg.fileUrl("C:\\repo\\icon.png"), "file:///C:/repo/icon.png")

            // Category toggle filters count
            var beforeCount = dlg.filteredCount
            var cats = uiTest.findObjectsByPrefix(container.Window.window, "pob.spectres.catToggle")
            compare(cats.length, 6)
            mouseClick(cats[cats.length - 1])
            wait(15)
            verify(dlg.filteredCount <= beforeCount)

            // AC-05: Gem level clamping 55 -> 40
            gemEdit.text = "55"
            gemEdit.committed("55")
            wait(10)
            compare(dlg.gemLevel, 40)
            compare(gemEdit.text, "40")

            waitForRendering(container)
            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "SpectreLibraryPopup")

            keyClick(Qt.Key_Escape)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "SpectreLibraryPopup")
        }
    }
}
