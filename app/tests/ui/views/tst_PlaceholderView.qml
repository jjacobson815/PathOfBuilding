import QtQuick
import QtTest
import "qrc:/qml/views" as Views
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Views.PlaceholderView {
        id: view
        anchors.fill: parent
        activeView: "CALCS"
    }

    TestCase {
        id: tc
        name: "PlaceholderViewTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            luaEngine.createBuild()
            view.activeView = "CALCS"
            view.saveLoadStatus = "idle"
            mouseMove(container, 1, 1)
            wait(10)
        }

        function cleanup() {
            uiTest.resetEngineForTest()
        }

        function test_all_ac() {
            var rootObj = Oracle.findRequired(tc, uiTest, view, "pob.placeholder.root")
            var btnSave = Oracle.findRequired(tc, uiTest, view, "pob.placeholder.btn_save")
            var btnLoad = Oracle.findRequired(tc, uiTest, view, "pob.placeholder.btn_load")
            var list = Oracle.findRequired(tc, uiTest, view, "pob.placeholder.list")

            // AC-01 & AC-02: Mount & viewLabel resolution
            compare(view.saveLoadStatus, "idle")
            compare(view.viewLabel("CALCS"), "Calcs")
            verify(btnSave.enabled)
            verify(btnLoad.enabled)
            verify(list.width > 0 && list.height > 0)

            // AC-03: Clicking Load updates saveLoadStatus safely without writing disk
            mouseClick(btnLoad)
            verify(view.saveLoadStatus !== "idle")

            // AC-04: Long status text elides cleanly across resolutions
            view.saveLoadStatus = "Saved -> " + "very/long/path/".repeat(12) + "build.xml"
            Oracle.assertMultiResLayout(tc, container, rootObj, uiTest, "PlaceholderView")
            Oracle.assertZeroWarnings(tc, uiTest, "PlaceholderView")
        }
    }
}
