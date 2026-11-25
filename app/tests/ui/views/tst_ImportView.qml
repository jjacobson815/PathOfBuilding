import QtQuick
import QtTest
import "qrc:/qml/views" as Views
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Views.ImportView {
        id: view
        anchors.fill: parent
    }

    TestCase {
        id: tc
        name: "ImportViewTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            luaEngine.createBuild()
            luaEngine.setActiveView("IMPORT")
            view.refresh()
            mouseMove(container, 1, 1)
            wait(20)
        }

        function cleanup() {
            uiTest.resetEngineForTest()
        }

        function test_all_ac() {
            var realmDrop = Oracle.findRequired(tc, uiTest, view, "pob.import.realm_drop")
            var authOAuth = Oracle.findRequired(tc, uiTest, view, "pob.import.auth_oauth")
            var charDrop = Oracle.findRequired(tc, uiTest, view, "pob.import.char_drop")
            var btnImport = Oracle.findRequired(tc, uiTest, view, "pob.import.btn_import")
            var shareBtn = Oracle.findRequired(tc, uiTest, view, "pob.import.share_btn")
            var openBtn = Oracle.findRequired(tc, uiTest, view, "pob.import.open_btn")

            // AC-01: Mount & state initialization
            verify(realmDrop.width > 0)
            verify(charDrop.width > 0)
            compare(btnImport.controlEnabled, false)
            compare(openBtn.controlEnabled, false)

            // Toggle OAuth button and generate share code
            mouseClick(authOAuth)
            wait(10)
            mouseClick(shareBtn)
            wait(20)
            verify(view._share.code && view._share.code.length > 0)

            Oracle.assertMultiResLayout(tc, container, view, uiTest, "ImportView")
            Oracle.assertZeroWarnings(tc, uiTest, "ImportView")
        }
    }
}
