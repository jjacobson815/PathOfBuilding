import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.CalcSectionCard {
        id: card
        x: 20
        y: 20
        coordTarget: container
        activeCellKey: "1:1:1:1"
        searchMatches: ({ "1:1:1": true })
        sectionObj: ({
            index: 1,
            width: 300,
            colour: "#33AAFF",
            special: false,
            subs: [
                {
                    index: 1,
                    label: "Life and Mana",
                    extra: "",
                    collapsed: false,
                    rows: [
                        {
                            index: 1,
                            label: "Total Life",
                            cells: [
                                { key: "1:1:1:1", width: 168, text: "3,013", breakdown: true }
                            ]
                        }
                    ]
                }
            ]
        })
    }

    SignalSpy { id: toggleSpy; target: card; signalName: "toggleSubsection" }
    SignalSpy { id: hoverSpy; target: card; signalName: "cellHovered" }
    SignalSpy { id: clickSpy; target: card; signalName: "cellClicked" }

    TestCase {
        id: tc
        name: "CalcSectionCardTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            toggleSpy.clear()
            hoverSpy.clear()
            clickSpy.clear()
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            var tgl = Oracle.findRequired(tc, uiTest, card, "pob.calcsCard.toggleBtn")
            var lbl = Oracle.findRequired(tc, uiTest, card, "pob.calcsCard.label")
            var cellMa = Oracle.findRequired(tc, uiTest, card, "pob.calcsCard.cellMouse")
            var hl = Oracle.findRequired(tc, uiTest, card, "pob.calcsCard.activeHl")
            Oracle.findRequired(tc, uiTest, card, "pob.calcsCard.skillLoader")

            // AC-03: Search match turns row label red
            verify(lbl.sourceText.indexOf("^xFF0000") === 0)
            compare(hl.color, Qt.color("#40ff40"))

            // AC-04: Cell hover & click signals
            mouseMove(cellMa, 10, 8)
            wait(10)
            verify(hoverSpy.count >= 1)
            mouseClick(cellMa, 10, 8)
            compare(clickSpy.count, 1)
            compare(clickSpy.signalArguments[0][0], "1:1:1:1")

            // AC-02: Toggle subsection emits signal
            mouseClick(tgl)
            compare(toggleSpy.count, 1)
            compare(toggleSpy.signalArguments[0][0], 1)
            compare(toggleSpy.signalArguments[0][1], 1)

            // AC-01: _indexOf handles primitive arrays safely
            compare(card._indexOf(["a", "b"], "id", 1), 0)

            Oracle.assertMultiResLayout(tc, container, card, uiTest, "CalcSectionCard")
            Oracle.assertZeroWarnings(tc, uiTest, "CalcSectionCard")
        }
    }
}
