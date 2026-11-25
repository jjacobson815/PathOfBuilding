import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    property var lastSet: null
    property var mockRec: ({ shown: true, enabled: true, text: "InitialMod" })

    QtObject {
        id: mockCraft
        function rec(name) { return container.mockRec }
        function set(name, val, quiet) { container.lastSet = [name, val, quiet] }
    }

    Widgets.CraftEdit {
        id: edit
        x: 40
        y: 40
        width: 260
        height: 18
        craft: mockCraft
        name: "custom"
        quiet: true
    }

    TestCase {
        id: tc
        name: "CraftEditTest"
        when: windowShown

        function init() {
            uiTest.resetWarnings()
            edit.craft = mockCraft
            container.lastSet = null
            container.mockRec = uiTest.toVariantMap({ shown: true, enabled: true, text: "InitialMod" })
            mouseMove(container, 1, 1)
            wait(10)
        }

        function test_all_ac() {
            Oracle.findRequired(tc, uiTest, edit, "pob.craftEdit.root")
            compare(edit.text, "InitialMod")

            // AC-02: Edited forwards with quiet flag
            edit.edited("NewModText")
            verify(container.lastSet !== null)
            compare(container.lastSet[0], "custom")
            compare(container.lastSet[1], "NewModText")
            compare(container.lastSet[2], true)

            // AC-04: External state sync
            container.mockRec = uiTest.toVariantMap({ shown: true, enabled: true, text: "SyncedText" })
            wait(5)
            compare(edit.text, "SyncedText")

            // Null craft safety
            edit.craft = null
            edit.edited("Safe")
            verify(!edit.visible)

            edit.craft = mockCraft
            wait(5)
            Oracle.assertMultiResLayout(tc, container, edit, uiTest, "CraftEdit")
            Oracle.assertZeroWarnings(tc, uiTest, "CraftEdit")
        }
    }
}
