import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.UpdateBanner {
        id: banner
        width: container.width
    }

    TestCase {
        id: tc
        name: "UpdateBannerTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            banner.updateState = { available: false, dismissed: false }
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, banner, "pob.updatebanner.root")
            var msg = Oracle.findRequired(tc, uiTest, banner, "pob.updatebanner.msg")
            var openBtn = Oracle.findRequired(tc, uiTest, banner, "pob.updatebanner.open")
            var dismissBtn = Oracle.findRequired(tc, uiTest, banner, "pob.updatebanner.dismiss")

            // AC-01: Collapsed when no update
            verify(!banner.visible)
            compare(banner.implicitHeight, 0)

            // AC-02: Expanded when update available
            banner.updateState = {
                available: true,
                dismissed: false,
                currentVersion: "2.47.0",
                latestVersion: "2.48.0",
                releaseUrl: "",
                repo: "PathOfBuildingCommunity/PathOfBuilding"
            }
            wait(15)
            verify(banner.visible)
            compare(banner.implicitHeight, 30)
            verify(msg.label.indexOf("2.47.0 -> 2.48.0") >= 0)
            verify(openBtn.controlEnabled)
            verify(dismissBtn.controlEnabled)

            Oracle.assertMultiResLayout(tc, container, banner, uiTest, "UpdateBanner")

            // AC-04: Dismiss click
            mouseClick(dismissBtn)
            wait(15)
            Oracle.assertZeroWarnings(tc, uiTest, "UpdateBanner")
        }
    }
}
