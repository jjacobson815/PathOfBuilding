import QtQuick
import QtTest
import "qrc:/qml/views" as Views
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Views.ItemsView {
        id: view
        anchors.fill: parent
    }

    TestCase {
        id: tc
        name: "ItemsViewTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            luaEngine.createBuild()
            luaEngine.setActiveView("ITEMS")
            view.refresh()
            mouseMove(container, 1, 1)
            wait(30)
        }

        function cleanup() {
            uiTest.resetEngineForTest()
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, view, "pob.items.drop_set")
            Oracle.findRequired(tc, uiTest, view, "pob.items.btn_manage_set")
            var ws1 = Oracle.findRequired(tc, uiTest, view, "pob.items.btn_weapon_set_1")
            var ws2 = Oracle.findRequired(tc, uiTest, view, "pob.items.btn_weapon_set_2")
            var slotDrops = uiTest.findObjectsByPrefix(view, "pob.items.drop_slot")
            verify(slotDrops.length > 0)
            Oracle.findRequired(tc, uiTest, view, "pob.items.drop_spec")
            Oracle.findRequired(tc, uiTest, view, "pob.items.btn_manage_spec")
            Oracle.findRequired(tc, uiTest, view, "pob.items.list_all_items")
            Oracle.findRequired(tc, uiTest, view, "pob.items.btn_sort")
            Oracle.findRequired(tc, uiTest, view, "pob.items.btn_delete_unused")
            Oracle.findRequired(tc, uiTest, view, "pob.items.btn_delete_all")
            Oracle.findRequired(tc, uiTest, view, "pob.items.btn_delete_item")
            Oracle.findRequired(tc, uiTest, view, "pob.items.panel_db")
            var craftBtn = Oracle.findRequired(tc, uiTest, view, "pob.items.btn_craft_item")
            Oracle.findRequired(tc, uiTest, view, "pob.items.btn_create_custom")

            // AC-04: Weapon Swap Synchronization
            mouseClick(ws2)
            wait(20)
            compare(!!view.st.useSecondWeaponSet, true)
            mouseClick(ws1)
            wait(20)
            compare(!!view.st.useSecondWeaponSet, false)

            // Craft popup opens cleanly and dismisses on Esc
            mouseClick(craftBtn)
            wait(20)
            var craftPopup = uiTest.findObject(view, "pob.craftNew.root")
            if (craftPopup) {
                verify(craftPopup.visible)
                keyClick(Qt.Key_Escape)
                tryCompare(craftPopup, "visible", false)
            }

            Oracle.assertMultiResLayout(tc, container, view, uiTest, "ItemsView")
            Oracle.assertZeroWarnings(tc, uiTest, "ItemsView")
        }
    }
}
