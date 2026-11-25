import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.PartyBufferBox {
        id: box
        x: 20
        y: 20
        width: 320
        title: "Aura Buffs:"
        bufferKey: "auras"
        showAdvanced: false
        hasSummary: true
        summaryText: "Determination\nGrace"
    }

    SignalSpy { id: editSpy; target: box; signalName: "bufferEdited" }

    TestCase {
        id: tc
        name: "PartyBufferBoxTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            box.showAdvanced = false
            box.hasSummary = true
            box.summaryText = "Determination\nGrace"
            box.setBufferText("")
            editSpy.clear()
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, box, "pob.partyBuffer.title")
            var editor = Oracle.findRequired(tc, uiTest, box, "pob.partyBuffer.editor")
            var summary = Oracle.findRequired(tc, uiTest, box, "pob.partyBuffer.summary")

            // AC-01: Summary visible, editor hidden
            verify(summary.visible)
            verify(!editor.visible)

            Oracle.assertMultiResLayout(tc, container, box, uiTest, "PartyBufferBox")

            // AC-02: Advanced mode reveals editor
            box.showAdvanced = true
            wait(10)
            verify(!summary.visible)
            verify(editor.visible)

            // AC-05: setBufferText respects activeFocus
            editor.forceActiveFocus()
            tryCompare(box, "focused", true)
            editor.text = "Grace level=20"
            box.setBufferText("ExternalOverwrite")
            compare(editor.text, "Grace level=20")

            // AC-03 & BUG-06: Debounced emission
            tryCompare(editSpy, "count", 1, 400)
            compare(editSpy.signalArguments[0][0], "auras")
            compare(editSpy.signalArguments[0][1], "Grace level=20")

            Oracle.assertMultiResLayout(tc, container, box, uiTest, "PartyBufferBox Adv")
            Oracle.assertZeroWarnings(tc, uiTest, "PartyBufferBox")
        }
    }
}
