import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    property string currentVal: "A"

    Widgets.UndoHandler {
        id: uh
        createState: function() { return container.currentVal }
        restoreState: function(s) { container.currentVal = s }
    }

    TestCase {
        id: tc
        name: "UndoHandlerTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            container.currentVal = "A"
            uh._undo = []
            uh._redo = []
            uh.modFlag = false
            wait(5)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, container, "pob.undohandler.root")
            verify(!uh.canUndo)
            verify(!uh.canRedo)

            uh.resetUndo()
            compare(uh._undo.length, 1)
            verify(!uh.canUndo)

            container.currentVal = "B"
            uh.addUndoState()
            verify(uh.canUndo)
            verify(uh.modFlag)

            uh.undo()
            compare(container.currentVal, "A")
            verify(uh.canRedo)

            uh.redo()
            compare(container.currentVal, "B")

            // AC-04: Ring size cap at 101
            uh.resetUndo()
            for (var i = 0; i < 110; i++) {
                container.currentVal = "S" + i
                uh.addUndoState()
            }
            compare(uh._undo.length, 101)

            // AC-05: New mutation clears redo
            uh.undo()
            verify(uh.canRedo)
            container.currentVal = "Z"
            uh.addUndoState()
            verify(!uh.canRedo)

            Oracle.assertMultiResLayout(tc, container, container, uiTest, "UndoHandler")
            Oracle.assertZeroWarnings(tc, uiTest, "UndoHandler")
        }
    }
}
