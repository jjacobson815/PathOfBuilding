import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.CraftCustomPopup {
        id: dlg
    }

    TestCase {
        id: tc
        name: "CraftCustomPopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            wait(10)
        }

        function test_all_ac() {
            dlg.title = "Add Modifier to Item"
            dlg.st = uiTest.toVariantMap({
                open: true,
                width: 710,
                height: 105,
                controls: {
                    source: { shown: true, enabled: true, list: ["Crafting Bench", "Custom"], sel: 1 },
                    sortLabel: { shown: true, label: "^7Sort by:" },
                    sort: { shown: true, enabled: true, list: ["Default", "DPS"], sel: 1 },
                    modSelect: { shown: true, enabled: true, list: ["(21-25)% increased Spell Damage"], sel: 1 },
                    custom: { shown: false, text: "" },
                    save: { shown: true, enabled: true, label: "Save" },
                    close: { shown: true, enabled: true, label: "Cancel" }
                }
            })
            dlg.open()
            tryCompare(dlg, "visible", true)

            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCustom.source")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCustom.sort")
            var modDrop = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCustom.modDrop")
            var custEdit = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCustom.customEdit")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCustom.saveBtn")
            var closeBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCustom.closeBtn")

            verify(!dlg.isCustom)
            verify(modDrop.visible)
            verify(!custEdit.visible)

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "CraftCustomPopup")

            // AC-02: Switch to Custom mode
            dlg.st = uiTest.toVariantMap({
                open: true,
                width: 710,
                height: 105,
                controls: {
                    source: { shown: true, enabled: true, list: ["Crafting Bench", "Custom"], sel: 2 },
                    sortLabel: { shown: true, label: "^7Sort by:" },
                    sort: { shown: false },
                    modSelect: { shown: true, enabled: true, list: [], sel: 1 }, // test BUG-15 mutually exclusive guard
                    custom: { shown: true, enabled: true, text: "+30% to Fire Resistance" },
                    save: { shown: true, enabled: true, label: "Save" },
                    close: { shown: true, enabled: true, label: "Cancel" }
                }
            })
            wait(10)
            verify(dlg.isCustom)
            verify(!modDrop.visible)
            verify(custEdit.visible)

            mouseClick(closeBtn)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "CraftCustomPopup")
        }
    }
}
