import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.CraftAnointPopup {
        id: dlg
    }

    TestCase {
        id: tc
        name: "CraftAnointPopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            wait(10)
        }

        function test_all_ac() {
            dlg.title = "Anoint Item"
            dlg.st = uiTest.toVariantMap({
                open: true,
                width: 380,
                height: 448,
                controls: {
                    notableDB: {
                        shown: true,
                        building: false,
                        sel: 1,
                        text: "",
                        rows: [
                            { key: 1, label: "^7Charisma (Clear, Golden, Golden)" },
                            { key: 2, label: "^7Whispers of Doom (Black, Golden, Golden)" }
                        ],
                        sub: {
                            sort: { shown: true, enabled: true, list: ["Default", "Full DPS"], sel: 1 },
                            search: { shown: true, enabled: true, text: "" },
                            searchMode: { shown: true, enabled: true, list: ["All", "Name"], sel: 1 }
                        }
                    },
                    save: { shown: true, enabled: true, label: "Anoint VeryLongNotablePassiveNameThatMustClampWidth" },
                    close: { shown: true, enabled: true, label: "Cancel" }
                }
            })
            dlg.open()
            tryCompare(dlg, "visible", true)

            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.anoint.sort")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.anoint.search")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.anoint.searchMode")
            var listBox = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.anoint.notableList")
            var saveBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.anoint.saveBtn")
            var closeBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.anoint.closeBtn")

            compare(listBox.count, 2)
            compare(listBox.selIndex, 0)
            verify(saveBtn.width <= 200) // BUG-24 upper width clamp

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "CraftAnointPopup")

            mouseClick(closeBtn)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "CraftAnointPopup")
        }
    }
}
