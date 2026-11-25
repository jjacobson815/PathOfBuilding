import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    property var items: ["Deadeye Bow Attack", "Lightning Strike", "Attack Deadeye"]

    Widgets.SearchHost {
        id: sh
        listAccessor: function() { return container.items }
        valueAccessor: function(e) { return e }
    }

    TestCase {
        id: tc
        name: "SearchHostTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            sh.resetSearch()
            wait(5)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, container, "pob.searchhost.root")
            compare(sh.searchTerm, "")
            verify(!sh.searchActive)
            compare(sh.matchCount, 0)

            // AC-02: Sequential word-order matching
            sh.searchTerm = "deadeye attack"
            sh.updateSearch()
            compare(sh.searchInfos[0].matches, true)
            compare(sh.searchInfos[2].matches, false)
            compare(sh.matchCount, 1)

            // AC-03: Character highlight ranges
            sh.searchTerm = "light strike"
            sh.updateSearch()
            compare(sh.searchInfos[1].matches, true)
            compare(sh.searchInfos[1].ranges.length, 2)
            compare(sh.searchInfos[1].ranges[0].from, 0)
            compare(sh.searchInfos[1].ranges[0].to, 5)
            compare(sh.searchInfos[1].ranges[1].from, 10)
            compare(sh.searchInfos[1].ranges[1].to, 16)

            // AC-04: Backspace & Escape
            sh.resetSearch()
            sh.onSearchChar("a")
            sh.onSearchChar("b")
            sh.onSearchChar("c")
            compare(sh.searchTerm, "abc")
            sh.onSearchKeyDown("BACK")
            compare(sh.searchTerm, "ab")
            sh.onSearchKeyDown("ESCAPE")
            compare(sh.searchTerm, "")

            // AC-05: Pretty string styling with 0 matches
            sh.searchTerm = "zzzz"
            sh.updateSearch()
            verify(sh.searchActive)
            compare(sh.matchCount, 0)
            verify(sh.searchTermPretty().indexOf("^xFF0000") === 0)

            Oracle.assertMultiResLayout(tc, container, container, uiTest, "SearchHost")
            Oracle.assertZeroWarnings(tc, uiTest, "SearchHost")
        }
    }
}
