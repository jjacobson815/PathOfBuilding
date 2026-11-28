import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.PowerReportPanel {
        id: panel
        x: 20
        y: 20
        width: 560
        height: 360
    }

    SignalSpy { id: nodeSpy; target: panel; signalName: "nodeSelected" }

    TestCase {
        id: tc
        name: "PowerReportPanelTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            panel.filterIndex = 0
            panel.showMasteries = true
            panel.sortCol = 3
            panel.setReport(null)
            nodeSpy.clear()
            mouseMove(container, 1, 1)
            wait(10)
            waitForRendering(panel)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, panel, "pob.powerreport.root")
            var mastChk = Oracle.findRequired(tc, uiTest, panel, "pob.powerreport.chk_mast")
            var filterDrop = Oracle.findRequired(tc, uiTest, panel, "pob.powerreport.filter")
            var hdrs = uiTest.findObjectsByPrefix(panel, "pob.powerreport.hdr")
            verify(hdrs.length === 5)

            // AC-01: Default state
            compare(panel.sortCol, 3)
            compare(panel.shown.length, 0)

            var sample = uiTest.toVariantMap({
                label: "Stat: Combined DPS",
                statLabel: "Total DPS",
                rows: [
                    { id: 4567, type: "Notable", name: "Heartseeker", power: 8.4, powerStr: "+8.4%", pathDist: 2, pathPower: 4.2, pathPowerStr: "+4.2%", allocated: false },
                    { id: 1002, type: "Mastery", name: "Life Mastery", power: 5.0, powerStr: "+5.0%", pathDist: 1, pathPower: 5.0, pathPowerStr: "+5.0%", allocated: false },
                    { id: 1003, type: "Notable", name: "Whispers of Doom", power: 14.2, powerStr: "+14.2%", pathDist: 1000, pathPower: 14.2, pathPowerStr: "+14.2%", allocated: false },
                    { id: 1004, type: "Small", name: "Allocated Life", power: 0, powerStr: "0%", pathDist: 1, pathPower: 0, pathPowerStr: "0%", allocated: true }
                ]
            })
            panel.setReport(sample)
            compare(panel.shown.length, 3)

            // AC-02: Unchecking Show Masteries removes Mastery rows
            mouseClick(mastChk)
            compare(panel.shown.length, 2)
            for (var i = 0; i < panel.shown.length; i++)
                verify(panel.shown[i].type !== "Mastery")
            mouseClick(mastChk)

            // AC-03: Click Type header sorts alphabetically ascending
            wait(10)
            waitForRendering(panel)
            hdrs = uiTest.findObjectsByPrefix(panel, "pob.powerreport.hdr")
            verify(hdrs.length === 5)
            var typeHdr = null
            for (var hi = 0; hi < hdrs.length; hi++) {
                if (hdrs[hi].width > 0 && hdrs[hi].visible && hdrs[hi].children.length > 0 && hdrs[hi].children[0].label === "Type") {
                    typeHdr = hdrs[hi]
                    break
                }
            }
            verify(typeHdr !== null)
            mouseClick(typeHdr)
            compare(panel.sortCol, 1)
            compare(panel.shown[0].type, "Mastery")

            // AC-04: Allocated mode reverses default sort direction
            filterDrop.currentIndex = 2
            filterDrop.selected(2)
            compare(panel.filterIndex, 2)
            compare(panel.shown.length, 1)
            compare(panel.shown[0].id, 1004)

            // AC-05: Clicking row emits nodeSelected
            filterDrop.currentIndex = 0
            filterDrop.selected(0)
            wait(50)
            waitForRendering(panel)
            var allRows = uiTest.findObjectsByPrefix(panel, "pob.powerreport.row")
            var rows = []
            for (var r = 0; r < allRows.length; r++) {
                if (allRows[r] && allRows[r].parent && allRows[r].width > 0 && allRows[r].visible)
                    rows.push(allRows[r])
            }
            verify(rows.length > 0)
            mouseClick(rows[0])
            compare(nodeSpy.count, 1)
            compare(nodeSpy.signalArguments[0][0], panel.shown[0].id)

            Oracle.assertMultiResLayout(tc, container, panel, uiTest, "PowerReportPanel")
            Oracle.assertZeroWarnings(tc, uiTest, "PowerReportPanel")
        }
    }
}
