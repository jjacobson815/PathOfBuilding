import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    property string lastClickName: ""
    property int tipCalls: 0
    property var mockRec: ({ shown: true, enabled: true, label: "Anoint Charisma" })

    QtObject {
        id: mockCraft
        function rec(name) { return container.mockRec }
        function click(name) { container.lastClickName = name }
        function fillTip(tt, name, idx) {
            container.tipCalls++
            tt.addLine(14, "Preview " + name)
        }
    }

    Widgets.CraftButton {
        id: btn
        x: 40
        y: 40
        width: 150
        craft: mockCraft
        name: "save"
        tip: true
    }

    TestCase {
        id: tc
        name: "CraftButtonTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            btn.craft = mockCraft
            container.lastClickName = ""
            container.tipCalls = 0
            container.mockRec = uiTest.toVariantMap({ shown: true, enabled: true, label: "Anoint Charisma" })
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, btn, "pob.craftButton.root")
            compare(btn.label, "Anoint Charisma")
            verify(btn.visible)
            verify(btn.controlEnabled)

            // AC-03: Click dispatches craft.click(name)
            mouseClick(btn)
            compare(container.lastClickName, "save")

            // AC-04: Hover tooltip triggers fillTip
            mouseMove(btn, btn.width / 2, btn.height / 2)
            wait(20)
            verify(container.tipCalls >= 1)

            // BUG-16 & AC-02: Disabled click suppressed
            container.lastClickName = ""
            container.mockRec = uiTest.toVariantMap({ shown: true, enabled: false, label: "Disabled" })
            wait(5)
            verify(!btn.controlEnabled)
            mouseClick(btn)
            compare(container.lastClickName, "")

            // Null craft safety
            btn.craft = null
            wait(5)
            verify(!btn.visible)

            // Restore visible for multi-res layout check
            btn.craft = mockCraft
            container.mockRec = uiTest.toVariantMap({ shown: true, enabled: true, label: "Save" })
            wait(5)
            Oracle.assertMultiResLayout(tc, container, btn, uiTest, "CraftButton")
            Oracle.assertZeroWarnings(tc, uiTest, "CraftButton")
        }
    }
}
