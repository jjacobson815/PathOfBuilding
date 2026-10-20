import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QC
import "StatDiff.js" as StatDiff

// ItemTextPopup — Phase 6 Part 6.3: ItemsTab:EditDisplayItemText
// (ItemsTab.lua:2225-2273). "Edit Item Text" for the display item (Edit...)
// or "Create Custom Item from Text" (Create custom...): a rarity dropdown,
// a fixed-font text box, Save/Create (enabled only while the text parses to
// an item with a base; its tooltip is the item, or the "item is invalid"
// help) and Cancel. Bridge: pob_itemsEditTextInit / Check / Save.
//
// Legacy re-validates every frame; here the check runs 200 ms after the last
// keystroke (a one-shot timer, no frame loop).
PopupBase {
    id: root

    property bool alsoAdd: false
    property bool valid: false
    property var _tipLines: null

    padding: 12

    function openFor(alsoAddItem) {
        alsoAdd = !!alsoAddItem
        const init = luaEngine.invoke("pob_itemsEditTextInit", []) || {}
        title = init.title || ""
        saveBtn.label = init.saveLabel || "Save"
        rarity.model = init.rarities && init.rarities.length !== undefined ? init.rarities : []
        rarity.currentIndex = (init.raritySel || 3) - 1
        area.text = init.text || ""
        _check()
        open()
        area.forceActiveFocus()
    }

    function _check() {
        const r = luaEngine.invoke("pob_itemsEditTextCheck", [area.text, rarity.currentIndex + 1])
        valid = !!(r && r.valid)
        _tipLines = r
    }

    function _save() {
        if (!valid) return
        const r = luaEngine.invoke("pob_itemsEditTextSave", [area.text, rarity.currentIndex + 1, alsoAdd])
        if (r && r.ok) accept()
    }

    Timer {
        id: checkTimer
        interval: 200
        onTriggered: root._check()
    }

    ColumnLayout {
        implicitWidth: 480
        spacing: 8

        RowLayout {
            spacing: 6
            Label { label: "^7Rarity:"; size: 16 }
            DropDownControl {
                id: rarity
                Layout.preferredWidth: 100
                Layout.preferredHeight: 18
                onSelected: function (i) { root._check() }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 420
            color: theme.background
            border.width: 1
            border.color: area.activeFocus ? theme.text : theme.border
            QC.ScrollView {
                anchors.fill: parent
                anchors.margins: 2
                QC.TextArea {
                    id: area
                    color: theme.text
                    font.family: theme.fontFixed
                    font.pixelSize: 14
                    wrapMode: TextEdit.NoWrap
                    selectByMouse: true
                    background: null
                    onTextChanged: checkTimer.restart()
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            Button {
                id: saveBtn
                implicitWidth: 80; implicitHeight: 20
                label: "Save"
                controlEnabled: root.valid
                forceTooltip: true
                tooltipFunc: function (tt) { StatDiff.fillFromLines(tt, root._tipLines) }
                onClicked: root._save()
            }
            Button {
                implicitWidth: 80; implicitHeight: 20
                label: "Cancel"
                onClicked: root.reject()
            }
        }
    }
}
