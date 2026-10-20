import QtQuick

// CraftEdit — a legacy EditControl of a captured craft popup (the Anoint
// search box, the Add Implicit custom line). Every keystroke is forwarded to
// the control's buffer; `quiet` skips the state re-read for free text only the
// Lua side needs.
EditControl {
    id: root

    property var craft: null
    property string name: ""
    property bool quiet: false
    readonly property var r: craft ? craft.rec(name) : ({})

    visible: r.shown === true
    controlEnabled: r.enabled !== false

    // Imperative push (a bound `text` breaks on the first edit); only when the
    // Lua side differs, so a refresh never resets the caret while typing.
    function push() { if (r.text !== undefined && r.text !== text) text = r.text }
    onRChanged: push()
    Component.onCompleted: push()

    onEdited: function (t) { if (craft) craft.set(name, t, quiet) }
}
