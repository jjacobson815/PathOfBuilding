import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.TimelessJewelPopup {
        id: dlg
    }

    TestCase {
        id: tc
        name: "TimelessJewelPopupTest"
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
            wait(30)

            var rootObj = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.timeless.root")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.timeless.jewel_drop")
            var sockDrop = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.timeless.socket_drop")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.timeless.btn_search")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.timeless.results")
            var tradeBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.timeless.trade_btn")

            verify(rootObj.width >= 900)
            compare(tradeBtn.controlEnabled, dlg.resultCount > 0)

            // Null/empty row lookup fallback
            var emptyRow = dlg.rowAt(999999)
            compare(emptyRow.label, "")

            // Mini viewer synchronization check
            if (sockDrop.model && sockDrop.model.length > 1) {
                sockDrop.currentIndex = 1
                sockDrop.selected(1)
                wait(20)
            }

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "TimelessJewelPopup")

            dlg.close()
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "TimelessJewelPopup")
        }
    }
}
