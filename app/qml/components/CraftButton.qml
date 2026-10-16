import QtQuick

// CraftButton — a legacy ButtonControl of a captured craft popup. Its label is
// the control's live label (the Anoint save button reads "Anoint X" /
// "Remove X" / "No Anoint"); `tip: true` shows the control's own tooltip (the
// item as it would be after the action).
Button {
    id: root

    property var craft: null
    property string name: ""
    property bool tip: false
    readonly property var r: craft ? craft.rec(name) : ({})

    visible: r.shown === true
    height: 20
    label: r.label || ""
    controlEnabled: r.enabled !== false
    forceTooltip: tip
    tooltipFunc: tip ? function (tt) { if (craft) craft.fillTip(tt, name, 0) } : null
    onClicked: if (craft) craft.click(name)
}
