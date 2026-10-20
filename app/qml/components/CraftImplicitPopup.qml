import QtQuick

// CraftImplicitPopup — ItemsTab:AddImplicitToDisplayItem (ItemsTab.lua:3389-
// 3751), "Add Implicit to Item" 710 x 130: Source (Searing Exarch / Eater of
// Worlds / Delve / Custom), Sort by, Type (mod group) and Modifier dropdowns,
// or a free-text line for Custom. Legacy moves the Modifier label to y 45 for
// Custom (it writes `modSelectLabel.y`); here that follows the custom field.
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

        CraftLabel { craft: root; name: "modGroupSelectLabel"; rx: 95; y: 45 }
        CraftDrop { craft: root; name: "modGroupSelect"; x: 100; y: 45; width: 600; height: 18 }

        CraftLabel { craft: root; staticLabel: "^7Modifier:"; rx: 95; y: root.isCustom ? 45 : 70 }
        CraftDrop { craft: root; name: "modSelect"; x: 100; y: 70; width: 600; height: 18 }
        CraftEdit { craft: root; name: "custom"; quiet: true; x: 100; y: 45; width: 440; height: 18 }

        CraftButton { craft: root; name: "save"; tip: true; x: 710 / 2 - 45 - 40; y: 100; width: 80 }
        CraftButton { craft: root; name: "close"; x: 710 / 2 + 45 - 40; y: 100; width: 80 }
    }
}
