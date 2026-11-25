import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.ConfirmPopup {
        id: dlg
        title: "Confirm"
        message: "Confirm deletion?"
    }

    SignalSpy { id: accSpy; target: dlg; signalName: "accepted" }
    SignalSpy { id: rejSpy; target: dlg; signalName: "rejected" }
    SignalSpy { id: extSpy; target: dlg; signalName: "extraClicked" }

    TestCase {
        id: tc
        name: "ConfirmPopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            dlg.extraLabel = ""
            accSpy.clear()
            rejSpy.clear()
            extSpy.clear()
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, dlg, "pob.confirm.root")
            dlg.open()
            tryCompare(dlg, "visible", true)

            var btnConf = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.confirm.btn_confirm")
            var btnExt = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.confirm.btn_extra")
            var btnCan = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.confirm.btn_cancel")
            verify(!btnExt.visible)
            verify(btnConf.visible)
            verify(btnCan.visible)

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "ConfirmPopup")

            // AC-03: 3-button mode
            dlg.extraLabel = "Retry"
            wait(10)
            verify(btnExt.visible)
            mouseClick(btnExt)
            compare(extSpy.count, 1)

            // AC-04: Enter accepts
            keyClick(Qt.Key_Return)
            tryCompare(dlg, "visible", false)
            compare(accSpy.count, 1)

            // AC-05: Escape rejects
            dlg.open()
            tryCompare(dlg, "visible", true)
            keyClick(Qt.Key_Escape)
            tryCompare(dlg, "visible", false)
            compare(rejSpy.count, 1)

            Oracle.assertZeroWarnings(tc, uiTest, "ConfirmPopup")
        }
    }
}
