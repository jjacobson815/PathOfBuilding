import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.TextListControl {
        id: tl
        x: 20
        y: 20
        width: 300
        height: 120
        columns: [{ x: 4, align: "LEFT" }, { x: 150, align: "LEFT" }]
        list: [
            { 1: "Row 1", height: 16 },
            { 1: "Row 2", height: 16 }
        ]
    }

    TestCase {
        id: tc
        name: "TextListControlTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            tl.list = [
                { 1: "Row 1", height: 16 },
                { 1: "Row 2", height: 16 }
            ]
            tl.sectionHeights = null
            tl.setScrollOffset(0)
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, tl, "pob.textlist.root")
            var sb = Oracle.findRequired(tc, uiTest, tl, "pob.textlist.scroll")
            var wheelArea = Oracle.findRequired(tc, uiTest, tl, "pob.textlist.wheel")

            compare(tl.contentHeight, 32)
            compare(tl.rowOffsets.length, 2)
            compare(tl.rowOffsets[0], 0)
            compare(tl.rowOffsets[1], 16)

            // Multi-column + tall list
            var rows = [{ 1: "Col A", 2: "Col B", height: 16 }]
            for (var i = 0; i < 25; i++) rows.push({ 1: "Line " + i, height: 16 })
            tl.list = rows
            tl.sectionHeights = [0, 150, 300]
            wait(10)

            tl.setScrollOffset(100)
            compare(sb.offset, 100)

            tl.setScrollOffset(0)
            mouseWheel(wheelArea, wheelArea.width / 2, wheelArea.height / 2, 0, -120, Qt.NoButton, Qt.ShiftModifier)
            compare(sb.offset, 150)
            // Shift+wheel at last section does not error or stick badly
            mouseWheel(wheelArea, wheelArea.width / 2, wheelArea.height / 2, 0, -120, Qt.NoButton, Qt.ShiftModifier)
            compare(sb.offset, 300)

            Oracle.assertMultiResLayout(tc, container, tl, uiTest, "TextListControl")
            Oracle.assertZeroWarnings(tc, uiTest, "TextListControl")
        }
    }
}
