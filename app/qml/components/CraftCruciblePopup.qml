import QtQuick

// CraftCruciblePopup — ItemsTab:AddCrucibleModifierToDisplayItem (ItemsTab.lua:3276-
// 3386), "Add Crucible Modifier to Item" 710 x 185: 5 node-location dropdowns (Node 1-5).
CraftPopupBase {
    id: root

    Item {
        implicitWidth: 710
        implicitHeight: root.frameH

        Repeater {
            model: 5
            delegate: Item {
                readonly property int n: index + 1
                readonly property int rowY: 45 + index * 22
                CraftLabel { craft: root; staticLabel: "^7Node " + parent.n + ":"; rx: 95; y: parent.rowY }
                CraftDrop { craft: root; name: "modSelectNode" + parent.n; x: 100; y: parent.rowY; width: 555; height: 18 }
            }
        }

        CraftButton { craft: root; name: "save"; tip: true; x: 710 / 2 - 45 - 40; y: 157; width: 80 }
        CraftButton { craft: root; name: "close"; x: 710 / 2 + 45 - 40; y: 157; width: 80 }
    }
}
