import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.MessagePopup {
        id: dlg
        title: "Notice"
        message: "Build imported successfully!"
    }

    SignalSpy { id: accSpy; target: dlg; signalName: "accepted" }

    TestCase {
        id: tc
        name: "MessagePopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            dlg.message = "Build imported successfully!"
            accSpy.clear()
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, dlg, "pob.message.root")
            dlg.open()
            tryCompare(dlg, "visible", true)
            var okBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.message.btn_ok")
            verify(okBtn.visible)

            dlg.message = "^1Critical Error\nLine 2"
            wait(10)
            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "MessagePopup")

            mouseClick(okBtn)
            tryCompare(dlg, "visible", false)
            compare(accSpy.count, 1)

            dlg.open()
            tryCompare(dlg, "visible", true)
            keyClick(Qt.Key_Return)
            tryCompare(dlg, "visible", false)
            compare(accSpy.count, 2)

            Oracle.assertZeroWarnings(tc, uiTest, "MessagePopup")
        }
    }
}
