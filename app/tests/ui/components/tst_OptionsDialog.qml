import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.OptionsDialog {
        id: dlg
    }

    SignalSpy { id: rejSpy; target: dlg; signalName: "rejected" }

    TestCase {
        id: tc
        name: "OptionsDialogTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            rejSpy.clear()
            wait(10)
        }

        function test_all_ac() {
            dlg.open()
            tryCompare(dlg, "visible", true)
            wait(50)

            verify(dlg.appOpts.length > 0)
            verify(dlg.buildOpts.length > 0)

            var checks = uiTest.findObjectsByPrefix(container.Window.window, "pob.options.check")
            var drops = uiTest.findObjectsByPrefix(container.Window.window, "pob.options.dropdown")
            var sliders = uiTest.findObjectsByPrefix(container.Window.window, "pob.options.slider")
            var fields = uiTest.findObjectsByPrefix(container.Window.window, "pob.options.textField")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.options.saveBtn")
            var cancelBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.options.cancelBtn")

            verify(checks.length > 0)
            verify(drops.length > 0)
            verify(sliders.length > 0)
            verify(fields.length > 0)

            // AC-03: Toggle a live check option then Cancel reverts
            var firstCheck = checks[0]
            var origState = firstCheck.state
            mouseClick(firstCheck, firstCheck.width / 2, firstCheck.height / 2)
            tryCompare(firstCheck, "state", !origState)

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "OptionsDialog")

            mouseClick(cancelBtn)
            tryCompare(dlg, "visible", false)
            compare(rejSpy.count, 1)
            Oracle.assertZeroWarnings(tc, uiTest, "OptionsDialog")
        }
    }
}
