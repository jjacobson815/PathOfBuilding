import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// ITEMS view (item browser). Extracted from main.qml (Part 1.1); behaviour
// unchanged. Bound to itemModel (the build's item list). Selecting an item
// shows its details (mods) in a side panel. A themed "Add from text" TextArea +
// button calls luaEngine.addItemFromRaw(text). Rarity colours come from the
// theme singleton via the local rarityColor() helper (moved here from the root
// Window — it is only used by this view). Visibility is parent-controlled.
Item {
    id: itemsView
    anchors.fill: parent
    clip: true

    // Currently selected item's map (from itemModel) so the details panel can
    // show its mods. Local to this view (was a root Window property).
    property var selectedItem: null

    // Map an item rarity string to its theme colour (no hex hardcoded in QML).
    function rarityColor(r) {
        if (r === "NORMAL") return theme.rarityNormal
        if (r === "MAGIC") return theme.rarityMagic
        if (r === "RARE") return theme.rarityRare
        if (r === "UNIQUE") return theme.rarityUnique
        if (r === "RELIC") return theme.rarityRelic
        return theme.text
    }

    // "Add from text" panel (top)
    ColumnLayout {
        id: itemsAddPanel
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: theme.space2
        spacing: theme.space1
        Text {
            text: "Add item from text"
            color: theme.text
            font.bold: true
            font.pixelSize: theme.fontSize
        }
        RowLayout {
            spacing: theme.space1
            TextArea {
                id: itemRawInput
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                color: theme.text
                background: Rectangle { color: theme.sideBarBg; border.color: theme.section; radius: theme.radiusControl }
                placeholderText: "Paste item text (Rarity: ...)"
                font.pixelSize: theme.fontSize - 1
                wrapMode: Text.WordWrap
            }
            Button {
                text: "Add"
                onClicked: {
                    if (itemRawInput.text.trim() !== "") {
                        luaEngine.addItemFromRaw(itemRawInput.text)
                        itemRawInput.text = ""
                    }
                }
            }
        }
    }

    // Body: item list (left) + details (right)
    RowLayout {
        anchors.top: itemsAddPanel.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: theme.space2
        spacing: theme.space2

        // Item list
        ListView {
            id: itemListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: parent.width * 0.45
            model: itemModel
            clip: true
            highlight: Rectangle { color: theme.accent; radius: theme.radiusControl }
            focus: true
            delegate: Rectangle {
                width: ListView.view.width
                height: 30
                color: (ListView.isCurrentItem ? theme.accent
                       : (index % 2 ? theme.sideBarBg : "transparent"))
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: theme.space1
                    spacing: theme.space1
                    Text {
                        text: (model.isEquipped ? "● " : "") + (model.name || "?")
                        color: ListView.isCurrentItem ? theme.background : itemsView.rarityColor(model.rarity)
                        font.pixelSize: theme.fontSize
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    clip: true
                    }
                    Text {
                        text: model.baseName || model.type || ""
                        color: ListView.isCurrentItem ? theme.background : theme.muted
                        font.pixelSize: theme.fontSize - 2
                        elide: Text.ElideRight
                        Layout.preferredWidth: 120
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        itemListView.currentIndex = index
                        itemsView.selectedItem = itemModel.get(index)
                    }
                }
            }
        }

        // Details panel
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: parent.width * 0.55
            color: theme.sideBarBg
            border.color: theme.section
            radius: theme.radiusControl
            clip: true
            ScrollView {
                anchors.fill: parent
                anchors.margins: theme.space2
                contentWidth: width
                ColumnLayout {
                    spacing: theme.space1
                    width: parent.width
                    Text {
                        text: itemsView.selectedItem ? itemsView.selectedItem.name : "Select an item"
                        color: itemsView.selectedItem ? itemsView.rarityColor(itemsView.selectedItem.rarity) : theme.muted
                        font.bold: true
                        font.pixelSize: theme.fontSize + 2
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Text {
                        visible: itemsView.selectedItem
                        text: (itemsView.selectedItem ? (itemsView.selectedItem.baseName || itemsView.selectedItem.type || "") : "")
                              + (itemsView.selectedItem && itemsView.selectedItem.quality ? ("  (Quality: " + itemsView.selectedItem.quality + ")") : "")
                              + (itemsView.selectedItem && itemsView.selectedItem.level ? ("  (ilvl " + itemsView.selectedItem.level + ")") : "")
                        color: theme.muted
                        font.pixelSize: theme.fontSize - 1
                        Layout.fillWidth: true
                    elide: Text.ElideRight
                    clip: true
                    }
                    Text {
                        visible: itemsView.selectedItem && itemsView.selectedItem.isEquipped
                        text: "Equipped in: " + (itemsView.selectedItem ? itemsView.selectedItem.slotName : "")
                        color: theme.accent
                        font.pixelSize: theme.fontSize - 1
                        Layout.fillWidth: true
                    elide: Text.ElideRight
                    clip: true
                    }
                    Repeater {
                        model: itemsView.selectedItem ? itemsView.selectedItem.modLines : []
                        delegate: Text {
                            text: modelData
                            color: theme.text
                            font.pixelSize: theme.fontSize - 1
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }
}
