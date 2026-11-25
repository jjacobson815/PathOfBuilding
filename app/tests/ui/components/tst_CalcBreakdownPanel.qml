import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.CalcBreakdownPanel {
        id: panel
        hostWidth: container.width
        hostHeight: container.height
        anchorRect: Qt.rect(100, 50, 80, 18)
        pinned: false
        breakdownData: ({
            ok: true,
            sections: [
                {
                    type: "TEXT",
                    lines: ["14% increased maximum Life", "7% increased maximum Life"]
                },
                {
                    type: "TABLE",
                    label: "Sources",
                    cols: [{ label: "Source" }, { label: "Value" }],
                    rows: [
                        {
                            cells: [
                                { text: "Base from Level", tip: { kind: "lines", lines: ["Level 100 base"] } },
                                { text: "1245", right: true }
                            ]
                        }
                    ]
                }
            ]
        })
    }

    SignalSpy { id: closeSpy; target: panel; signalName: "closeRequested" }

    TestCase {
        id: tc
        name: "CalcBreakdownPanelTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            panel.pinned = false
            panel.anchorRect = Qt.rect(100, 50, 80, 18)
            closeSpy.clear()
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            wait(20)
            var frame = Oracle.findRequired(tc, uiTest, panel, "pob.breakdown.frame")
            var closeBtn = Oracle.findRequired(tc, uiTest, panel, "pob.breakdown.closeBtn")
            Oracle.findRequired(tc, uiTest, panel, "pob.breakdown.treePreview")

            verify(panel.visible)
            compare(frame.border.color, Qt.color("#55aa55"))
            verify(!closeBtn.visible)

            // AC-02: Boundary flip when anchor is near right edge
            panel.anchorRect = Qt.rect(1020, 50, 60, 18)
            wait(10)
            verify(panel.x < panel.anchorRect.x)

            // AC-03 & AC-05: Pinned state + Close button
            panel.anchorRect = Qt.rect(100, 50, 80, 18)
            panel.pinned = true
            wait(10)
            compare(frame.border.color, Qt.color("#40ff40"))
            verify(closeBtn.visible)

            Oracle.assertMultiResLayout(tc, container, panel, uiTest, "CalcBreakdownPanel")

            mouseClick(closeBtn)
            compare(closeSpy.count, 1)
            Oracle.assertZeroWarnings(tc, uiTest, "CalcBreakdownPanel")
        }
    }
}
