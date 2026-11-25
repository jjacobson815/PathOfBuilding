import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.Chrome {
        id: chrome
        x: 20
        y: 20
        width: 120
        height: 24
    }

    TestCase {
        id: tc
        name: "ChromeTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            chrome.pressed = false
            chrome.hovered = false
            chrome.locked = false
            chrome.controlEnabled = true
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, chrome, "pob.chrome.surface")
            compare(chrome.border.width, 1)
            compare(chrome.color, Qt.rgba(0, 0, 0, 0))
            compare(chrome.border.color, theme.border)

            chrome.hovered = true
            compare(chrome.border.color, theme.borderStrong)
            compare(chrome.color, theme.hover)

            chrome.pressed = true
            compare(chrome.color, theme.active)

            chrome.pressed = false
            chrome.hovered = false
            chrome.locked = true
            compare(chrome.color, theme.hover)
            compare(chrome.border.color, theme.borderStrong)

            chrome.controlEnabled = false
            chrome.pressed = true
            chrome.hovered = true
            compare(chrome.color, theme.disabled)
            compare(chrome.border.color, theme.border)

            Oracle.assertMultiResLayout(tc, container, chrome, uiTest, "Chrome")
            Oracle.assertZeroWarnings(tc, uiTest, "Chrome")
        }
    }
}
