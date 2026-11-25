import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.TextInputPopup {
        id: dlg
        title: "Rename"
        prompt: "Name:"
    }

    SignalSpy { id: accSpy; target: dlg; signalName: "accepted" }
    SignalSpy { id: rejSpy; target: dlg; signalName: "rejected" }

    TestCase {
        id: tc
        name: "TextInputPopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            dlg.text = ""
            accSpy.clear()
            rejSpy.clear()
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, dlg, "pob.textpopup.root")
            dlg.open()
            tryCompare(dlg, "visible", true)
            var inp = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.textpopup.input")
            var btnOk = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.textpopup.btn_confirm")
            var btnCancel = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.textpopup.btn_cancel")

            tryCompare(inp, "activeFocus", true)
            verify(!dlg.confirmEnabled)

            // AC-02: whitespace-only cannot accept
            dlg.text = "   "
            wait(10)
            verify(!dlg.confirmEnabled)
            keyClick(Qt.Key_Return)
            wait(15)
            verify(dlg.visible)
            compare(accSpy.count, 0)

            // AC-03: valid text accepts
            dlg.text = "New Spec"
            wait(10)
            verify(dlg.confirmEnabled)
            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "TextInputPopup")
            mouseClick(btnOk)
            tryCompare(dlg, "visible", false)
            compare(accSpy.count, 1)

            // AC-05: cancel rejects
            dlg.open()
            tryCompare(dlg, "visible", true)
            mouseClick(btnCancel)
            tryCompare(dlg, "visible", false)
            compare(rejSpy.count, 1)

            Oracle.assertZeroWarnings(tc, uiTest, "TextInputPopup")
        }
    }
}
