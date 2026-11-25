import QtQuick
import QtQuick.Controls as QC
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.ConversionPopup {
        id: dlg
        liveDisplay: "3.30"
        buildName: "LegacyBuild"
    }

    SignalSpy { id: decSpy; target: dlg; signalName: "declined" }

    TestCase {
        id: tc
        name: "ConversionPopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            decSpy.clear()
            wait(10)
        }

        function test_all_ac() {
            dlg.open()
            tryCompare(dlg, "visible", true)

            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.conversion.infoText")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.conversion.warningText")
            var convBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.conversion.convertBtn")
            var cancelBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.conversion.cancelBtn")

            compare(convBtn.label, "Convert to 3.30")
            compare(dlg.closePolicy, QC.Popup.NoAutoClose)

            // AC-05: Escape does NOT close dialog
            keyClick(Qt.Key_Escape)
            wait(20)
            verify(dlg.visible)

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "ConversionPopup")

            // AC-04: Cancel declines
            mouseClick(cancelBtn)
            tryCompare(dlg, "visible", false)
            compare(decSpy.count, 1)
            Oracle.assertZeroWarnings(tc, uiTest, "ConversionPopup")
        }
    }
}
