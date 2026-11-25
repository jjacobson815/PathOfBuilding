import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.ItemListBox {
        id: ilb
        x: 20
        y: 20
        width: 360
        height: 240
        title: "All Items"
        defaultText: "^7No items yet.\n^8Drag items here."
        dragKind: "item"
        acceptKinds: ["item"]
        reorderable: true
    }

    SignalSpy { id: ctrlSpy; target: ilb; signalName: "ctrlClicked" }
    SignalSpy { id: dblSpy; target: ilb; signalName: "doubleClicked" }
    SignalSpy { id: movedSpy; target: ilb; signalName: "moved" }

    TestCase {
        id: tc
        name: "ItemListBoxTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            ilb.selIndex = -1
            ilb.rows = uiTest.toVariantList([
                { key: "1", label: "^4Mageblood, Heavy Belt - Very Long Item Name To Verify Right Elision Inside Fixed Box" },
                { key: "2", label: "^4Headhunter, Leather Belt" },
                { key: "3", label: "^3Mirrored Bow, Spine Bow" }
            ])
            ctrlSpy.clear()
            dblSpy.clear()
            movedSpy.clear()
            mouseMove(container, 1, 1)
            wait(15)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, ilb, "pob.itemList.box")
            var emptyCol = Oracle.findRequired(tc, uiTest, ilb, "pob.itemList.emptyText")
            Oracle.findRequired(tc, uiTest, ilb, "pob.itemList.list")
            var ma = Oracle.findRequired(tc, uiTest, ilb, "pob.itemList.mouseArea")
            Oracle.findRequired(tc, uiTest, ilb, "pob.itemList.dropArea")
            Oracle.findRequired(tc, uiTest, ilb, "pob.itemList.insertMarker")
            Oracle.findRequired(tc, uiTest, ilb, "pob.itemList.scrollBar")

            // AC-01: Populated rows, empty text hidden
            compare(ilb.count, 3)
            verify(!emptyCol.visible)

            // AC-02: Keyboard traversal Up/Down
            ilb.forceActiveFocus()
            keyClick(Qt.Key_Down)
            compare(ilb.selIndex, 0)
            keyClick(Qt.Key_Down)
            compare(ilb.selIndex, 1)
            keyClick(Qt.Key_Up)
            compare(ilb.selIndex, 0)

            // AC-04: Ctrl+Click & Ctrl+Shift+Click
            mouseClick(ma, 30, 2 * 16 + 8, Qt.LeftButton, Qt.ControlModifier)
            compare(ctrlSpy.count, 1)
            compare(ctrlSpy.signalArguments[0][0], 2)
            compare(ctrlSpy.signalArguments[0][1], false)

            mouseClick(ma, 30, 2 * 16 + 8, Qt.LeftButton, Qt.ControlModifier | Qt.ShiftModifier)
            compare(ctrlSpy.count, 2)
            compare(ctrlSpy.signalArguments[1][1], true)

            Oracle.assertMultiResLayout(tc, container, ilb, uiTest, "ItemListBox")

            // AC-05: Empty state displays defaultText cleanly
            ilb.rows = uiTest.toVariantList([])
            wait(10)
            compare(ilb.count, 0)
            verify(emptyCol.visible)

            Oracle.assertZeroWarnings(tc, uiTest, "ItemListBox")
        }
    }
}
