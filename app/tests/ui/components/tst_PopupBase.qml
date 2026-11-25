import QtQuick
import QtQuick.Controls
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.PopupBase {
        id: dlg
        title: "Test Popup"
        Item {
            implicitWidth: 200
            implicitHeight: 100
            Widgets.PopupButton { label: "Inner"; anchors.centerIn: parent }
        }
    }

    SignalSpy { id: accSpy; target: dlg; signalName: "accepted" }
    SignalSpy { id: rejSpy; target: dlg; signalName: "rejected" }

    TestCase {
        id: tc
        name: "PopupBaseTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            dlg.acceptOnEnter = true
            accSpy.clear()
            rejSpy.clear()
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, dlg, "pob.popup.root")
            verify(dlg.modal)
            verify(!dlg.visible)

            dlg.open()
            tryCompare(dlg, "visible", true)
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.popup.title")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.popup.scope")
            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "PopupBase")

            // AC-03: Escape closes & rejects
            keyClick(Qt.Key_Escape)
            tryCompare(dlg, "visible", false)
            compare(rejSpy.count, 1)

            // AC-04: Enter accepts when acceptOnEnter: true
            dlg.open()
            tryCompare(dlg, "visible", true)
            keyClick(Qt.Key_Return)
            tryCompare(dlg, "visible", false)
            compare(accSpy.count, 1)

            // AC-05: Enter ignored when acceptOnEnter: false
            dlg.acceptOnEnter = false
            dlg.open()
            tryCompare(dlg, "visible", true)
            keyClick(Qt.Key_Return)
            wait(20)
            verify(dlg.visible)
            compare(accSpy.count, 1)
            dlg.close()

            Oracle.assertZeroWarnings(tc, uiTest, "PopupBase")
        }
    }
}
