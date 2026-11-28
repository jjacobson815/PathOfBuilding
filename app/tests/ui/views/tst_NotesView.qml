import QtQuick
import QtTest
import "qrc:/qml/views" as Views
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Views.NotesView {
        id: view
        anchors.fill: parent
    }

    TestCase {
        id: tc
        name: "NotesViewTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            verify(uiTest.loadTestBuild("../spec/TestBuilds/3.13/OccVortex.xml"))
            luaEngine.setActiveView("NOTES")
            view.refresh()
            mouseMove(container, 1, 1)
            wait(20)
        }

        function cleanup() {
            uiTest.resetEngineForTest()
        }

        function test_all_ac() {
            var editor = Oracle.findRequired(tc, uiTest, view, "pob.notes.text_editor")
            var preview = Oracle.findRequired(tc, uiTest, view, "pob.notes.view_preview")
            var toggleBtn = Oracle.findRequired(tc, uiTest, view, "pob.notes.btn_toggle_preview")
            var colorBtn = Oracle.findRequired(tc, uiTest, view, "pob.notes.btn_color_0")

            // AC-01 & AC-02: Typing updates preview synchronously
            verify(editor.width > 0 && preview.width > 0)
            mouseClick(editor)
            keyClick(Qt.Key_H)
            keyClick(Qt.Key_I)
            wait(160)
            verify(editor.text.indexOf("hi") >= 0 || editor.text.indexOf("HI") >= 0)
            compare(preview.sourceText, editor.text)

            // AC-03: Color insert wraps selection or inserts color code
            editor.selectAll()
            mouseClick(colorBtn)
            wait(20)
            verify(editor.text.indexOf("^") >= 0)

            // AC-04: Zoom helper scaling
            var oldSz = view.editorFontSize
            view._zoom(2)
            compare(view.editorFontSize, oldSz + 2)
            view._zoom(-2)
            compare(view.editorFontSize, oldSz)

            // AC-05: Toggle preview pane & Show Color Codes
            var codesBtn = Oracle.findRequired(tc, uiTest, view, "pob.notes.btn_toggle_codes")
            mouseClick(codesBtn)
            wait(20)
            verify(preview.sourceText.indexOf("^_") === -1)
            mouseClick(codesBtn)
            wait(20)

            verify(view.showPreview)
            mouseClick(toggleBtn)
            compare(view.showPreview, false)
            mouseClick(toggleBtn)
            verify(view.showPreview)

            mouseMove(container, 1, 1)
            wait(20)
            Oracle.assertMultiResLayout(tc, container, view, uiTest, "NotesView", 1100, 720, { strict: true, checkSiblingOverlap: false })
            Oracle.assertZeroWarnings(tc, uiTest, "NotesView")
        }
    }
}
