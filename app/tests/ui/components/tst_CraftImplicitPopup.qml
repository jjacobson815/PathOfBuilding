import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.CraftImplicitPopup {
        id: dlg
    }

    TestCase {
        id: tc
        name: "CraftImplicitPopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            wait(10)
        }

        function test_all_ac() {
            dlg.title = "Add Implicit to Item"
            dlg.st = uiTest.toVariantMap({
                open: true,
                width: 710,
                height: 130,
                controls: {
                    source: { shown: true, enabled: true, list: ["Searing Exarch", "Custom"], sel: 1 },
                    sortLabel: { shown: true, label: "^7Sort by:" },
                    sort: { shown: true, enabled: true, list: ["Default", "DPS"], sel: 1 },
                    modGroupSelectLabel: { shown: true, label: "^7Mod Type:" },
                    modGroupSelect: { shown: true, enabled: true, list: ["Attack Modifiers"], sel: 1 },
                    modSelect: { shown: true, enabled: true, list: ["(15-17)% increased Attack Speed"], sel: 1 },
                    custom: { shown: false, text: "" },
                    save: { shown: true, enabled: true, label: "Save" },
                    close: { shown: true, enabled: true, label: "Cancel" }
                }
            })
            dlg.open()
            tryCompare(dlg, "visible", true)

            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftImplicit.source")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftImplicit.sort")
            var grpDrop = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftImplicit.groupDrop")
            var modDrop = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftImplicit.modDrop")
            var custEdit = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftImplicit.customEdit")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftImplicit.saveBtn")
            var closeBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftImplicit.closeBtn")

            verify(!dlg.isCustom)
            verify(grpDrop.visible)
            verify(modDrop.visible)
            verify(!custEdit.visible)

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "CraftImplicitPopup")

            // AC-02: Custom mode hides modSelect/groupDrop & shows customEdit
            dlg.st = uiTest.toVariantMap({
                open: true,
                width: 710,
                height: 105,
                controls: {
                    source: { shown: true, enabled: true, list: ["Searing Exarch", "Custom"], sel: 2 },
                    sortLabel: { shown: false, label: "" },
                    sort: { shown: false },
                    modGroupSelectLabel: { shown: false, label: "" },
                    modGroupSelect: { shown: false },
                    modSelect: { shown: true, enabled: true, list: [], sel: 1 }, // intentionally true to test BUG-15 guard
                    custom: { shown: true, enabled: true, text: "Cannot be Frozen" },
                    save: { shown: true, enabled: true, label: "Save" },
                    close: { shown: true, enabled: true, label: "Cancel" }
                }
            })
            wait(10)
            verify(dlg.isCustom)
            verify(!modDrop.visible) // BUG-15 guard verified
            verify(custEdit.visible)

            mouseClick(closeBtn)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "CraftImplicitPopup")
        }
    }
}
