import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.SaveAsPopup {
        id: dlg
    }

    TestCase {
        id: tc
        name: "SaveAsPopupTest"
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
            dlg.openForCurrentBuild()
            tryCompare(dlg, "visible", true)

            var nameEdit = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.saveAs.nameEdit")
            var valLbl = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.saveAs.validationLabel")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.saveAs.path")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.saveAs.newFolder")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.saveAs.sortDrop")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.saveAs.folderList")
            var saveBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.saveAs.saveBtn")
            var cancelBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.saveAs.cancelBtn")

            // BUG-03 regression: QVariantList folders
            dlg.folders = uiTest.toVariantList([{ name: "VeryLongFolderNameThatShouldElideRightSafelyWithoutOverflow", subPath: "VeryLongFolderName/" }])
            wait(10)
            compare(dlg.folderCount, 1)

            // AC-05: invalid / empty (whitespace-only) disables save
            nameEdit.text = "   "
            dlg.recheck("   ")
            wait(10)
            verify(!dlg.canSave)
            verify(valLbl.visible)
            verify(!saveBtn.controlEnabled)

            // Valid name enables save
            nameEdit.text = "__QuickTestNovelBuild__"
            dlg.recheck("__QuickTestNovelBuild__")
            wait(10)
            verify(dlg.canSave)
            verify(saveBtn.controlEnabled)

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "SaveAsPopup")

            mouseClick(cancelBtn)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "SaveAsPopup")
        }
    }
}
