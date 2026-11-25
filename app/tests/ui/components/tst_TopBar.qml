import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.TopBar {
        id: topBar
        width: container.width
    }

    SignalSpy { id: saveAsSpy; target: topBar; signalName: "saveAsRequested" }
    SignalSpy { id: collapseSpy; target: topBar; signalName: "collapseToggled" }

    TestCase {
        id: tc
        name: "TopBarTest"
        when: windowShown

        function initTestCase() {
            uiTest.resetEngineForTest()
        }

        function init() {
            uiTest.resetWarnings()
            uiTest.resetEngineForTest()
            topBar.refresh()
            saveAsSpy.clear()
            collapseSpy.clear()
            wait(15)
        }

        function cleanupTestCase() {
            uiTest.resetEngineForTest()
        }

        function test_ac01_initial_render_and_zero_warnings() {
            Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.collapse")
            Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.back")
            Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.save")
            Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.saveAs")
            Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.namePlate")
            Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.points")
            Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.levelMode")
            Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.level")
            Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.class")
            Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.ascend")
            Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.secondary")
            Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.loadouts")

            verify(topBar.hasBuild)
            verify(topBar.loadoutEntries.length > 0)
            Oracle.assertMultiResLayout(tc, container, topBar, uiTest, "TopBar")
            Oracle.assertZeroWarnings(tc, uiTest, "TopBar AC-01")
        }

        function test_ac02_long_build_name_elision() {
            luaEngine.setBuildName("Very Long Character Build Name For Testing Elision And Overflow Behavior Across Multiple Resolutions")
            topBar.refresh()
            wait(15)
            var np = Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.namePlate")
            verify(np.width <= 260)
            Oracle.assertMultiResLayout(tc, container, topBar, uiTest, "TopBar LongName")
            luaEngine.setBuildName("Unnamed build")
            topBar.refresh()
            Oracle.assertZeroWarnings(tc, uiTest, "TopBar AC-02")
        }

        function test_ac03_class_and_bug04_loadouts_qvariantlist() {
            // BUG-04 regression: QVariantList loadout dropdown must populate
            topBar.loadoutState = uiTest.toVariantMap({
                ok: true,
                activeDropdownIndex0: 0,
                dropdown: uiTest.toVariantList([
                    { label: "Default", value: 1, kind: "loadout" },
                    { label: "Manage...", value: "manage", kind: "manage" }
                ])
            })
            wait(10)
            compare(topBar.loadoutEntries.length, 2)
            Oracle.assertZeroWarnings(tc, uiTest, "TopBar AC-03")
        }

        function test_ac04_save_without_filename_signals_saveAs() {
            var saveBtn = Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.save")
            if (!topBar.shell.dbFileName || topBar.shell.dbFileName.length === 0) {
                mouseClick(saveBtn)
                compare(saveAsSpy.count, 1)
            }
            Oracle.assertZeroWarnings(tc, uiTest, "TopBar AC-04")
        }

        function test_ac05_list_mode_hides_build_controls() {
            luaEngine.setListMode()
            topBar.refresh()
            wait(15)
            verify(!topBar.hasBuild)
            var saveBtn = Oracle.findRequired(tc, uiTest, topBar, "pob.topbar.save")
            verify(!saveBtn.visible)
            uiTest.resetEngineForTest()
            topBar.refresh()
            Oracle.assertZeroWarnings(tc, uiTest, "TopBar AC-05")
        }
    }
}
