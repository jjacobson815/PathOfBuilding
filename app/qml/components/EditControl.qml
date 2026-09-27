import QtQuick
import QtQuick.Window

// EditControl — Tier 3, ported from legacy EditControl.lua (751 lines).
//
// Legacy EditControl is an immediate-mode text field that hand-rolls
// everything SimpleGraphic doesn't give it: caret placement via
// DrawStringCursorIndex, selection ranges, scroll-to-caret, undo, filtering,
// placeholder ("prompt") text, and a capture-by-RETURN focus model.
//
// **Deliberate deviation (the Phase 1 input/focus decision, applied):** the
// caret, selection, clipboard and scroll-to-caret are handed to Qt's native
// `TextInput` rather than reproduced over TextMetrics. This is NOT the same
// call as the measurement rule. The "never use QFontMetrics" rule exists so
// LAYOUT matches legacy pixel-for-pixel (auto-width columns, ellipsis points,
// mouse-x -> character index over legacy-rendered text). Here the text is
// rendered BY Qt, so the caret must be placed with the same metrics Qt used
// to draw the glyphs — measuring with the .tgf atlas and drawing with the TTF
// would put the caret visibly off the character it belongs to. TextMetrics is
// still the right tool for sizing this control from the outside (see
// `measuredWidth`), and that is what it is exposed for.
//
// What IS ported faithfully:
//   - ENTER commits, ESC reverts to the value held at focus-in (legacy
//     `EditControl:OnKeyUp` RETURN/ESCAPE), focus-out commits.
//   - Placeholder/"prompt" text shown only while empty AND unfocused.
//   - Character filtering (`filterFunc`) and a numeric mode with clamping,
//     mirroring legacy's `filter`/`filterFormat` + `SetText` clamp.
//   - Select-all on focus-in.
//   - Tooltip integration on the same contract as Button/CheckBox
//     (`tooltipFunc(tooltip)` for rich content, else plain `tooltipText`).
//
// Numeric clamping happens on COMMIT, never per keystroke — clamping while
// typing makes intermediate states ("1" on the way to "15" with min=10)
// impossible to type through, which is exactly the bug legacy avoids by
// clamping in SetText rather than in the key handler.
Item {
    id: root

    // --- value ---
    property string text: ""
    property string placeholder: ""
    property bool readOnly: false
    property bool controlEnabled: true

    // --- filtering ---
    property bool isNumeric: false
    property bool allowNegative: false
    property bool allowDecimal: false
    property int maxChars: 0             // 0 = unlimited
    // function(ch) -> bool ; consulted per character when set (legacy `filter`)
    property var filterFunc: null
    // Numeric clamp bounds. Leave undefined for "no bound".
    property var numericMin: undefined
    property var numericMax: undefined

    // --- presentation ---
    property int size: theme.fontSize
    property bool selectAllOnFocus: true
    property bool useFixedFont: false
    property alias horizontalAlignment: input.horizontalAlignment

    // --- tooltip (same contract as Button.qml) ---
    property string tooltipText: ""
    property var tooltipFunc: null
    property bool noTooltip: false

    readonly property bool hovered: hoverMa.containsMouse
    readonly property bool editing: input.activeFocus
    readonly property bool empty: input.text.length === 0
    // Legacy-parity width of the CURRENT text, for callers that need to size a
    // column the way SimpleGraphic would have. This is the TextMetrics path.
    readonly property real measuredWidth:
        textMetrics.width(root.size, root.useFixedFont ? "FIXED" : "VAR", input.text)

    signal edited(string text)        // live, per accepted keystroke
    signal committed(string text)     // ENTER, or focus-out with a changed value
    signal reverted()                 // ESC

    implicitWidth: 120
    implicitHeight: theme.controlSize

    // Value held at focus-in; ESC restores it.
    property string _preEditText: ""
    // Set while we are writing back into `text` ourselves, so onTextChanged
    // can tell an external model update from our own echo.
    property bool _internalWrite: false

    Chrome {
        anchors.fill: parent
        hovered: root.hovered
        // A focused field reads as "active", matching legacy's focus highlight.
        locked: root.editing
        controlEnabled: root.controlEnabled && !root.readOnly
    }

    TextInput {
        id: input

        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        verticalAlignment: TextInput.AlignVCenter
        clip: true

        text: root.text
        readOnly: root.readOnly || !root.controlEnabled
        enabled: root.controlEnabled
        selectByMouse: true
        activeFocusOnPress: true
        // maximumLength rejects at the source; the sanitizer below still runs
        // for the paste path, which can arrive over-length in one edit.
        maximumLength: root.maxChars > 0 ? root.maxChars : 32767

        color: root.controlEnabled ? theme.text : theme.muted
        selectionColor: theme.accent
        selectedTextColor: theme.background
        font.family: root.useFixedFont ? theme.fontFixed : theme.fontVar
        font.pixelSize: root.size

        // Themed caret. TextInput owns its X position (see the deviation note
        // in the header) — this delegate only controls how it LOOKS.
        cursorDelegate: Rectangle {
            width: 1
            color: theme.accent
            visible: input.activeFocus
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: input.activeFocus
                NumberAnimation { to: 0; duration: 500 }
                NumberAnimation { to: 1; duration: 500 }
            }
        }

        onTextEdited: {
            var clean = root._sanitize(input.text)
            if (clean !== input.text) {
                // Reject the disallowed characters without moving the caret to
                // the end: put the caret back where it was minus what we cut.
                var pos = Math.max(0, input.cursorPosition - (input.text.length - clean.length))
                input.text = clean
                input.cursorPosition = pos
            }
            root._internalWrite = true
            root.text = input.text
            root._internalWrite = false
            root.edited(input.text)
        }

        onActiveFocusChanged: {
            if (activeFocus) {
                root._preEditText = input.text
                if (root.selectAllOnFocus) input.selectAll()
            } else {
                input.deselect()
                root._commit()
            }
        }

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                root.revert()
                event.accepted = true
            }
        }
        // RETURN/ENTER both commit, matching legacy's KEY_RETURN handling.
        onAccepted: root._commit()
    }

    // Placeholder ("prompt"). Rendered through Label so colour codes in the
    // prompt text work the same as everywhere else.
    Label {
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        visible: root.empty && !input.activeFocus && root.placeholder.length > 0
        label: root.placeholder
        size: root.size
        defaultColor: theme.mutedDark
    }

    // Hover is tracked on a non-accepting area so it coexists with
    // TextInput's own mouse handling (selectByMouse) instead of stealing it.
    MouseArea {
        id: hoverMa
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    Tooltip { id: tt }

    // --- external model updates -------------------------------------------
    // When `text` is changed from outside (an engine refresh, a set swap),
    // adopt it as the new revert baseline so a later ESC doesn't resurrect a
    // value the model has already moved past.
    onTextChanged: {
        if (!_internalWrite && !input.activeFocus) _preEditText = root.text
    }

    // --- API ---------------------------------------------------------------
    function revert() {
        _internalWrite = true
        root.text = _preEditText
        _internalWrite = false
        input.text = _preEditText
        input.selectAll()
        root.reverted()
    }

    function commit() { _commit() }

    function selectAll() { input.selectAll() }

    function forceEditFocus() { input.forceActiveFocus() }

    // --- internals ---------------------------------------------------------
    function _commit() {
        var value = input.text
        if (root.isNumeric) value = root._clamp(value)
        if (value !== input.text) {
            input.text = value
            _internalWrite = true
            root.text = value
            _internalWrite = false
        }
        if (value !== _preEditText) {
            _preEditText = value
            root.committed(value)
        }
    }

    function _sanitize(s) {
        var out = ""
        var seenDot = false
        for (var i = 0; i < s.length; i++) {
            var ch = s.charAt(i)
            if (root.isNumeric) {
                if (ch >= "0" && ch <= "9") { out += ch; continue }
                if (ch === "-" && root.allowNegative && out.length === 0) { out += ch; continue }
                if (ch === "." && root.allowDecimal && !seenDot) { seenDot = true; out += ch; continue }
                continue
            }
            if (root.filterFunc && !root.filterFunc(ch)) continue
            out += ch
        }
        if (root.maxChars > 0 && out.length > root.maxChars)
            out = out.substring(0, root.maxChars)
        return out
    }

    function _clamp(s) {
        if (s.length === 0 || s === "-") return s
        var n = root.allowDecimal ? parseFloat(s) : parseInt(s, 10)
        if (isNaN(n)) return ""
        if (root.numericMin !== undefined && n < root.numericMin) n = root.numericMin
        if (root.numericMax !== undefined && n > root.numericMax) n = root.numericMax
        return String(n)
    }

    function _showTooltip() {
        if (!root.hovered) { tt.hide(); return }
        if (root.noTooltip) { tt.hide(); return }
        tt.clear()
        if (root.tooltipFunc) root.tooltipFunc(tt)
        else if (root.tooltipText) tt.addLine(14, root.tooltipText)
        if (tt.lines.length > 0) {
            var win = Window.window
            var origin = win ? root.mapToItem(win.contentItem, 0, 0) : Qt.point(0, 0)
            var viewport = win ? Qt.rect(-origin.x, -origin.y, win.width, win.height)
                               : Qt.rect(0, 0, root.width, root.height)
            tt.showAt(0, 0, root.width, root.height, viewport)
            return
        }
        tt.hide()
    }

    onHoveredChanged: _showTooltip()
    onTooltipTextChanged: _showTooltip()
    onNoTooltipChanged: _showTooltip()
}
