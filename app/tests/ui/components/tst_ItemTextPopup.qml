import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.ItemTextPopup {
        id: dlg
    }

    TestCase {
        id: tc
        name: "ItemTextPopupTest"
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
            dlg.openFor(true)
            tryCompare(dlg, "visible", true)
            wait(20)

            var rar = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.itemText.rarity")
            var area = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.itemText.area")
            var saveBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.itemText.saveBtn")
            var cancelBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.itemText.cancelBtn")

            verify(rar.width >= 130)

            // AC-04: Invalid text disables Save
            area.text = "Not A Valid Item At All"
            wait(250)
            verify(!dlg.valid)
            verify(!saveBtn.controlEnabled)

            // AC-02 & BUG-05: Valid text + immediate _save() before debounce timer fires
            area.text = "Rarity: RARE\nTest Jewels\nCobalt Jewel\n--------\n7% increased maximum Life"
            dlg._save()
            tryCompare(dlg, "visible", false)

            // Re-open and test Cancel
            dlg.openFor(true)
            tryCompare(dlg, "visible", true)
            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "ItemTextPopup")

            mouseClick(cancelBtn)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "ItemTextPopup")
        }
    }
}
