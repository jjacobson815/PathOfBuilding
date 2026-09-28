import QtQuick
import QtQuick.Window
import QtQuick.Controls as QC

// GemSelect — Phase 5, ports GemSelectControl.lua (an EditControl with a
// gem dropdown). The list, its matching (exact -> initials "ctf" -> prefix
// -> contains, plus :tag / :-tag filters), the DPS sort and the check / "+"
// markers all come from the LIVE control through pob_skillsGemCandidates;
// this file is the input + dropdown behaviour:
//   * focus opens the full list (BuildList("")), selecting the current gem;
//   * typing filters; Up/Down move the selection (Up past the top restores
//     the typed text);
//   * Enter picks the selection, else the TOP match, else clears;
//     a click on a row picks it; Esc reverts to the gem held on focus;
//   * focus lost with the list open keeps an exact name match, else clears
//     (legacy UpdateGem(true, true, true): on a gem row that deletes the gem);
//   * "S" / "A" boxes inside the right edge filter to Support / Active gems
//     (gem rows only); a click on the text body clears the filter (legacy);
//   * hover: collapsed -> the gem tooltip (pob_skillsGemTooltip); dropped ->
//     the hovered row's gem tooltip + "Selecting this gem will give you:".
//
// Deviation (documented): legacy live-previews the highlighted gem into the
// group while typing / arrowing (no recalc until a commit). Here nothing is
// written until a commit, so the build never holds a half-typed gem.
//
// `picked(id)` carries the data.gems id, or "" for "no gem".
FocusScope {
    id: root

    property int groupIndex: 0          // 1-based socket group
    property int row: 0                 // 0 = imbued selector, else gem row
    property string text: ""            // the committed gem name
    property string textColor: "^7"     // legacy inactiveCol (gem colour)
    property bool controlEnabled: true
    property bool imbued: row === 0
    property bool highlighted: false    // supporting-gem cross-highlight

    signal picked(string id)
    signal hoverChanged(bool on)

    readonly property bool dropped: listPopup.visible
    readonly property bool hovered: hoverMa.containsMouse
    property var rows: []
    property int selIndex: 0            // 0 = the typed text; else 1-based row
    property string filter: ""          // "", "support", "grants_active_skill"
    property string _initial: ""
    property string _search: ""
    property bool _noMatches: false
    property bool _settingText: false

    implicitWidth: 300
    implicitHeight: 20

    function _hex(code) {
        return (code && code.indexOf("^x") === 0) ? "#" + code.substr(2, 6) : theme.text
    }

    function _fetch(buf) {
        const r = luaEngine.invoke("pob_skillsGemCandidates", [groupIndex, row, buf, filter])
        rows = (r && r.rows && r.rows.length !== undefined) ? r.rows : []
        _noMatches = !r || r.noMatches || rows.length === 0
    }

    function _setText(t) {
        _settingText = true
        input.text = t
        _settingText = false
    }

    function openList() {
        if (!controlEnabled) return
        _initial = root.text
        _search = ""
        _fetch("")
        selIndex = 0
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].name === root.text) { selIndex = i + 1; break }
        }
        tip.hide()
        listPopup.open()
        if (selIndex > 0) list.positionViewAtIndex(selIndex - 1, ListView.Center)
    }

    function _commit(id) {
        listPopup.close()
        root.picked(id)
    }

    // Enter: the selection, else the top match; no match clears.
    function _enter() {
        if (_noMatches) { _setText(""); _commit(""); return }
        const i = Math.max(selIndex, 1) - 1
        _setText(rows[i].name)
        _commit(rows[i].id)
    }

    function _escape() {
        _setText(_initial)
        listPopup.close()
        input.focus = false
        root.focus = false
    }

    function _exactId(t) {
        const low = t.toLowerCase()
        for (let i = 0; i < rows.length; i++) if (rows[i].name.toLowerCase() === low) return rows[i].id
        return ""
    }

    function _move(delta) {
        if (!dropped) { openList(); return }
        let i = selIndex + delta
        if (i < 0) i = 0
        if (i > rows.length) i = rows.length
        selIndex = i
        _setText(i === 0 ? _search : rows[i - 1].name)
        if (i > 0) list.positionViewAtIndex(i - 1, ListView.Contain)
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        Chrome {
            anchors.fill: parent
            hovered: root.hovered
            locked: input.activeFocus
            controlEnabled: root.controlEnabled
        }
        Rectangle {                      // cross-highlight (0.33,1,0.33,0.25)
            anchors.fill: parent
            anchors.margins: 1
            visible: root.highlighted
            color: Qt.rgba(0.33, 1, 0.33, 0.25)
        }
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: root.imbued ? 4 : 40
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        text: root.text
        enabled: root.controlEnabled
        selectByMouse: true
        font.family: theme.fontVar
        font.pixelSize: 16
        color: !root.controlEnabled ? theme.muted
             : activeFocus ? theme.text : root._hex(root.textColor)
        selectionColor: theme.accent
        selectedTextColor: theme.background
        // EditControl filter "^ %a':-" (letters, space, apostrophe, colon, dash).
        validator: RegularExpressionValidator { regularExpression: /[A-Za-z ':\-]*/ }

        onTextEdited: {
            if (root._settingText) return
            root._search = text
            if (!root.dropped) { tip.hide(); listPopup.open() }
            root._fetch(text)
            root.selIndex = 0
        }
        onActiveFocusChanged: {
            if (activeFocus) {
                root.openList()
                selectAll()
            } else if (root.dropped && !rowMa.containsMouse) {
                // Focus lost while dropped: keep an exact match, else clear.
                const id = root._exactId(text)
                if (id === "") _setText("")
                root._commit(id)
            }
        }
        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Down) { root._move(1); event.accepted = true }
            else if (event.key === Qt.Key_Up) { root._move(-1); event.accepted = true }
            else if (event.key === Qt.Key_PageDown) { root._move(15); event.accepted = true }
            else if (event.key === Qt.Key_PageUp) { root._move(-15); event.accepted = true }
            else if (event.key === Qt.Key_Escape) { root._escape(); event.accepted = true }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.dropped) root._enter(); else root.openList()
                event.accepted = true
            }
        }
    }

    // A click on the text body clears the S/A filter (legacy 639-648).
    MouseArea {
        anchors.fill: input
        acceptedButtons: Qt.LeftButton
        propagateComposedEvents: true
        onPressed: function (mouse) {
            if (root.filter !== "") { root.filter = ""; if (root.dropped) root._fetch(input.text) }
            mouse.accepted = false
        }
    }

    // S / A overlay filter boxes (not on the imbued selector).
    Row {
        visible: !root.imbued
        anchors.right: parent.right
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Repeater {
            model: [ { t: "A", f: "grants_active_skill", tip: "Only show Active gems" },
                     { t: "S", f: "support", tip: "Only show Support gems" } ]
            delegate: Rectangle {
                width: 16; height: 16
                color: "transparent"
                border.width: 1
                border.color: boxMa.containsMouse || root.filter === modelData.f ? theme.text : theme.muted
                opacity: boxMa.containsMouse || root.filter === modelData.f ? 1.0 : 0.5
                Label {
                    anchors.centerIn: parent
                    label: modelData.t
                    size: 14
                }
                MouseArea {
                    id: boxMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.controlEnabled
                    onClicked: {
                        root.filter = modelData.f
                        if (!root.dropped) { input.forceActiveFocus() }
                        root._fetch(input.text === root.text && root._search === "" ? "" : input.text)
                        root.selIndex = 0
                        if (!root.dropped) listPopup.open()
                    }
                    onContainsMouseChanged: {
                        if (containsMouse) { tip.clear(); tip.addLine(16, modelData.tip); root._placeTip(0) }
                        else tip.hide()
                    }
                }
            }
        }
    }

    MouseArea {
        id: hoverMa
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onContainsMouseChanged: {
            root.hoverChanged(containsMouse)
            if (containsMouse && !root.dropped) root._showGemTip()
            else if (!root.dropped) tip.hide()
        }
    }

    function _fillTip(tt, t) {
        tt.clear()
        tt.maxWidth = 800
        if (!t || !t.lines) return
        for (let k = 0; k < t.lines.length; k++) {
            const l = t.lines[k]
            if (l.sep) tt.addSeparator(l.size)
            else tt.addLine(l.size, l.text.length > 0 ? l.text : " ")
        }
    }

    // Place the tooltip beside an item at local y `yOff` (row or control).
    function _placeTip(yOff, h) {
        if (tip.lines.length === 0) { tip.hide(); return }
        const win = Window.window
        const o = win ? root.mapToItem(win.contentItem, 0, 0) : Qt.point(0, 0)
        tip.showAt(0, yOff, width, h || height,
                   win ? Qt.rect(-o.x, -o.y, win.width, win.height) : Qt.rect(0, 0, width, height))
    }

    function _showGemTip() {
        if (root.groupIndex < 1) return
        _fillTip(tip, luaEngine.invoke("pob_skillsGemTooltip", [groupIndex, row]))
        _placeTip(0)
    }

    function _showRowTip(i) {
        if (i < 0 || i >= rows.length) { rowTip.hide(); return }
        _fillTip(rowTip, luaEngine.invoke("pob_skillsGemCandidateTooltip", [groupIndex, row, rows[i].key]))
        if (rowTip.lines.length === 0) { rowTip.hide(); return }
        const win = Window.window
        const host = rowTip.parent
        const o = win ? host.mapToItem(win.contentItem, 0, 0) : Qt.point(0, 0)
        rowTip.showAt(0, 2 + i * 16 - list.contentY, list.width, 16,
                      win ? Qt.rect(-o.x, -o.y, win.width, win.height) : Qt.rect(0, 0, host.width, host.height))
    }

    Tooltip { id: tip; z: 200 }

    // The dropdown: up to 15 rows of 16px below the control. A Popup so it
    // draws in the window overlay above the rows below; it never takes focus
    // (typing stays in the TextInput) and closes only through this file.
    QC.Popup {
        id: listPopup
        x: 0
        y: root.height
        width: root.width
        height: Math.max(1, Math.min(15, root.rows.length || 1)) * 16 + 4
        padding: 0
        focus: false
        modal: false
        closePolicy: QC.Popup.NoAutoClose
        onClosed: { rowTip.hide(); tip.hide() }

        background: Rectangle {
            color: "black"
            border.width: 1
            border.color: theme.text
        }
        contentItem: Item {
            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: 2
                anchors.rightMargin: sb.visible ? 18 : 2
                clip: true
                interactive: false
                model: root.rows.length > 0 ? root.rows
                     : [ { name: "<No matches>", color: "^7", marker: "", markerColor: "^7" } ]
                delegate: Rectangle {
                    width: list.width
                    height: 16
                    color: (index === rowMa.hoverRow || index === root.selIndex - 1
                            || (index === 0 && root.selIndex === 0)) ? Qt.rgba(0.2, 0.2, 0.2, 1) : "transparent"
                    Label {
                        x: 0
                        anchors.verticalCenter: parent.verticalCenter
                        label: modelData.color + modelData.name
                        size: 16
                    }
                    Label {
                        visible: modelData.marker === "plus"
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        label: modelData.markerColor + "+"
                        size: 16
                    }
                    CheckMark {
                        visible: modelData.marker === "check"
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12; height: 12
                        glyphColor: root._hex(modelData.markerColor)
                    }
                }
                onContentYChanged: sb.setOffset(contentY)
            }
            ScrollBar {
                id: sb
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 1
                width: 16
                visible: active
                dir: "VERTICAL"
                contentDim: root.rows.length * 16
                viewDim: list.height
                onOffsetChanged: list.contentY = offset
            }
            MouseArea {
                id: rowMa
                anchors.fill: list
                hoverEnabled: true
                property int hoverRow: -1
                onPositionChanged: function (mouse) {
                    const i = Math.floor((mouse.y + list.contentY) / 16)
                    hoverRow = (i >= 0 && i < root.rows.length) ? i : -1
                }
                onExited: hoverRow = -1
                onHoverRowChanged: root._showRowTip(hoverRow)
                onClicked: {
                    if (hoverRow < 0) return
                    const r = root.rows[hoverRow]
                    root._setText(r.name)
                    root._commit(r.id)
                    input.focus = false
                    root.focus = false
                }
                onWheel: function (wheel) { sb.handleWheel(wheel.angleDelta.y) }
            }
            // Row tooltip lives in the popup so it draws above the list.
            Tooltip { id: rowTip; z: 200 }
        }
    }
}
