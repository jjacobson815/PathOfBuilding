import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    property string receivedKey: ""

    Widgets.EditControl {
        id: activeEdit
        x: 20
        y: 20
        text: "KeepFocus"
    }

    Item {
        id: rowItem
        x: 20
        y: 60
        width: 200
        height: 24

        Widgets.HoverKeyArea {
            id: hka
            anchors.fill: parent
            onHoverKeyUp: function(k) { container.receivedKey = k }
        }
    }

    TestCase {
        id: tc
        name: "HoverKeyAreaTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            container.receivedKey = ""
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, hka, "pob.hoverkey.root")
            Oracle.findRequired(tc, uiTest, hka, "pob.hoverkey.hh")
            verify(!hka.hovered)

            activeEdit.forceEditFocus()
            tryCompare(activeEdit, "editing", true)

            mouseMove(rowItem, rowItem.width / 2, rowItem.height / 2)
            tryCompare(hka, "hovered", true)
            verify(activeEdit.editing)

            hka.onHoverKeyUp("W")
            compare(container.receivedKey, "W")

            Oracle.assertMultiResLayout(tc, container, rowItem, uiTest, "HoverKeyArea")
            Oracle.assertZeroWarnings(tc, uiTest, "HoverKeyArea")
        }
    }
}
