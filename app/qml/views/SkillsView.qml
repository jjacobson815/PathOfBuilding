import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// SKILLS view (socket groups + active-skill DPS). Extracted from main.qml
// (Part 1.1); behaviour unchanged. Bound to socketGroupModel (groups + nested
// gems) and skillModel (active-skill DPS list). Selecting an active skill calls
// luaEngine.setActiveSkill(socketGroupIndex, displaySkillIndex). A themed
// "Add group + gem" control calls luaEngine.addSocketGroupWithGem(label, gemName).
// All colours come from the theme singleton. Visibility is parent-controlled.
Item {
    id: skillsView
    anchors.fill: parent
    clip: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.space3
        spacing: theme.space2

        Text {
            text: "Skills"
            color: theme.text
            font.bold: true
            font.pixelSize: theme.fontSize + 4
        }

        // --- Add group + gem control ---
        RowLayout {
            spacing: theme.space1
            TextField {
                id: skillGroupLabel
                Layout.fillWidth: true
                placeholderText: "Group label"
                color: theme.text
                background: Rectangle { color: theme.sideBarBg; border.color: theme.section; radius: theme.radiusControl }
            }
            TextField {
                id: skillGemName
                Layout.fillWidth: true
                placeholderText: "Gem name (e.g. Fireball)"
                color: theme.text
                background: Rectangle { color: theme.sideBarBg; border.color: theme.section; radius: theme.radiusControl }
            }
            Button {
                text: "Add"
                onClicked: {
                    if (skillGemName.text.trim() !== "") {
                        luaEngine.addSocketGroupWithGem(
                            skillGroupLabel.text.trim() || "New Group",
                            skillGemName.text.trim())
                        skillGroupLabel.text = ""
                        skillGemName.text = ""
                    }
                }
            }
        }

        // --- Socket groups (with nested gems) ---
        Text {
            text: "Socket groups: " + socketGroupModel.count
            color: theme.accent
            font.bold: true
        }
        ListView {
            id: socketGroupListView
            Layout.fillWidth: true
            Layout.preferredHeight: parent.height * 0.4
            model: socketGroupModel
            clip: true
            delegate: Rectangle {
                width: ListView.view.width
                height: gemRow.height + 8
                color: index % 2 ? theme.sideBarBg : "transparent"
                Column {
                    id: gemRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: theme.space1
                    spacing: 2
                    RowLayout {
                        width: parent.width
                        spacing: theme.space2
                        Text {
                            text: (model.enabled ? "✔" : "✖") + "  " + (model.title || "(untitled)")
                            color: model.enabled ? theme.text : theme.muted
                            font.pixelSize: theme.fontSize
                            Layout.fillWidth: true
                        elide: Text.ElideRight
                        clip: true
                        }
                        Text {
                            text: model.slot ? ("[" + model.slot + "]") : ""
                            color: theme.muted
                            font.pixelSize: theme.fontSize - 1
                        }
                        Text {
                            text: "main #" + model.mainActiveSkill
                            color: theme.muted
                            font.pixelSize: theme.fontSize - 1
                        }
                    }
                    // Nested gem list for this group.
                    ListView {
                        width: parent.width
                        height: Math.max(1, (model.gems ? model.gems.length : 0) * 20)
                        model: model.gems
                        clip: true
                        interactive: false
                        delegate: Text {
                            text: "   • " + (modelData.name || "?")
                                  + "  " + (modelData.level || 1) + "/" + (modelData.quality || 0)
                                  + (modelData.enabled ? "" : "  (disabled)")
                            color: theme.muted
                            font.pixelSize: theme.fontSize - 1
                        elide: Text.ElideRight
                        clip: true
                        }
                    }
                }
            }
        }

        // --- Active-skill DPS list ---
        Text {
            text: "Active skills (DPS):"
            color: theme.accent
            font.bold: true
        }
        ListView {
            id: activeSkillListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: skillModel
            clip: true
            delegate: Rectangle {
                width: ListView.view.width
                height: 24
                color: model.isMain ? theme.accent : (index % 2 ? theme.sideBarBg : "transparent")
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: theme.space1
                    spacing: theme.space2
                    Text {
                        text: (model.isMain ? "★ " : "  ") + (model.name || "?")
                        color: model.isMain ? theme.background : theme.text
                        font.pixelSize: theme.fontSize
                        Layout.fillWidth: true
                    elide: Text.ElideRight
                    clip: true
                    }
                    Text {
                        text: "DPS " + Math.round(model.totalDps || 0).toLocaleString()
                        color: model.isMain ? theme.background : theme.accent
                        font.pixelSize: theme.fontSize - 1
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        luaEngine.setActiveSkill(
                            model.socketGroupIndex,
                            model.displaySkillIndex)
                    }
                }
            }
        }
    }
}
