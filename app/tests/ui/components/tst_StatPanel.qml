import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.StatPanel {
        id: panel
        width: theme.sideBarWidth
        height: 400
    }

    TestCase {
        id: tc
        name: "StatPanelTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            panel.refresh()
            wait(15)
        }

        function test_all_ac() {
            var list = Oracle.findRequired(tc, uiTest, panel, "pob.statpanel.list")
            var sb = Oracle.findRequired(tc, uiTest, panel, "pob.statpanel.scrollbar")

            verify(panel.statCount > 0)
            var h = 0
            for (var i = 0; i < panel.rows.length; i++) h += panel.rows[i].height
            compare(panel.contentHeight, h)

            // AC-03 & AC-04: disableReason and Minion partitioning
            panel.output = {
                minion: { stats: [{ label: "Minion Life", valueStr: "1,200" }] },
                disableReason: "No weapon equipped",
                player: {
                    stats: [{ label: "Life", valueStr: "60" }],
                    skillDPS: [{ name: "Arc", dpsStr: "100", count: 1 }]
                }
            }
            wait(15)
            compare(panel.rows[0].kind, "header")
            compare(panel.rows[0].left.indexOf("Minion:") >= 0, true)
            compare(panel.rows[1].kind, "stat")
            compare(panel.rows[2].kind, "spacer")
            compare(panel.rows[3].kind, "header")
            compare(panel.rows[4].left.indexOf("Skill disabled:") >= 0, true)
            compare(panel.rows[5].kind, "center")

            // AC-05: wheel scroll on long list
            var many = []
            for (var k = 0; k < 40; k++) many.push({ label: "Stat " + k, valueStr: String(k) })
            panel.output = { player: { stats: many, skillDPS: [] } }
            wait(15)
            mouseWheel(list, list.width / 2, list.height / 2, 0, -120)
            verify(sb.offset > 0)

            panel.refresh()
            Oracle.assertMultiResLayout(tc, container, panel, uiTest, "StatPanel")
            Oracle.assertZeroWarnings(tc, uiTest, "StatPanel")
        }
    }
}
