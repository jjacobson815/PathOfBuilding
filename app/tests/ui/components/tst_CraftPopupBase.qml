import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.CraftPopupBase {
        id: dlg
        Item {
            implicitWidth: 360
            implicitHeight: dlg.frameH
        }
    }

    TestCase {
        id: tc
        name: "CraftPopupBaseTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            wait(10)
        }

        function test_all_ac() {
            // Invalid openCraft clears st safely
            dlg.st = uiTest.toVariantMap({ open: true, height: 220 })
            verify(!dlg.openCraft("nonexistent_kind_xyz", 1))
            compare(dlg.frameH, 100)

            // Populate session descriptor & test dotted rec() + dynamic frameH
            dlg.title = "Craft Session"
            dlg.st = uiTest.toVariantMap({
                open: true,
                width: 360,
                height: 240,
                controls: {
                    notableDB: {
                        shown: true,
                        sub: {
                            search: { shown: true, text: "Charisma" }
                        }
                    },
                    missingParent: null
                }
            })
            dlg.open()
            tryCompare(dlg, "visible", true)

            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftBase.root")
            compare(dlg.frameH, 240)
            compare(dlg.rec("notableDB.search").text, "Charisma")
            compare(dlg.rec("missingParent.child").text, undefined)

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "CraftPopupBase")

            keyClick(Qt.Key_Escape)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "CraftPopupBase")
        }
    }
}
