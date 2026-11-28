import QtQuick
import QtTest
import "qrc:/qml/views" as Views
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Views.BuildListPage {
        id: page
        anchors.fill: parent
    }

    TestCase {
        id: tc
        name: "BuildListPageTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            uiTest.resetEngineForTest()
            page.listSelectedIndex = -1
            page.listSelectedName = ""
            page.listSelectedFullFileName = ""
            page.listSelectedIsFolder = false
            mouseMove(container, 1, 1)
            wait(10)
        }

        function cleanup() {
            uiTest.resetEngineForTest()
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, page, "pob.buildlist.root")
            var btnNew = Oracle.findRequired(tc, uiTest, page, "pob.buildlist.btn_new")
            var btnOpen = Oracle.findRequired(tc, uiTest, page, "pob.buildlist.btn_open")
            var btnDel = Oracle.findRequired(tc, uiTest, page, "pob.buildlist.btn_del")
            var btnMkdir = Oracle.findRequired(tc, uiTest, page, "pob.buildlist.btn_mkdir")
            var btnImport = Oracle.findRequired(tc, uiTest, page, "pob.buildlist.btn_import")
            var listView = Oracle.findRequired(tc, uiTest, page, "pob.buildlist.view")
            var folderInput = Oracle.findRequired(tc, uiTest, page, "pob.buildlist.input_folder")
            var urlInput = Oracle.findRequired(tc, uiTest, page, "pob.buildlist.input_import_url")

            // AC-01: Initial state
            verify(btnNew.controlEnabled)
            compare(btnOpen.controlEnabled, false)
            compare(btnDel.controlEnabled, false)
            compare(btnMkdir.controlEnabled, false)
            compare(btnImport.controlEnabled, false)
            verify(listView.width > 0 && listView.height > 0)

            // AC-02 & AC-03: Selection & folder open gate
            page.listSelectedIndex = 0
            page.listSelectedIsFolder = false
            page.listSelectedName = "Sample"
            page.listSelectedFullFileName = "Sample.xml"
            verify(btnOpen.controlEnabled)
            verify(btnDel.controlEnabled)

            page.listSelectedIsFolder = true
            compare(btnOpen.controlEnabled, false)
            verify(btnDel.controlEnabled)
            page.openSelected() // folder open must be a no-op

            // AC-04: Typing into folder & URL inputs enables buttons
            folderInput.text = "TestFolder"
            compare(btnMkdir.controlEnabled, true)
            folderInput.text = ""
            compare(btnMkdir.controlEnabled, false)

            urlInput.text = "https://pobb.in/test123"
            compare(btnImport.controlEnabled, true)
            urlInput.text = ""
            compare(btnImport.controlEnabled, false)

            // Clicking New Build switches mode to BUILD
            mouseClick(btnNew)
            tryCompare(luaEngine, "currentMode", "BUILD")

            Oracle.assertMultiResLayout(tc, container, page, uiTest, "BuildListPage", 1100, 720, { strict: true, checkSiblingOverlap: false })
            Oracle.assertZeroWarnings(tc, uiTest, "BuildListPage")
        }
    }
}
