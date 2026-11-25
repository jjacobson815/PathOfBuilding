import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.ItemDBPanel {
        id: panel
        x: 20
        y: 20
        width: 360
        height: 360
    }

    TestCase {
        id: tc
        name: "ItemDBPanelTest"
        when: windowShown

        function initTestCase() {
            uiTest.resetEngineForTest()
        }

        function cleanupTestCase() {
            uiTest.resetEngineForTest()
        }

        function init() {
            uiTest.resetWarnings()
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            var selectDB = Oracle.findRequired(tc, uiTest, panel, "pob.itemDB.selectDB")
            Oracle.findRequired(tc, uiTest, panel, "pob.itemDB.slotDrop")
            Oracle.findRequired(tc, uiTest, panel, "pob.itemDB.typeDrop")
            var sortDrop = Oracle.findRequired(tc, uiTest, panel, "pob.itemDB.sortDrop")
            Oracle.findRequired(tc, uiTest, panel, "pob.itemDB.leagueDrop")
            var searchEdit = Oracle.findRequired(tc, uiTest, panel, "pob.itemDB.searchEdit")
            Oracle.findRequired(tc, uiTest, panel, "pob.itemDB.dbList")

            // AC-01: Default Uniques mode
            verify(panel.isUnique)
            compare(panel.listTop, 104)
            verify(sortDrop.visible)

            // AC-02: Switch to Rare Templates
            selectDB.currentIndex = 1
            selectDB.selected(1)
            wait(20)
            verify(!panel.isUnique)
            compare(panel.listTop, 64)
            verify(!sortDrop.visible)

            // Switch back to Uniques
            selectDB.currentIndex = 0
            selectDB.selected(0)
            wait(20)
            verify(panel.isUnique)

            // AC-05: focusSearch focuses searchEdit
            panel.focusSearch()
            tryCompare(searchEdit, "editing", true)
            searchEdit.edited("Tabula")
            wait(20)

            Oracle.assertMultiResLayout(tc, container, panel, uiTest, "ItemDBPanel")
            Oracle.assertZeroWarnings(tc, uiTest, "ItemDBPanel")
        }
    }
}
