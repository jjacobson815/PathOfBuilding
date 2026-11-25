import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.Toast {
        id: toast
        x: 20
        y: 20
        toastId: "toast_1"
        message: "Build Saved Successfully\nSaved to builds/Test.xml"
    }

    SignalSpy { id: dismissSpy; target: toast; signalName: "dismissRequested" }

    TestCase {
        id: tc
        name: "ToastTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            toast.toastId = "toast_1"
            toast.message = "Build Saved Successfully\nSaved to builds/Test.xml"
            dismissSpy.clear()
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, toast, "pob.toast.card")
            var title = Oracle.findRequired(tc, uiTest, toast, "pob.toast.title")
            var body = Oracle.findRequired(tc, uiTest, toast, "pob.toast.body")
            var btn = Oracle.findRequired(tc, uiTest, toast, "pob.toast.dismiss")

            compare(toast.implicitWidth, 312)
            compare(title.sourceText, "Build Saved Successfully")
            verify(body.visible)
            compare(body.sourceText, "Saved to builds/Test.xml")

            // Single-line hides body
            toast.message = "Single Line Alert"
            wait(10)
            compare(title.sourceText, "Single Line Alert")
            verify(!body.visible)

            // Multiline joins lines 2..N
            toast.message = "Line 1\nLine 2\nLine 3"
            wait(10)
            compare(body.sourceText, "Line 2\nLine 3")

            mouseClick(btn)
            compare(dismissSpy.count, 1)

            Oracle.assertMultiResLayout(tc, container, toast, uiTest, "Toast")
            Oracle.assertZeroWarnings(tc, uiTest, "Toast")
        }
    }
}
