import QtQuick
import QtTest
import "qrc:/qml/views" as Views
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Views.TreeView {
        id: view
        anchors.fill: parent
    }

    TestCase {
        id: tc
        name: "TreeViewTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            luaEngine.createBuild()
            luaEngine.setActiveView("TREE")
            view.refreshSpecs()
            view.refreshVersion()
            view.refreshPower()
            mouseMove(container, 1, 1)
            wait(20)
        }

        function cleanup() {
            view.showPowerReport = false
            uiTest.resetEngineForTest()
        }

        function test_all_ac() {
            var specDrop = Oracle.findRequired(tc, uiTest, view, "pob.treeview.spec_drop")
            var compareChk = Oracle.findRequired(tc, uiTest, view, "pob.treeview.compare_chk")
            var heatChk = Oracle.findRequired(tc, uiTest, view, "pob.treeview.heat_chk")
            var btnReport = Oracle.findRequired(tc, uiTest, view, "pob.treeview.btn_report")
            var btnFinder = Oracle.findRequired(tc, uiTest, view, "pob.treeview.btn_finder")

            // AC-01: Spec model ends with Manage trees
            verify(specDrop.model && specDrop.model.length >= 2)
            compare(specDrop.model[specDrop.model.length - 1].specIndex, -1)

            // AC-04: Toggle compare mode
            mouseClick(compareChk)
            wait(10)
            verify(compareChk.state)
            mouseClick(compareChk)
            wait(10)

            // AC-02: Enable heat map and toggle power report drawer
            mouseClick(heatChk)
            wait(20)
            verify(btnReport.visible)
            mouseClick(btnReport)
            verify(view.showPowerReport)
            mouseClick(btnReport)
            compare(view.showPowerReport, false)
            mouseClick(heatChk)
            wait(10)

            // AC-03: Open Manage Trees via specDrop last item and close
            var lastIdx = specDrop.model.length - 1
            specDrop.selected(lastIdx)
            wait(20)
            var specManage = uiTest.findObject(view, "pob.specmanage.root")
            verify(specManage !== null && specManage.visible)
            specManage.close()
            tryCompare(specManage, "visible", false)

            // Finder opens TimelessJewelPopup
            mouseClick(btnFinder)
            wait(20)
            var finderPopup = uiTest.findObject(view, "pob.timeless.root")
            verify(finderPopup !== null && finderPopup.visible)
            finderPopup.close()
            tryCompare(finderPopup, "visible", false)

            Oracle.assertMultiResLayout(tc, container, view, uiTest, "TreeView")
            Oracle.assertZeroWarnings(tc, uiTest, "TreeView")
        }
    }
}
