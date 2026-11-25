import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    property string lastChange: ""

    Widgets.PathControl {
        id: pc
        x: 20
        y: 20
        width: 400
        basePath: "builds/"
        subPath: ""
        onChange: function(p) { container.lastChange = p }
    }

    TestCase {
        id: tc
        name: "PathControlTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            pc.basePath = "builds/"
            pc.subPath = ""
            container.lastChange = ""
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, pc, "pob.path.root")
            Oracle.findRequired(tc, uiTest, pc, "pob.path.undo")
            compare(pc.folderList.length, 1)

            pc.subPath = "Poison/BladeVortex/"
            wait(10)
            compare(pc.folderList.length, 3)
            compare(pc.folderList[1].label, "Poison")
            compare(pc.folderList[2].label, "BladeVortex")

            var segs = uiTest.findObjectsByPrefix(pc, "pob.path.segment")
            compare(segs.length, 3)
            mouseClick(segs[1])
            wait(10)
            compare(container.lastChange, "Poison/")
            compare(pc.subPath, "Poison/")

            // Undo/Redo ring
            pc.setSubPath("")
            pc.setSubPath("A/")
            pc.setSubPath("A/B/")
            verify(pc.canUndo())
            pc.undoPath()
            compare(pc.subPath, "A/")
            verify(pc.canRedo())
            pc.redoPath()
            compare(pc.subPath, "A/B/")

            Oracle.assertMultiResLayout(tc, container, pc, uiTest, "PathControl")
            Oracle.assertZeroWarnings(tc, uiTest, "PathControl")
        }
    }
}
