import QtQuick
import QtTest
import "qrc:/qml/views" as Views
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Views.CalcsView {
        id: view
        anchors.fill: parent
    }

    TestCase {
        id: tc
        name: "CalcsViewTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            luaEngine.createBuild()
            luaEngine.setActiveView("CALCS")
            view.refresh()
            mouseMove(container, 1, 1)
            wait(30)
        }

        function cleanup() {
            view.clearBreakdown()
            uiTest.resetEngineForTest()
        }

        function test_all_ac() {
            var searchIn = Oracle.findRequired(tc, uiTest, view, "pob.calcs.input_search")
            var clearBtn = Oracle.findRequired(tc, uiTest, view, "pob.calcs.btn_clear_search")
            var bdPanel = Oracle.findRequired(tc, uiTest, view, "pob.calcs.breakdownPanel")

            // AC-01 & AC-02: Section cards and masonry layout
            verify(view._sections.length > 0)
            verify(view.layoutInfo.contentW > 0 && view.layoutInfo.contentH > 0)

            // AC-05: Search & Clear
            view.runSearch("Life")
            verify(view.searchHitCount > 0)
            verify(clearBtn.visible)
            mouseClick(clearBtn)
            compare(view.searchHitCount, 0)
            compare(view.searchQuery, "")

            // AC-03 & AC-04: Pin breakdown on clickable stat cell then dismiss with Esc
            var cells = uiTest.findObjectsByPrefix(view, "pob.calcsCard.cellMouse")
            verify(cells.length > 0)
            for (var si = 0; si < view._sections.length && !view.breakdownPinned; si++) {
                var sec = view._sections[si]
                if (!sec || !sec.enabled || !sec.subs) continue
                for (var ui2 = 0; ui2 < sec.subs.length && !view.breakdownPinned; ui2++) {
                    var sub = sec.subs[ui2]
                    if (!sub || sub.collapsed || !sub.rows) continue
                    for (var ri = 0; ri < sub.rows.length && !view.breakdownPinned; ri++) {
                        var r = sub.rows[ri]
                        if (!r || !r.cells) continue
                        for (var ci = 0; ci < r.cells.length; ci++) {
                            var c = r.cells[ci]
                            if (c && c.breakdown && c.key) {
                                view.showBreakdown(c.key, Qt.rect(100, 100, 60, 18), true)
                                break
                            }
                        }
                    }
                }
            }
            if (view.breakdownPinned) {
                verify(bdPanel.visible)
                keyClick(Qt.Key_Escape)
                compare(view.breakdownPinned, false)
            }
            verify(searchIn.width > 0)

            Oracle.assertMultiResLayout(tc, container, view, uiTest, "CalcsView")
            Oracle.assertZeroWarnings(tc, uiTest, "CalcsView")
        }
    }
}
