import QtQuick
import "StatDiff.js" as StatDiff

// CraftPopupBase — shell shared by the four display-item craft popups (Phase 6
// Part 6.3 item 2: Enchant / Anoint / Corrupt / Add Implicit).
//
// Legacy builds each popup as a local `controls` table handed to main:OpenPopup.
// The bridge (pob_items.lua "Craft popups") CAPTURES that table and keeps it as
// one craft session; this shell only renders the session state `st` and
// forwards user actions by control NAME:
//   openCraft(kind, slot)   pob_itemsCraftOpen   -> st (open() on success)
//   rec(name)               one control's record ("a.b" = a sub-control of list a)
//   set(name, value)        pob_itemsCraftSet    (selFunc / changeFunc runs in Lua)
//   click(name)             pob_itemsCraftClick  (closes when legacy would)
//   fillTip(tt, name, i)    pob_itemsCraftTooltip -> tooltip lines
// Closing in any way ends the session (pob_itemsCraftClose; legacy Cancel only
// closes). The frame size comes from the session (`st.width` / `st.height`):
// legacy callbacks resize the popup (Corrupt's Scourge / Roll Ranges).
PopupBase {
    id: root

    property var st: ({})
    readonly property bool live: st && st.open === true
    readonly property real frameW: (st && st.width) ? st.width : 400
    readonly property real frameH: (st && st.height) ? st.height : 100

    padding: 0

    function _invoke(fn, args) { return luaEngine.invoke(fn, args || []) }

    function openCraft(kind, slot) {
        const r = _invoke("pob_itemsCraftOpen", [kind, slot])
        if (!r || r.open !== true) return false
        st = r
        title = r.title || ""
        open()
        return true
    }

    function rec(name) {
        const c = st && st.controls ? st.controls : null
        if (!c) return ({})
        const dot = name.indexOf(".")
        if (dot < 0) return c[name] || ({})
        const parent = c[name.substring(0, dot)]
        return (parent && parent.sub && parent.sub[name.substring(dot + 1)]) || ({})
    }

    function refresh() {
        const r = _invoke("pob_itemsCraftState")
        if (r && r.open === true) st = r
        else if (visible) close()
    }

    // `quiet`: do not re-read the state (free-text fields that only the Lua
    // side needs until the popup is applied).
    function set(name, value, quiet) {
        const r = _invoke("pob_itemsCraftSet", [name, value])
        if (!r) return
        if (r.open === true) { if (!quiet) st = r }
        else if (r.ok === true) close()
    }

    function click(name) {
        const r = _invoke("pob_itemsCraftClick", [name])
        if (!r || r.ok !== true) { refresh(); return }
        if (r.closed === true) close()
        else refresh()
    }

    function fillTip(tt, name, index) {
        StatDiff.fillFromLines(tt, _invoke("pob_itemsCraftTooltip", [name, index]))
    }

    onClosed: _invoke("pob_itemsCraftClose")
}
