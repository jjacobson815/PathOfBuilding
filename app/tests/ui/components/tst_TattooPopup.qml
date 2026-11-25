import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.TattooPopup {
        id: dlg
    }

    SignalSpy { id: changedSpy; target: dlg; signalName: "changed" }

    TestCase {
        id: tc
        name: "TattooPopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            changedSpy.clear()
            wait(10)
        }

        function test_all_ac() {
            // AC-01: Initial mount defaults
            compare(dlg.nodeId, -1)
            compare(dlg.title, "Replace Modifier of Node")

            // Open with eligible tattoos populated directly for deterministic testing
            var modDrop = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.tattoo.mod_drop")
            var addBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.tattoo.btn_add")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.tattoo.root")
            var resetBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.tattoo.btn_reset")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.tattoo.btn_count")
            var legChk = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.tattoo.chk_leg")

            // Empty options disables Add button
            dlg.tstate = uiTest.toVariantMap({ options: [], showLegacy: false, tattooCountStr: "0", tattooLines: [] })
            dlg.open()
            tryCompare(dlg, "visible", true)
            verify(!addBtn.controlEnabled)

            // Populated options with long description wrapping
            var opts = uiTest.toVariantList([
                { name: "Tattoo of the Ramako Fleetfoot", descriptions: ["Replaces +10 Dexterity", "2% increased Movement Speed with a very long reminder description string that wraps beyond 400px cleanly."] }
            ])
            dlg.tstate = uiTest.toVariantMap({ options: opts, defaultIndex: 1, showLegacy: false, tattooCountStr: "1", tattooLines: ["1x Ramako Fleetfoot"] })
            modDrop.model = dlg.options
            modDrop.currentIndex = 0
            wait(10)
            verify(addBtn.controlEnabled)

            // Toggle legacy checkbox
            mouseClick(legChk)
            wait(10)

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "TattooPopup")

            // AC-04: Reset Node dispatches and emits changed
            mouseClick(resetBtn)
            tryCompare(dlg, "visible", false)
            compare(changedSpy.count, 1)

            Oracle.assertZeroWarnings(tc, uiTest, "TattooPopup")
        }
    }
}
