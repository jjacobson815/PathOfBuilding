import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.ItemAffixRow {
        id: row
        x: 100
        y: 20
        rec: ({
            n: 1,
            label: "Prefix:",
            list: ["None", "T1 - (35-39)% increased Spell Damage"],
            sel: 1,
            sliderShown: false,
            rollLabel: "Roll:",
            sliderWidth: 100,
            divCount: 5,
            val: 0.5
        })
    }

    TestCase {
        id: tc
        name: "ItemAffixRowTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            var lbl = Oracle.findRequired(tc, uiTest, row, "pob.itemAffix.label")
            var drop = Oracle.findRequired(tc, uiTest, row, "pob.itemAffix.drop")
            var rlbl = Oracle.findRequired(tc, uiTest, row, "pob.itemAffix.rollLabel")
            var slider = Oracle.findRequired(tc, uiTest, row, "pob.itemAffix.slider")

            compare(row.height, 24)
            verify(!rlbl.visible)
            verify(!slider.visible)
            compare(drop.model.length, 2)
            verify(lbl.x + lbl.width <= drop.x)

            row.rec = uiTest.toVariantMap({
                n: 1,
                label: "LongPrefix:",
                list: ["T1 - Spell Damage", "T2 - Spell Damage"],
                sel: 2,
                sliderShown: true,
                rollLabel: "Roll:",
                sliderWidth: 300,
                divCount: 5,
                val: 0.75
            })
            wait(10)
            compare(row.height, 42)
            verify(rlbl.visible)
            verify(slider.visible)
            compare(slider.width, 300)
            verify(rlbl.x + rlbl.width <= slider.x)

            Oracle.assertMultiResLayout(tc, container, row, uiTest, "ItemAffixRow")
            Oracle.assertZeroWarnings(tc, uiTest, "ItemAffixRow")
        }
    }
}
