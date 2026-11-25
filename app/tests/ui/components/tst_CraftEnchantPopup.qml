import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.CraftEnchantPopup {
        id: dlg
    }

    TestCase {
        id: tc
        name: "CraftEnchantPopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            wait(10)
        }

        function test_all_ac() {
            dlg.title = "Enchant Item"
            dlg.st = uiTest.toVariantMap({
                open: true,
                width: 605,
                height: 130,
                controls: {
                    skill: { shown: true, enabled: true, list: ["Lightning Strike", "Cyclone"], sel: 1 },
                    allSkills: { shown: true, enabled: true, state: false },
                    enchantmentSource: { shown: true, enabled: true, list: ["Eternal Labyrinth"], sel: 1 },
                    sort: { shown: true, enabled: true, list: ["Default", "Full DPS"], sel: 1 },
                    enchantment: { shown: true, enabled: true, list: ["40% increased Lightning Strike Damage"], sel: 1 },
                    save: { shown: true, enabled: true, label: "Save" },
                    remove: { shown: true, enabled: true, label: "Remove" },
                    close: { shown: true, enabled: true, label: "Cancel" }
                }
            })
            dlg.open()
            tryCompare(dlg, "visible", true)

            var skillD = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.enchant.skill")
            var allChk = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.enchant.allSkills")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.enchant.source")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.enchant.sort")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.enchant.enchantment")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.enchant.save")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.enchant.remove")
            var closeBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.enchant.close")

            verify(skillD.visible)
            verify(allChk.visible)

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "CraftEnchantPopup")

            // AC-02: Non-helmet hides skill & allSkills
            dlg.st = uiTest.toVariantMap({
                open: true,
                width: 605,
                height: 130,
                controls: {
                    skill: { shown: false },
                    allSkills: { shown: false },
                    enchantmentSource: { shown: true, enabled: true, list: ["Lab"], sel: 1 },
                    sort: { shown: true, enabled: true, list: ["Default"], sel: 1 },
                    enchantment: { shown: true, enabled: true, list: ["16% increased Attack Speed"], sel: 1 },
                    save: { shown: true, enabled: true, label: "Save" },
                    remove: { shown: true, enabled: false, label: "Remove" },
                    close: { shown: true, enabled: true, label: "Cancel" }
                }
            })
            wait(10)
            verify(!skillD.visible)
            verify(!allChk.visible)

            mouseClick(closeBtn)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "CraftEnchantPopup")
        }
    }
}
