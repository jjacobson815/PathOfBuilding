import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.TreeImportPopup {
        id: dlg
    }

    SignalSpy { id: importedSpy; target: dlg; signalName: "imported" }

    TestCase {
        id: tc
        name: "TreeImportPopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            importedSpy.clear()
            wait(10)
        }

        function test_all_ac() {
            dlg.openFresh()
            tryCompare(dlg, "visible", true)

            var nameIn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.treeImport.nameInput")
            var linkIn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.treeImport.linkInput")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.treeImport.statusMsg")
            var impBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.treeImport.importBtn")
            var canBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.treeImport.cancelBtn")

            verify(!dlg.canImport)
            verify(!impBtn.controlEnabled)

            // BUG-22: Return while !canImport must not import or close
            keyClick(Qt.Key_Return)
            wait(10)
            verify(dlg.visible)
            compare(importedSpy.count, 0)

            // Whitespace-only keeps disabled
            nameIn.text = "   "
            linkIn.text = "   "
            verify(!dlg.canImport)

            // Non-empty enables Import button
            nameIn.text = "Imported Spec"
            linkIn.text = "https://www.pathofbuilding.community/"
            verify(dlg.canImport)
            verify(impBtn.controlEnabled)

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "TreeImportPopup")

            mouseClick(canBtn)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "TreeImportPopup")
        }
    }
}
