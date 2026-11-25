import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.AboutPopup {
        id: dlg
        content: luaEngine.getAboutContent()
    }

    TestCase {
        id: tc
        name: "AboutPopupTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            dlg.showHelp = false
            wait(10)
        }

        function test_all_ac() {
            dlg.openAtSection("skills tab")
            tryCompare(dlg, "visible", true)
            verify(dlg.showHelp)

            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.about.githubBtn")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.about.checkUpdateBtn")
            var statusLbl = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.about.statusLabel")
            var openRelBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.about.openReleaseBtn")
            var closeBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.about.closeBtn")
            var histBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.about.historyTab")
            var helpBtn = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.about.helpTab")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.about.list")

            verify(helpBtn.locked)
            mouseClick(histBtn)
            wait(10)
            verify(!dlg.showHelp)
            verify(histBtn.locked)

            // AC-05: Error status renders in red and hides Open Release button
            dlg.updateState = { status: "error", error: "Network unreachable" }
            wait(10)
            verify(statusLbl.label.indexOf("^1") === 0)
            verify(!openRelBtn.visible)

            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "AboutPopup")

            mouseClick(closeBtn)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "AboutPopup")
        }
    }
}
