import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.BottomBar {
        id: bar
        width: container.width
        anchors.bottom: parent.bottom
    }

    SignalSpy { id: optSpy; target: bar; signalName: "optionsRequested" }
    SignalSpy { id: aboutSpy; target: bar; signalName: "aboutRequested" }

    TestCase {
        id: tc
        name: "BottomBarTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            optSpy.clear()
            aboutSpy.clear()
            wait(10)
        }

        function test_all_ac() {
            var opt = Oracle.findRequired(tc, uiTest, bar, "pob.bottombar.options")
            var abt = Oracle.findRequired(tc, uiTest, bar, "pob.bottombar.about")
            var upd = Oracle.findRequired(tc, uiTest, bar, "pob.bottombar.update")
            Oracle.findRequired(tc, uiTest, bar, "pob.bottombar.fork")
            var ver = Oracle.findRequired(tc, uiTest, bar, "pob.bottombar.version")
            Oracle.findRequired(tc, uiTest, bar, "pob.bottombar.devMode")

            compare(bar.implicitHeight, 24)
            verify(!upd.controlEnabled)
            verify(ver.sourceText.indexOf("Version:") >= 0 || ver.sourceText.indexOf("Beta:") >= 0)

            mouseClick(opt)
            compare(optSpy.count, 1)
            mouseClick(abt)
            compare(aboutSpy.count, 1)

            Oracle.assertMultiResLayout(tc, container, bar, uiTest, "BottomBar")
            Oracle.assertZeroWarnings(tc, uiTest, "BottomBar")
        }
    }
}
