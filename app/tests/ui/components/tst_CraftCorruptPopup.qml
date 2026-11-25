import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.CraftCorruptPopup {
        id: dlg
    }

    TestCase {
        id: tc
        name: "CraftCorruptPopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            wait(10)
        }

        function test_all_ac() {
            dlg.title = "Corrupted Item"
            dlg.st = uiTest.toVariantMap({
                open: true,
                width: 605,
                height: 220,
                controls: {
                    implicits: { shown: true, enabled: true, label: "Implicits" },
                    rolls: { shown: true, enabled: true, label: "Roll Ranges" },
                    source: { shown: true, enabled: true, list: ["Corrupted", "Scourge"], sel: 1 },
                    sort: { shown: true, enabled: true, list: ["Default", "DPS"], sel: 1 },
                    implicitCannotBeChangedLabel: { shown: false, label: "" },
                    implicit1Label: { shown: true, label: "Implicit #1:" },
                    implicit1: { shown: true, enabled: true, list: ["None", "+1 to Socketed Gems"], sel: 1 },
                    implicit2Label: { shown: true, label: "Implicit #2:" },
                    implicit2: { shown: true, enabled: true, list: ["None", "(4-6)% increased Life"], sel: 1 },
                    implicit3Label: { shown: false, label: "" },
                    implicit3: { shown: false },
                    implicit4Label: { shown: false, label: "" },
                    implicit4: { shown: false },
                    rollRangeSlider1: { shown: false, val: 1.0 },
                    rollRangeLabel1: { label: "+100 to maximum Life" },
                    rollRangeValue1: { label: "1.00" },
                    save: { shown: true, enabled: true, label: "Save" },
                    close: { shown: true, enabled: true, label: "Cancel" }
                }
            })
            dlg.open()
            tryCompare(dlg, "visible", true)

            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCorrupt.implicits")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCorrupt.rolls")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCorrupt.source")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCorrupt.sort")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCorrupt.implicit1")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCorrupt.implicit2")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCorrupt.saveBtn")
            var closeBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCorrupt.closeBtn")

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "CraftCorruptPopup")

            // Switch to Roll Ranges mock state and verify slider & rollRows binding
            dlg.st = uiTest.toVariantMap({
                open: true,
                width: 605,
                height: 220,
                controls: {
                    implicits: { shown: true, enabled: true, label: "Implicits" },
                    rolls: { shown: true, enabled: true, label: "Roll Ranges" },
                    source: { shown: false },
                    sort: { shown: false },
                    implicitCannotBeChangedLabel: { shown: false, label: "" },
                    rollRangeSlider1: { shown: true, val: 0.5 },
                    rollRangeLabel1: { label: "+100 to maximum Life" },
                    rollRangeValue1: { label: "1.00" },
                    save: { shown: true, enabled: true, label: "Save" },
                    close: { shown: true, enabled: true, label: "Cancel" }
                }
            })
            wait(20)
            compare(dlg.rollCount, 1)
            var rollSlider = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.craftCorrupt.rollSlider")
            verify(rollSlider.visible)

            mouseClick(closeBtn)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "CraftCorruptPopup")
        }
    }
}
