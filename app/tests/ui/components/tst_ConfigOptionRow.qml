import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.ConfigOptionRow {
        id: row
        x: 20
        y: 20
        option: ({
            var: "usePowerCharges",
            type: "check",
            label: "Do you use Power Charges?",
            displayLabel: "^7Do you use Power Charges?",
            value: false,
            borderState: "normal",
            hasTooltip: false
        })
    }

    SignalSpy { id: valSpy; target: row; signalName: "valueChanged" }

    TestCase {
        id: tc
        name: "ConfigOptionRowTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            valSpy.clear()
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            var lbl = Oracle.findRequired(tc, uiTest, row, "pob.configRow.label")
            var chk = Oracle.findRequired(tc, uiTest, row, "pob.configRow.checkCtrl")
            Oracle.findRequired(tc, uiTest, row, "pob.configRow.numCtrl")
            var listCtrl = Oracle.findRequired(tc, uiTest, row, "pob.configRow.listCtrl")
            Oracle.findRequired(tc, uiTest, row, "pob.configRow.textCtrl")

            // AC-01 & AC-02: Click label toggles checkbox
            verify(row.isCheck)
            verify(chk.visible)
            mouseClick(lbl)
            compare(valSpy.count, 1)
            compare(valSpy.signalArguments[0][0], "usePowerCharges")
            compare(valSpy.signalArguments[0][1], true)

            // AC-04: Highlight border colors
            row.option = uiTest.toVariantMap({
                var: "enemyIsBoss",
                type: "list",
                label: "Is the enemy a Boss?",
                displayLabel: "^7Is the enemy a Boss?",
                selIndex: 1,
                options: [{ label: "No", val: "None" }, { label: "Boss", val: "Boss" }],
                borderState: "modified",
                hasTooltip: false
            })
            wait(5)
            verify(row.isList)
            compare(listCtrl.model.length, 2)
            compare(row.highlightBorderColor, Qt.rgba(0.451, 0.576, 0.702, 1))

            // AC-03: Numeric & Text row heights
            row.option = uiTest.toVariantMap({
                var: "enemyLevel",
                type: "count",
                label: "Enemy Level",
                displayLabel: "^7Enemy Level",
                textValue: "84",
                borderState: "invalid",
                hasTooltip: false
            })
            wait(5)
            verify(row.isNum)
            compare(row.height, 20)
            compare(row.highlightBorderColor, Qt.rgba(0.753, 0.502, 0.502, 1))

            row.option = uiTest.toVariantMap({
                var: "customText",
                type: "text",
                label: "Custom",
                displayLabel: "^7Custom",
                textValue: "abc",
                borderState: "normal",
                hasTooltip: false
            })
            wait(5)
            verify(row.isText)
            compare(row.height, 42)

            Oracle.assertMultiResLayout(tc, container, row, uiTest, "ConfigOptionRow")
            Oracle.assertZeroWarnings(tc, uiTest, "ConfigOptionRow")
        }
    }
}
