import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.SocketGroupList {
        id: sgl
        x: 20
        y: 20
        width: 360
        height: 320
    }

    SignalSpy { id: delSpy; target: sgl; signalName: "deleteRequested" }
    SignalSpy { id: delAllSpy; target: sgl; signalName: "deleteAllRequested" }
    SignalSpy { id: msgSpy; target: sgl; signalName: "messageRequested" }

    TestCase {
        id: tc
        name: "SocketGroupListTest"
        when: windowShown

        function initTestCase() {
            uiTest.resetEngineForTest()
        }

        function cleanupTestCase() {
            uiTest.resetEngineForTest()
        }

        function init() {
            uiTest.resetWarnings()
            delSpy.clear()
            delAllSpy.clear()
            msgSpy.clear()
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            var newBtn = Oracle.findRequired(tc, uiTest, sgl, "pob.socketGroups.newBtn")
            var delAllBtn = Oracle.findRequired(tc, uiTest, sgl, "pob.socketGroups.delAllBtn")
            var delBtn = Oracle.findRequired(tc, uiTest, sgl, "pob.socketGroups.delBtn")
            Oracle.findRequired(tc, uiTest, sgl, "pob.socketGroups.list")
            Oracle.findRequired(tc, uiTest, sgl, "pob.socketGroups.dropLine")
            Oracle.findRequired(tc, uiTest, sgl, "pob.socketGroups.scrollBar")
            var overlay = Oracle.findRequired(tc, uiTest, sgl, "pob.socketGroups.mouseOverlay")

            // AC-01 & BUG-07: populate via QVariantList
            sgl.groups = uiTest.toVariantList([
                { label: "^7Very Long Socket Group Label That Should Clip Cleanly Inside Box Boundary (Active)", icon: "", source: false, hasGems: false, hasTooltip: false },
                { label: "^7Body Armour: Item Granted Skill", icon: "", source: true, hasGems: true, hasTooltip: false },
                { label: "^7Second Group", icon: "", source: false, hasGems: false, hasTooltip: false }
            ])
            wait(10)
            compare(sgl.count, 3)
            verify(delAllBtn.controlEnabled)

            // AC-03: Right-click row 2 selects main group (verify overlay interaction + zero warnings)
            mouseClick(overlay, 30, 2 * 16 + 8, Qt.RightButton)
            wait(10)

            // AC-04: Ctrl+Right-click row 0 toggles FullDPS
            mouseClick(overlay, 30, 8, Qt.RightButton, Qt.ControlModifier)
            wait(10)

            // BUG-19: Clicking below last row does not select out-of-bounds
            sgl.selIndex = 0
            mouseClick(overlay, 30, 200, Qt.LeftButton)
            compare(sgl.selIndex, 0)

            // AC-05: Protected item-granted group guard
            sgl.selIndex = 1
            wait(5)
            verify(!delBtn.controlEnabled)
            sgl.deleteAt(1)
            compare(msgSpy.count, 1)

            // Real bridge New button smoke
            mouseClick(newBtn)
            wait(10)

            Oracle.assertMultiResLayout(tc, container, sgl, uiTest, "SocketGroupList")
            Oracle.assertZeroWarnings(tc, uiTest, "SocketGroupList")
        }
    }
}
