import QtQuick
import QtTest
import "qrc:/qml/views" as Views
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Views.SkillsView {
        id: view
        anchors.fill: parent
    }

    TestCase {
        id: tc
        name: "SkillsViewTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            luaEngine.createBuild()
            luaEngine.setActiveView("SKILLS")
            luaEngine.invoke("pob_skillsNewGroup", [])
            view.refresh()
            mouseMove(container, 1, 1)
            wait(30)
        }

        function cleanup() {
            uiTest.resetEngineForTest()
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, view, "pob.skills.drop_set")
            Oracle.findRequired(tc, uiTest, view, "pob.skills.btn_manage_set")
            Oracle.findRequired(tc, uiTest, view, "pob.skills.list_socket_groups")
            var sortChk = Oracle.findRequired(tc, uiTest, view, "pob.skills.check_sort_dps")
            Oracle.findRequired(tc, uiTest, view, "pob.skills.drop_sort_field")
            Oracle.findRequired(tc, uiTest, view, "pob.skills.drop_default_level")
            Oracle.findRequired(tc, uiTest, view, "pob.skills.input_default_quality")
            Oracle.findRequired(tc, uiTest, view, "pob.skills.drop_support_types")
            Oracle.findRequired(tc, uiTest, view, "pob.skills.check_show_legacy")
            var grpLabel = Oracle.findRequired(tc, uiTest, view, "pob.skills.input_group_label")
            Oracle.findRequired(tc, uiTest, view, "pob.skills.drop_group_slot")
            var grpEn = Oracle.findRequired(tc, uiTest, view, "pob.skills.check_group_enabled")
            Oracle.findRequired(tc, uiTest, view, "pob.skills.check_group_fulldps")
            Oracle.findRequired(tc, uiTest, view, "pob.skills.row_gem.select_gem")

            // AC-01 & AC-02: Canvas dimensions
            verify(view.groups.length >= 1)
            verify(grpLabel.width > 0)

            // AC-05: Edit group label and commit
            mouseClick(grpLabel)
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_B)
            keyClick(Qt.Key_Return)
            wait(30)
            verify(view.detail !== null)

            // Toggle checkbox controls
            var wasSort = sortChk.state
            mouseClick(sortChk)
            wait(10)
            compare(sortChk.state, !wasSort)

            var wasEn = grpEn.state
            mouseClick(grpEn)
            wait(10)
            compare(grpEn.state, !wasEn)

            Oracle.assertMultiResLayout(tc, container, view, uiTest, "SkillsView")
            Oracle.assertZeroWarnings(tc, uiTest, "SkillsView")
        }
    }
}
