import QtQuick

// CraftEnchantPopup — ItemsTab:EnchantDisplayItem (ItemsTab.lua:2280-2489),
// "Enchant Item" 605 x 130. Layout, control names and sizes are legacy's.
CraftPopupBase {
    id: root

    Item {
        implicitWidth: 605
        implicitHeight: root.frameH

        CraftLabel { craft: root; staticLabel: "^7Skill:"; rx: 95; y: 20; visible: root.rec("skill").shown === true }
        CraftDrop { craft: root; name: "skill"; x: 100; y: 20; width: 180; height: 18 }
        CheckBox {
            id: allSkills
            visible: root.rec("allSkills").shown === true
            x: 350; y: 20; width: 18; height: 18
            label: "All skills:"
            controlEnabled: root.rec("allSkills").enabled !== false
            tooltipText: "Show all skills, not just those used by this build."
            readonly property var r: root.rec("allSkills")
            onRChanged: if (r.state !== undefined) state = r.state === true
            onToggled: function (s) { root.set("allSkills", s) }
        }

        CraftLabel { craft: root; staticLabel: "^7Source:"; rx: 95; y: 45 }
        CraftDrop { craft: root; name: "enchantmentSource"; x: 100; y: 45; width: 180; height: 18 }
        CraftLabel { craft: root; staticLabel: "^7Sort by:"; rx: 350; y: 45 }
        CraftDrop { craft: root; name: "sort"; x: 355; y: 45; width: 240; height: 18 }

        CraftLabel { craft: root; staticLabel: "^7Enchantment:"; rx: 95; y: 70 }
        CraftDrop { craft: root; name: "enchantment"; x: 100; y: 70; width: 495; height: 18 }

        CraftButton { craft: root; name: "save"; x: 605 / 2 - 88 - 40; y: 100; width: 80 }
        CraftButton { craft: root; name: "remove"; x: 605 / 2 - 40; y: 100; width: 80 }
        CraftButton { craft: root; name: "close"; x: 605 / 2 + 88 - 40; y: 100; width: 80 }
    }
}
