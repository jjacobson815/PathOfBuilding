import QtQuick
import QtQuick.Window
import "StatDiff.js" as StatDiff
import "QmlBridge.js" as QmlBridge

// ConfigOptionRow — Data-driven control factory for a single ConfigOptions entry
// (Phase 7 Part 7.1). Renders the right-aligned label + control keyed on
// `option.type` (check / count / countAllowZero / integer / float / list / text),
// with placeholder support, dynamic tooltip/tooltipFunc, and legacy modified/
// invalid border & red-label highlighting.
Item {
    id: root

    property var option: null
    signal valueChanged(string varName, var newValue)

    readonly property string optVar: option && option.var ? String(option.var) : ""
    readonly property string optType: option && option.type ? String(option.type) : ""
    readonly property bool isCheck: optType === "check"
    readonly property bool isNum: optType === "count" || optType === "countAllowZero" || optType === "integer" || optType === "float"
    readonly property bool isList: optType === "list"
    readonly property bool isText: optType === "text"
    readonly property string borderState: option && option.borderState ? String(option.borderState) : "normal"
    readonly property bool hasTooltip: !!(option && option.hasTooltip)

    readonly property color highlightBorderColor:
        borderState === "invalid" ? Qt.rgba(0.753, 0.502, 0.502, 1)
        : borderState === "modified" ? Qt.rgba(0.451, 0.576, 0.702, 1)
        : "transparent"

    implicitWidth: 352
    implicitHeight: isText ? 42 : 20
    width: 352
    height: implicitHeight

    function syncFromOption() {
        if (!option) return
        var t = option.type ? String(option.type) : ""
        if (t === "check") {
            checkCtrl.state = (option.value === true)
        } else if (t === "count" || t === "countAllowZero" || t === "integer" || t === "float") {
            if (!numCtrl.editing) {
                numCtrl.text = option.textValue !== undefined ? String(option.textValue) : ""
            }
            numCtrl.placeholder = option.placeholder !== undefined ? String(option.placeholder) : ""
        } else if (t === "list") {
            var opts = QmlBridge.toArray(option.options)
            listCtrl.model = opts
            listCtrl.currentIndex = (option.selIndex !== undefined ? Number(option.selIndex) : 1) - 1
        } else if (t === "text") {
            if (!textCtrl.editing) {
                textCtrl.text = option.textValue !== undefined ? String(option.textValue) : ""
            }
            textCtrl.placeholder = option.placeholder !== undefined ? String(option.placeholder) : ""
        }
    }

    onOptionChanged: syncFromOption()
    Component.onCompleted: syncFromOption()

    function _fillTooltip(tt, hoverVal) {
        if (!optVar) return
        var args = hoverVal !== undefined ? [optVar, hoverVal] : [optVar]
        var res = luaEngine.invoke("pob_configTooltip", args)
        StatDiff.fillFromLines(tt, res)
    }

    // Label on the left (right-aligned for non-text controls, top-left for text)
    Item {
        id: labelArea
        x: 2
        y: 0
        width: root.isText ? 348 : 222
        height: 18
        clip: true

        Label {
            id: optLabel
            objectName: "pob.configRow.label"
            anchors.right: root.isText ? undefined : parent.right
            anchors.left: root.isText ? parent.left : undefined
            anchors.verticalCenter: parent.verticalCenter
            label: root.option && root.option.displayLabel ? String(root.option.displayLabel) : ""
            size: {
                var raw = root.option && root.option.label ? String(root.option.label) : ""
                return textMetrics.width(14, "VAR", raw) > 220 ? 12 : 14
            }
        }

        MouseArea {
            id: labelMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.isCheck ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (root.isCheck) {
                    var next = !checkCtrl.state
                    checkCtrl.state = next
                    root.valueChanged(root.optVar, next)
                }
            }
            onContainsMouseChanged: {
                if (!containsMouse || !root.hasTooltip) { labelTip.hide(); return }
                labelTip.clear()
                root._fillTooltip(labelTip)
                if (labelTip.lines.length > 0) {
                    var win = Window.window
                    var o = win ? labelMa.mapToItem(win.contentItem, 0, 0) : Qt.point(0, 0)
                    labelTip.showAt(0, 0, labelMa.width, labelMa.height,
                        win ? Qt.rect(-o.x, -o.y, win.width, win.height) : Qt.rect(0, 0, width, height))
                }
            }
        }
        Tooltip { id: labelTip }
    }

    // 1. CheckBox control
    CheckBox {
        id: checkCtrl
        objectName: "pob.configRow.checkCtrl"
        visible: root.isCheck
        x: 228
        y: 1
        width: 18
        height: 18
        borderFunc: root.borderState === "invalid"
            ? function() { return [0.753, 0.502, 0.502] }
            : root.borderState === "modified"
                ? function() { return [0.451, 0.576, 0.702] }
                : null
        noTooltip: !root.hasTooltip
        tooltipFunc: function(tt) { root._fillTooltip(tt) }
        onToggled: function(newState) {
            root.valueChanged(root.optVar, newState)
        }
    }

    // 2. Numeric EditControl (count / countAllowZero / integer / float)
    Item {
        visible: root.isNum
        x: 228
        y: 1
        width: 90
        height: 18

        EditControl {
            id: numCtrl
            objectName: "pob.configRow.numCtrl"
            anchors.fill: parent
            isNumeric: true
            allowNegative: root.optType === "integer" || root.optType === "countAllowZero"
            allowDecimal: root.optType === "float"
            maxChars: 10
            size: 14
            noTooltip: !root.hasTooltip
            tooltipFunc: function(tt) { root._fillTooltip(tt) }
            onCommitted: function(txt) {
                root.valueChanged(root.optVar, txt)
            }
        }
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 1
            border.color: root.highlightBorderColor
            visible: root.borderState !== "normal" && !numCtrl.editing
            z: 2
        }
    }

    // 3. List DropDownControl
    Item {
        visible: root.isList
        x: 228
        y: 1
        width: 120
        height: 18

        DropDownControl {
            id: listCtrl
            objectName: "pob.configRow.listCtrl"
            anchors.fill: parent
            size: 14
            popupMinWidth: 160
            noTooltip: !root.hasTooltip
            tooltipFunc: function(tt) { root._fillTooltip(tt) }
            tooltipForItem: function(item, tt) {
                if (item && item.val !== undefined) root._fillTooltip(tt, item.val)
            }
            onSelected: function(idx) {
                var opts = root.option ? QmlBridge.toArray(root.option.options) : []
                if (idx >= 0 && idx < opts.length) {
                    root.valueChanged(root.optVar, opts[idx].val)
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 1
            border.color: root.highlightBorderColor
            visible: root.borderState !== "normal"
            z: 2
        }
    }

    // 4. Text EditControl
    Item {
        visible: root.isText
        x: 4
        y: 20
        width: 344
        height: 20

        EditControl {
            id: textCtrl
            objectName: "pob.configRow.textCtrl"
            anchors.fill: parent
            size: 14
            noTooltip: !root.hasTooltip
            tooltipFunc: function(tt) { root._fillTooltip(tt) }
            onCommitted: function(txt) {
                root.valueChanged(root.optVar, txt)
            }
        }
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 1
            border.color: root.highlightBorderColor
            visible: root.borderState !== "normal" && !textCtrl.editing
            z: 2
        }
    }
}
