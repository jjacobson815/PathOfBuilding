import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.ToastStack {
        id: stack
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 12
    }

    TestCase {
        id: tc
        name: "ToastStackTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            stack.toasts = []
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, stack, "pob.toaststack.root")
            Oracle.findRequired(tc, uiTest, stack, "pob.toaststack.repeater")
            compare(stack.implicitHeight, 0)

            // AC-02: Stack order reversal with QVariantList
            stack.toasts = uiTest.toVariantList([
                { id: "toast_a", message: "Oldest Toast" },
                { id: "toast_b", message: "Newest Toast" }
            ])
            wait(300)
            compare(stack._stackOrder.length, 2)
            compare(stack._stackOrder[0].id, "toast_b")
            compare(stack._stackOrder[1].id, "toast_a")
            verify(stack.implicitHeight > 0)

            var cards = uiTest.findObjectsByPrefix(stack, "pob.toaststack.toast")
            compare(cards.length, 2)
            compare(cards[0].opacity, 1.0)

            Oracle.assertMultiResLayout(tc, container, stack, uiTest, "ToastStack")
            Oracle.assertZeroWarnings(tc, uiTest, "ToastStack")
        }
    }
}
