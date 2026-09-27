import QtQuick
import QtQuick.Layouts

// TattooPopup — Phase 4 Part 4.4, ports TreeTab:ModifyNodePopup
// (TreeTab.lua:868-1017), title "Replace Modifier of Node": the tattoos (or
// runegrafts, on a mastery) eligible for this node by target type and
// connection count, the chosen one's stat/reminder lines, Add / Reset Node /
// Cancel, the "Tattoo Count: x/50" button (hover lists every tattoo in the
// tree) and "Show Legacy Tattoos". All eligibility logic is pob_getTattooOptions.
PopupBase {
    id: root

    property int nodeId: -1
    property var tstate: ({ options: [] })
    readonly property var options: (tstate.options && tstate.options.length !== undefined) ? tstate.options : []
    readonly property var current: modSelect.currentIndex >= 0 && modSelect.currentIndex < options.length
                                   ? options[modSelect.currentIndex] : null
    signal changed()

    title: "Replace Modifier of Node"
    padding: 12

    function _load(showLegacy) {
        const s = luaEngine.invoke("pob_getTattooOptions", showLegacy === undefined ? [nodeId] : [nodeId, showLegacy])
        tstate = s ? s : ({ options: [] })
        modSelect.model = options
        modSelect.currentIndex = Math.max(0, (tstate.defaultIndex || 1) - 1)
        legacyCheck.state = !!tstate.showLegacy
    }

    function openFor(id) {
        nodeId = id
        _load()
        open()
    }

    ColumnLayout {
        width: 576
        spacing: 6

        RowLayout {
            spacing: 6
            Label { label: "^7Modifier:"; size: 16 }
            DropDownControl {
                id: modSelect
                Layout.preferredWidth: 250
                Layout.preferredHeight: 18
                popupMinWidth: 320
                labelFor: function (o) { return o ? o.name : "" }
                tooltipForItem: function (o, tt) {
                    if (!o) return
                    for (let i = 0; i < o.descriptions.length; i++) tt.addLine(16, "^7" + o.descriptions[i])
                }
            }
        }

        // The selected modifier's lines (constructUI, wrapped at 375px).
        Repeater {
            model: root.current ? root.current.descriptions : []
            delegate: ColorText {
                Layout.preferredWidth: 560
                sourceText: "^7" + modelData
                font.pixelSize: 16
                wrapMode: Text.WordWrap
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            Button {
                implicitWidth: 80; implicitHeight: 20
                label: "Add"
                controlEnabled: root.current !== null
                onClicked: {
                    luaEngine.invoke("pob_applyTattoo", [root.nodeId, modSelect.currentIndex + 1])
                    root.changed()
                    root.close()
                }
            }
            Button {
                implicitWidth: 80; implicitHeight: 20
                label: "Reset Node"
                onClicked: {
                    luaEngine.invoke("pob_resetTattooNode", [root.nodeId])
                    root.changed()
                    root.close()
                }
            }
            Button {
                implicitWidth: 80; implicitHeight: 20
                label: "Cancel"
                onClicked: root.reject()
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12
            Button {
                implicitWidth: 145; implicitHeight: 20
                label: "^7Tattoo Count: " + (root.tstate.tattooCountStr || "0") + "/50"
                tooltipFunc: function (tt) {
                    const lines = root.tstate.tattooLines
                    if (!lines || lines.length === undefined) return
                    for (let i = 0; i < lines.length; i++) tt.addLine(16, lines[i])
                }
            }
            CheckBox {
                id: legacyCheck
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                Layout.leftMargin: labelWidth + 12
                label: "Show Legacy Tattoos:"
                onToggled: function (s) { root._load(s) }
            }
        }
    }
}
