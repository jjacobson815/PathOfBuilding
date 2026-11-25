import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    property var mockRec: ({ shown: true, label: "^7DynamicSort:" })

    QtObject {
        id: mockCraft
        function rec(name) { return container.mockRec }
    }

    Widgets.CraftLabel {
        id: staticLbl
        y: 20
        rx: 95
        staticLabel: "^7Source:"
    }

    Widgets.CraftLabel {
        id: dynLbl
        y: 50
        rx: 250
        craft: mockCraft
        name: "sortLabel"
    }

    TestCase {
        id: tc
        name: "CraftLabelTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dynLbl.craft = mockCraft
            container.mockRec = uiTest.toVariantMap({ shown: true, label: "^7DynamicSort:" })
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, staticLbl, "pob.craftLabel.root")
            Oracle.findRequired(tc, uiTest, dynLbl, "pob.craftLabel.root")

            // AC-01 & AC-03: Right anchor precision without negative X clip
            compare(staticLbl.x + staticLbl.width, 95)
            verify(staticLbl.x >= 0)
            compare(dynLbl.x + dynLbl.width, 250)
            compare(dynLbl.label, "^7DynamicSort:")

            // AC-05: Null craft safety
            dynLbl.craft = null
            wait(5)
            compare(dynLbl.label, "")
            verify(!dynLbl.visible)

            dynLbl.craft = mockCraft
            wait(5)
            Oracle.assertMultiResLayout(tc, container, container, uiTest, "CraftLabel")
            Oracle.assertZeroWarnings(tc, uiTest, "CraftLabel")
        }
    }
}
