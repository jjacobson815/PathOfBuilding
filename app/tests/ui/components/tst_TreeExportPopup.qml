import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.TreeExportPopup {
        id: dlg
    }

    TestCase {
        id: tc
        name: "TreeExportPopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            wait(10)
        }

        function test_all_ac() {
            dlg.openFresh()
            tryCompare(dlg, "visible", true)

            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.treeexport.root")
            var linkIn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.treeexport.input")
            var shrinkBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.treeexport.shrink")
            var copyBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.treeexport.copy")
            var doneBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.treeexport.done")

            verify(linkIn.text.indexOf("http") === 0)
            verify(shrinkBtn.controlEnabled)
            verify(copyBtn.controlEnabled)

            mouseClick(copyBtn)
            wait(10)

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "TreeExportPopup")

            mouseClick(doneBtn)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "TreeExportPopup")
        }
    }
}
