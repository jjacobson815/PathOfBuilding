import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.CraftCruciblePopup {
        id: dlg
    }

    TestCase {
        id: tc
        name: "CraftCruciblePopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            wait(10)
        }

        function test_all_ac() {
            dlg.title = "Add Crucible Modifier to Item"
            dlg.st = uiTest.toVariantMap({
                open: true,
                width: 710,
                height: 185,
                controls: {
                    modSelectNode1: { shown: true, enabled: true, list: ["None", "10% increased Attack Speed"], sel: 1 },
                    modSelectNode2: { shown: true, enabled: true, list: ["None", "+0.4% Crit Chance"], sel: 1 },
                    modSelectNode3: { shown: true, enabled: true, list: ["None", "Adds 15 to 25 Cold Damage"], sel: 1 },
                    modSelectNode4: { shown: true, enabled: true, list: ["None", "Double Damage"], sel: 1 },
                    modSelectNode5: { shown: true, enabled: true, list: ["None", "Voidforge Convert"], sel: 1 },
                    save: { shown: true, enabled: true, label: "Save" },
                    close: { shown: true, enabled: true, label: "Cancel" }
                }
            })
            dlg.open()
            tryCompare(dlg, "visible", true)

            for (var n = 1; n <= 5; n++) {
                var nd = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCrucible.node" + n)
                verify(nd.visible)
            }
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCrucible.saveBtn")
            var closeBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCrucible.closeBtn")

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "CraftCruciblePopup")

            mouseClick(closeBtn)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "CraftCruciblePopup")
        }
    }
}
