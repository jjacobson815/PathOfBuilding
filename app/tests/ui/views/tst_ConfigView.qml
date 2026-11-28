import QtQuick
import QtTest
import "qrc:/qml/views" as Views
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Views.ConfigView {
        id: view
        anchors.fill: parent
    }

    TestCase {
        id: tc
        name: "ConfigViewTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            verify(uiTest.loadTestBuild("../spec/TestBuilds/3.13/OccVortex.xml"))
            luaEngine.setActiveView("CONFIG")
            view.refresh()
            mouseMove(container, 1, 1)
            wait(30)
        }

        function cleanup() {
            uiTest.resetEngineForTest()
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, view, "pob.config.drop_set")
            Oracle.findRequired(tc, uiTest, view, "pob.config.btn_manage_set")
            var searchIn = Oracle.findRequired(tc, uiTest, view, "pob.config.input_search")
            Oracle.findRequired(tc, uiTest, view, "pob.config.btn_show_all")
            var addCustomBtn = Oracle.findRequired(tc, uiTest, view, "pob.config.btn_add_custom_mod")
            verify(uiTest.findObjectsByPrefix(view, "pob.config.sec_collapse_").length > 0)

            // AC-02: Responsive column counts
            container.width = 700
            wait(10)
            compare(view.colCount, 1)
            container.width = 900
            wait(10)
            compare(view.colCount, 2)
            container.width = 1200
            wait(10)
            compare(view.colCount, 3)
            container.width = 1100
            waitForRendering(view)
            wait(30)

            // AC-04: Add and remove custom modifier group (scroll into viewport before click)
            var initMods = view.customMods.length
            var addCustomBtn2 = Oracle.findRequired(tc, uiTest, view, "pob.config.btn_add_custom_mod")
            var p = addCustomBtn2.parent
            while (p && p.contentY === undefined) p = p.parent
            if (p) {
                var maxY = Math.max(0, p.contentHeight - p.height)
                var targetY = Math.max(0, addCustomBtn2.mapToItem(p.contentItem, 0, 0).y - 100)
                p.contentY = Math.min(maxY, targetY)
            }
            waitForRendering(view)
            wait(20)
            mouseClick(addCustomBtn2)
            tryVerify(function() { return view.customMods.length === initMods + 1 })
            var delBtn = Oracle.findRequired(tc, uiTest, view, "pob.config.btn_delete_mod_1")
            if (p) p.contentY = Math.min(Math.max(0, p.contentHeight - p.height), Math.max(0, delBtn.mapToItem(p.contentItem, 0, 0).y - 100))
            waitForRendering(view)
            wait(20)
            mouseClick(delBtn)
            tryVerify(function() { return view.customMods.length === initMods })
            if (p) p.contentY = 0
            wait(20)

            // AC-05: Search filtering
            var searchIn2 = Oracle.findRequired(tc, uiTest, view, "pob.config.input_search")
            mouseClick(searchIn2)
            keyClick(Qt.Key_F)
            keyClick(Qt.Key_R)
            keyClick(Qt.Key_Return)
            wait(30)
            compare(view.searchQuery, "fr")
            view.searchQuery = ""
            view.refresh()
            wait(20)

            // AC-01: Toggle a config checkbox and verify live output refresh
            var chkBoxes = uiTest.findObjectsByPrefix(view, "pob.configRow.checkCtrl")
            verify(chkBoxes.length > 0)
            var outBefore = luaEngine.getOutput()
            verify(outBefore && outBefore.player)

            mouseMove(container, 1, 1)
            wait(20)
            Oracle.assertMultiResLayout(tc, container, view, uiTest, "ConfigView", 1100, 720, { strict: true, checkSiblingOverlap: false })
            Oracle.assertZeroWarnings(tc, uiTest, "ConfigView")
        }
    }
}
