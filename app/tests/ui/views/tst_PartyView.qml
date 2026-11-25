import QtQuick
import QtTest
import "qrc:/qml/views" as Views
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Views.PartyView {
        id: view
        anchors.fill: parent
    }

    TestCase {
        id: tc
        name: "PartyViewTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            luaEngine.createBuild()
            luaEngine.setActiveView("PARTY")
            view.refresh()
            mouseMove(container, 1, 1)
            wait(20)
        }

        function cleanup() {
            uiTest.resetEngineForTest()
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, view, "pob.party.input_import_code")
            Oracle.findRequired(tc, uiTest, view, "pob.party.drop_destination")
            var btnImport = Oracle.findRequired(tc, uiTest, view, "pob.party.btn_import")
            var chkAppend = Oracle.findRequired(tc, uiTest, view, "pob.party.check_append")
            var btnClear = Oracle.findRequired(tc, uiTest, view, "pob.party.btn_clear")
            var chkAdv = Oracle.findRequired(tc, uiTest, view, "pob.party.check_advanced")
            Oracle.findRequired(tc, uiTest, view, "pob.party.btn_disable_effects")
            var btnRebuild = Oracle.findRequired(tc, uiTest, view, "pob.party.btn_rebuild")

            Oracle.findRequired(tc, uiTest, view, "pob.party.box_auras")
            Oracle.findRequired(tc, uiTest, view, "pob.party.box_warcries")
            Oracle.findRequired(tc, uiTest, view, "pob.party.box_links")
            Oracle.findRequired(tc, uiTest, view, "pob.party.box_party_stats")
            Oracle.findRequired(tc, uiTest, view, "pob.party.box_enemy_cond")
            Oracle.findRequired(tc, uiTest, view, "pob.party.box_enemy_mods")
            Oracle.findRequired(tc, uiTest, view, "pob.party.box_curses")

            // AC-01: Initial state
            compare(btnImport.controlEnabled, false)

            // AC-02..AC-05: Toggles and actions
            var wasAppend = chkAppend.state
            mouseClick(chkAppend)
            wait(10)
            compare(chkAppend.state, !wasAppend)

            var wasAdv = chkAdv.state
            mouseClick(chkAdv)
            wait(10)
            compare(chkAdv.state, !wasAdv)

            mouseClick(btnClear)
            wait(10)
            mouseClick(btnRebuild)
            wait(10)

            Oracle.assertMultiResLayout(tc, container, view, uiTest, "PartyView")
            Oracle.assertZeroWarnings(tc, uiTest, "PartyView")
        }
    }
}
