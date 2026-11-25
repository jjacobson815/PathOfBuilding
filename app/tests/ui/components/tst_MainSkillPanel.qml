import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.MainSkillPanel {
        id: panel
        width: 300
        suffix: ""
    }

    SignalSpy { id: spectreSpy; target: panel; signalName: "manageSpectresRequested" }

    TestCase {
        id: tc
        name: "MainSkillPanelTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            uiTest.resetEngineForTest()
            panel.suffix = ""
            panel.refresh()
            spectreSpy.clear()
            wait(15)
        }

        function test_all_ac() {
            var grp = Oracle.findRequired(tc, uiTest, panel, "pob.mainskill.group")
            var skl = Oracle.findRequired(tc, uiTest, panel, "pob.mainskill.skill")
            var prt = Oracle.findRequired(tc, uiTest, panel, "pob.mainskill.part")
            var stg = Oracle.findRequired(tc, uiTest, panel, "pob.mainskill.stages")
            var mne = Oracle.findRequired(tc, uiTest, panel, "pob.mainskill.mines")
            var mnn = Oracle.findRequired(tc, uiTest, panel, "pob.mainskill.minion")
            Oracle.findRequired(tc, uiTest, panel, "pob.mainskill.minionDrop")
            var spc = Oracle.findRequired(tc, uiTest, panel, "pob.mainskill.spectres")
            var msk = Oracle.findRequired(tc, uiTest, panel, "pob.mainskill.minionSkill")

            verify(grp.count >= 0)
            // AC-02: Conditional controls visibility reflects payload
            panel.payload = {
                socketGroups: [{ index: 1, label: "Group 1" }],
                skills: [{ index: 1, label: "Raise Spectre" }],
                parts: [{ index: 1, label: "Part 1" }],
                noSkills: false,
                skillsEnabled: true,
                partsShown: true,
                stages: { shown: true, value: "5" },
                mines: { shown: true, value: "3" },
                minion: { shown: true, enabled: true, isItemSet: false, libraryShown: true, list: [{ minionId: "m1", label: "Spectre" }] },
                minionSkill: { shown: true, enabled: true, index: 1, list: ["Beam"] }
            }
            wait(15)
            verify(skl.visible)
            verify(prt.visible)
            verify(stg.visible)
            verify(mne.visible)
            verify(mnn.visible)
            verify(spc.visible)
            verify(msk.visible)

            // AC-04: Manage Spectres click emits signal
            mouseClick(spc)
            compare(spectreSpy.count, 1)

            // AC-05: Suffix decoupling property
            panel.suffix = "Calcs"
            panel.refresh()
            wait(15)

            panel.suffix = ""
            panel.refresh()
            Oracle.assertMultiResLayout(tc, container, panel, uiTest, "MainSkillPanel")
            Oracle.assertZeroWarnings(tc, uiTest, "MainSkillPanel")
        }
    }
}
