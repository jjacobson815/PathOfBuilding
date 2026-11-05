import QtQuick

// CraftCustomPopup — ItemsTab:AddCustomModifierToDisplayItem (ItemsTab.lua:2973-
// 3274), "Add Modifier to Item" 710 x 105: Source (Crafting Bench / Essence /
// Veiled / Beastcraft / Necropolis / Delve / Prefix / Suffix / Custom), Sort by,
// Modifier dropdown, or a free-text line for Custom.
CraftPopupBase {
    id: root

    readonly property bool isCustom: rec("custom").shown === true

    Item {
        implicitWidth: 710
        implicitHeight: root.frameH

        CraftLabel { craft: root; staticLabel: "^7Source:"; rx: 95; y: 20 }
        CraftDrop { craft: root; name: "source"; x: 100; y: 20; width: 150; height: 18 }
        CraftLabel { craft: root; name: "sortLabel"; rx: 350; y: 20 }
        CraftDrop { craft: root; name: "sort"; x: 355; y: 20; width: 240; height: 18 }

        CraftLabel { craft: root; staticLabel: "^7Modifier:"; rx: 95; y: 45 }
        CraftDrop { craft: root; name: "modSelect"; x: 100; y: 45; width: 600; height: 18 }
        CraftEdit { craft: root; name: "custom"; quiet: true; x: 100; y: 45; width: 440; height: 18 }

        CraftButton { craft: root; name: "save"; tip: true; x: 710 / 2 - 45 - 40; y: 75; width: 80 }
        CraftButton { craft: root; name: "close"; x: 710 / 2 + 45 - 40; y: 75; width: 80 }
    }
}
