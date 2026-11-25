import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.MasteryPopup {
        id: dlg
    }

    SignalSpy { id: selectedSpy; target: dlg; signalName: "selectedEffect" }

    TestCase {
        id: tc
        name: "MasteryPopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            selectedSpy.clear()
            wait(10)
        }

        function test_all_ac() {
            // Invalid node returns false cleanly
            verify(!dlg.openFor(99999999, []))
            verify(!dlg.visible)

            // Populate effects list and open
            dlg.nodeId = 12345
            dlg.effects = uiTest.toVariantList([
                { id: 101, label: "^715% increased maximum Life if there are no Life Modifiers on Equipped Body Armour", selected: false },
                { id: 102, label: "^7+50 to maximum Life", selected: true }
            ])
            dlg.open()
            tryCompare(dlg, "visible", true)
            wait(20)

            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.mastery.root")
            var rows = uiTest.findObjectsByPrefix(container.Window.window, "pob.mastery.row")
            verify(rows.length === 2)
            var cancelBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.mastery.cancel")

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "MasteryPopup")

            mouseClick(cancelBtn)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "MasteryPopup")
        }
    }
}
