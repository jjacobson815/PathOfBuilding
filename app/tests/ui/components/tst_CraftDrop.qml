import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    property var lastSet: null
    property var mockRec: ({ shown: true, enabled: true, list: ["Option A", "Option B", "Option C", "Option D"], sel: 2 })

    QtObject {
        id: mockCraft
        function rec(name) { return container.mockRec }
        function set(name, val) { container.lastSet = [name, val] }
        function fillTip(tt, name, idx) { tt.addLine(14, "Row " + idx) }
    }

    Widgets.CraftDrop {
        id: drop
        x: 40
        y: 40
        width: 220
        height: 18
        craft: mockCraft
        name: "modSelect"
    }

    TestCase {
        id: tc
        name: "CraftDropTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            drop.craft = mockCraft
            container.lastSet = null
            container.mockRec = uiTest.toVariantMap({ shown: true, enabled: true, list: ["Option A", "Option B", "Option C", "Option D"], sel: 2 })
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, drop, "pob.craftDrop.root")
            compare(drop.model.length, 4)
            compare(drop.currentIndex, 1)

            // AC-03: 1-based index dispatch
            drop.selected(3)
            verify(container.lastSet !== null)
            compare(container.lastSet[0], "modSelect")
            compare(container.lastSet[1], 4)

            // AC-05: Empty list & QVariantList fallback
            container.mockRec = uiTest.toVariantMap({ shown: true, enabled: true, list: [] })
            wait(5)
            compare(drop.model.length, 0)
            compare(drop.currentIndex, -1)

            container.mockRec = uiTest.toVariantMap({ shown: true, enabled: true, list: ["Option A", "Option B"], sel: 1 })
            wait(5)
            Oracle.assertMultiResLayout(tc, container, drop, uiTest, "CraftDrop")
            Oracle.assertZeroWarnings(tc, uiTest, "CraftDrop")
        }
    }
}
