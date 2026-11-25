import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.NewFolderPopup {
        id: dlg
        title: "New Folder"
    }

    SignalSpy { id: accSpy; target: dlg; signalName: "accepted" }

    TestCase {
        id: tc
        name: "NewFolderPopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            dlg.text = ""
            accSpy.clear()
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, dlg, "pob.newfolder.root")
            compare(dlg.prompt, "Enter folder name:")
            compare(dlg.confirmLabel, "Create")

            dlg.open()
            tryCompare(dlg, "visible", true)

            dlg.text = "League_3.24"
            wait(10)
            verify(dlg.confirmEnabled)

            dlg.text = "Build/Test"
            wait(10)
            verify(!dlg.confirmEnabled)

            dlg.text = "Test:1"
            wait(10)
            verify(!dlg.confirmEnabled)

            dlg.text = "Bad\nName"
            wait(10)
            verify(!dlg.confirmEnabled)

            dlg.text = "ValidFolder"
            wait(10)
            verify(dlg.confirmEnabled)
            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "NewFolderPopup")

            var btnCreate = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.textpopup.btn_confirm")
            mouseClick(btnCreate)
            tryCompare(dlg, "visible", false)
            compare(accSpy.count, 1)
            compare(dlg.text, "ValidFolder")

            Oracle.assertZeroWarnings(tc, uiTest, "NewFolderPopup")
        }
    }
}
