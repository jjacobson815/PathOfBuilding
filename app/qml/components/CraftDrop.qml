import QtQuick
import "QmlBridge.js" as QmlBridge

// CraftDrop — a legacy DropDownControl of a captured craft popup, driven by
// name through CraftPopupBase (`craft`). Rows are { label, i } so the 1-based
// index reaches the row tooltip; every craft dropdown filters while dropped
// (legacy SearchHost behaviour).
DropDownControl {
    id: root
    objectName: "pob.craftDrop.root"

    property var craft: null
    property string name: ""
    readonly property var r: craft ? craft.rec(name) : ({})

    visible: r.shown === true
    controlEnabled: r.enabled !== false
    searchable: true
    maxVisibleItems: 14

    // Imperative push: DropDownControl writes its own currentIndex on a pick.
    function push() {
        const arr = QmlBridge.toArray(r ? r.list : null)
        if (arr.length === 0) { model = []; currentIndex = -1; return }
        const m = []
        for (let i = 0; i < arr.length; i++) m.push({ label: arr[i], i: i + 1 })
        model = m
        currentIndex = r.sel !== undefined ? r.sel - 1 : -1
    }
    onRChanged: push()
    Component.onCompleted: push()

    onSelected: function (i) { if (craft) craft.set(name, i + 1) }
    tooltipForItem: function (item, tt) { if (craft) craft.fillTip(tt, name, item.i) }
}
