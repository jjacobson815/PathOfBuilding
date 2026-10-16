import QtQuick

// CraftCorruptPopup — ItemsTab:CorruptDisplayItem (ItemsTab.lua:2637-2970),
// "Corrupted Item" 605 x (103 + 20 * rows): Source (Corrupted / Scourge), Sort
// by and 2-4 "Implicit #n" dropdowns (a mod picked in one is dropped from its
// partner's list); for uniques the Implicits / Roll Ranges buttons switch to
// per-modifier roll sliders (0.78-1.22). The frame height is the session's,
// because legacy resizes the popup from its callbacks.
CraftPopupBase {
    id: root

    // Roll rows (legacy ItemsTab.lua:2795-2841): the y of each row grows by
    // 16 px per extra wrapped line of the rows above it.
    readonly property var rollRows: {
        const c = st && st.controls ? st.controls : ({})
        const idx = []
        for (const k in c) {
            const m = /^rollRangeSlider(\d+)$/.exec(k)
            if (m) idx.push(parseInt(m[1]))
        }
        idx.sort(function (a, b) { return a - b })
        let offset = 20
        const out = []
        for (let n = 0; n < idx.length; n++) {
            const i = idx[n]
            const lbl = (c["rollRangeLabel" + i] || ({})).label || ""
            const lines = lbl.split("\n")
            out.push({ i: i, y: 10 + offset, lines: lines })
            offset += 16 * (lines.length - 1) + 20
        }
        return out
    }

    Item {
        implicitWidth: 605
        implicitHeight: root.frameH

        CraftButton { craft: root; name: "implicits"; x: 5; y: 5; width: 80 }
        CraftButton { craft: root; name: "rolls"; x: 90; y: 5; width: 100 }

        CraftLabel { craft: root; staticLabel: "^7Source:"; rx: 95; y: 30; visible: root.rec("source").shown === true }
        CraftDrop { craft: root; name: "source"; x: 100; y: 30; width: 150; height: 18 }
        CraftLabel { craft: root; staticLabel: "^7Sort by:"; rx: 350; y: 20; visible: root.rec("sort").shown === true }
        CraftDrop { craft: root; name: "sort"; x: 355; y: 20; width: 240; height: 18 }

        Label {
            visible: root.rec("implicitCannotBeChangedLabel").shown === true
            x: 20; y: 55
            label: root.rec("implicitCannotBeChangedLabel").label || ""
            size: 16
        }
        Repeater {
            model: 4
            delegate: Item {
                readonly property int n: index + 1
                CraftLabel { craft: root; name: "implicit" + n + "Label"; rx: 75; y: 35 + 20 * n }
                CraftDrop { craft: root; name: "implicit" + n; x: 80; y: 35 + 20 * n; width: 440; height: 18 }
            }
        }

        Repeater {
            model: root.rollRows
            delegate: Row {
                id: rollRow
                readonly property int n: modelData.i
                readonly property var sliderRec: root.rec("rollRangeSlider" + n)
                visible: sliderRec.shown === true
                x: 10; y: modelData.y
                spacing: 5
                Label {
                    label: root.rec("rollRangeValue" + rollRow.n).label || ""
                    size: 16
                }
                Slider {
                    id: roll
                    width: 80; height: 18
                    property bool pushing: false
                    function push() {
                        if (dragging || rollRow.sliderRec.val === undefined) return
                        pushing = true
                        value = rollRow.sliderRec.val
                        pushing = false
                    }
                    Connections { target: rollRow; function onSliderRecChanged() { roll.push() } }
                    Component.onCompleted: push()
                    onValueChanged: if (!pushing) root.set("rollRangeSlider" + rollRow.n, value)
                }
                Column {
                    Repeater {
                        model: modelData.lines
                        delegate: Label { label: modelData; size: 16 }
                    }
                }
            }
        }

        CraftButton { craft: root; name: "save"; tip: true; x: 605 / 2 - 45 - 40; y: root.frameH - 24; width: 80 }
        CraftButton { craft: root; name: "close"; x: 605 / 2 + 45 - 40; y: root.frameH - 24; width: 80 }
    }
}
