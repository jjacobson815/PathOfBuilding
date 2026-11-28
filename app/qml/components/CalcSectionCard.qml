import QtQuick
import "QmlBridge.js" as QmlBridge

// CalcSectionCard — Phase 8 Part 8.1.
// Ports CalcSectionControl (CalcSectionControl.lua) for a single CalcSections
// card: coloured 2px border, collapsible primary/secondary subsections with
// +/- toggles, search-match highlighting (^xFF0000), multi-column cells with
// hover/click breakdown signalling, and inline SkillSelect controls for the
// "View Skill Details" section (independent *Calcs selectors + Calculation Mode).
Rectangle {
    id: root

    property var sectionObj: ({})
    property var skillSelect: null
    property var searchMatches: ({})
    property string activeCellKey: ""
    property Item coordTarget: null

    signal toggleSubsection(int sectionIndex, int subIndex)
    signal cellHovered(string cellKey, rect cellRect)
    signal cellUnhovered(string cellKey)
    signal cellClicked(string cellKey, rect cellRect)
    signal skillFieldChanged(string field, var value)
    signal inputChanged(string name, var value)
    signal manageSpectresRequested()

    readonly property var _subs: sectionObj ? QmlBridge.toArray(sectionObj.subs) : []
    readonly property string borderCol: (sectionObj && sectionObj.colour) ? sectionObj.colour : "#FFFFFF"
    readonly property int cardWidth: (sectionObj && sectionObj.width) ? sectionObj.width : 230
    readonly property int secIndex: (sectionObj && sectionObj.index) ? sectionObj.index : 0
    readonly property bool isSpecial: !!(sectionObj && sectionObj.special)

    width: cardWidth
    height: Math.max(22, cardCol.implicitHeight + 4)
    color: "#1A1A1A"
    border.width: 2
    border.color: borderCol

    function _matched(key) {
        return !!(searchMatches && searchMatches[key] === true)
    }

    function _indexOf(list, key, value) {
        if (!list || list.length === undefined) return -1
        for (var i = 0; i < list.length; i++) {
            if (list[i] && typeof list[i] === "object" && list[i][key] === value) return i
        }
        return list.length > 0 ? 0 : -1
    }

    function _rectInHost(item) {
        var target = root.coordTarget || root.parent
        if (!item || !target) return Qt.rect(0, 0, 0, 0)
        var pt = item.mapToItem(target, 0, 0)
        return Qt.rect(pt.x, pt.y, item.width, item.height)
    }

    Column {
        id: cardCol
        x: 2
        y: 2
        width: root.width - 4
        spacing: 0
        clip: true

        Repeater {
            model: root._subs.length
            delegate: Column {
                id: subCol
                readonly property var subObj: root._subs[index] || ({})
                readonly property var subRows: QmlBridge.toArray(subObj.rows)
                readonly property string subKey: root.secIndex + ":" + (subObj.index || (index + 1))
                width: cardCol.width
                spacing: 0

                // Top divider for secondary subsections
                Rectangle {
                    visible: index > 0
                    width: parent.width
                    height: 2
                    color: root.borderCol
                }

                // Subsection header bar (20px)
                Item {
                    width: parent.width
                    height: 20

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 3
                        anchors.right: toggleBtn.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        clip: true

                        ColorText {
                            sourceText: (root._matched(subCol.subKey) ? "^xFF0000" : "^7") + (subCol.subObj.label || "") + ":"
                            defaultColor: "#FFFFFF"
                            font.bold: true
                            font.pixelSize: 14
                        }
                        ColorText {
                            visible: !!(subCol.subObj.extra && subCol.subObj.extra.length > 0)
                            sourceText: "^7" + (subCol.subObj.extra || "")
                            defaultColor: "#FFFFFF"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }

                    // +/- collapse button (CalcSectionControl.lua:50-55)
                    Rectangle {
                        id: toggleBtn
                        objectName: "pob.calcsCard.toggleBtn"
                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        color: toggleMouse.containsMouse ? "#444444" : "#262626"
                        border.width: 1
                        border.color: root.borderCol

                        Text {
                            anchors.centerIn: parent
                            text: subCol.subObj.collapsed ? "+" : "-"
                            color: "#FFFFFF"
                            font.pixelSize: 12
                            font.bold: true
                        }

                        MouseArea {
                            id: toggleMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleSubsection(root.secIndex, subCol.subObj.index || (index + 1))
                        }
                    }
                }

                // Bottom divider under header when expanded
                Rectangle {
                    visible: !subCol.subObj.collapsed && subCol.subRows.length > 0
                    width: parent.width
                    height: 2
                    color: root.borderCol
                }

                // Data rows
                Repeater {
                    model: subCol.subObj.collapsed ? 0 : subCol.subRows.length
                    delegate: Item {
                        id: rowBox
                        readonly property var rowObj: subCol.subRows[index] || ({})
                        readonly property var rowCells: rowObj ? QmlBridge.toArray(rowObj.cells) : []
                        readonly property string rowKey: subCol.subKey + ":" + (rowObj.index || (index + 1))
                        readonly property string rowBg: rowObj.bgCol || "#000000"
                        width: subCol.width
                        height: root.isSpecial && rowCells.length > 0 && rowCells[0].control ? 22 : 18

                        // Left 126px label cell (fits 126 + 6*96 = 702 === cardCol.width on 3-col cards)
                        Rectangle {
                            id: labelBg
                            x: 0
                            y: 0
                            width: 126
                            height: parent.height
                            color: (rowBox.rowObj.label && rowBox.rowObj.label.length > 0) ? rowBox.rowBg : "transparent"

                            ColorText {
                                objectName: "pob.calcsCard.label"
                                visible: !!(rowBox.rowObj.label && rowBox.rowObj.label.length > 0)
                                anchors.right: parent.right
                                anchors.rightMargin: 3
                                anchors.left: parent.left
                                anchors.leftMargin: 2
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                sourceText: (root._matched(rowBox.rowKey) ? "^xFF0000" : (rowBox.rowObj.color || "^7"))
                                            + (rowBox.rowObj.label || "") + "^7:"
                                defaultColor: "#FFFFFF"
                                font.pixelSize: 13
                                elide: Text.ElideLeft
                            }
                        }

                        // Value / control cells
                        Row {
                            x: 126
                            y: 0
                            height: parent.height
                            spacing: 0

                            Repeater {
                                model: rowBox.rowCells.length
                                delegate: Item {
                                    id: cellWrap
                                    objectName: "pob.calcsCard.cellWrap"
                                    readonly property var cellObj: rowBox.rowCells[index] || ({})
                                    readonly property bool isActive: cellObj.key !== undefined && cellObj.key === root.activeCellKey
                                    readonly property bool isInteractive: !!(cellObj && cellObj.breakdown)
                                    readonly property string ctrlName: (cellObj && cellObj.control) ? String(cellObj.control) : ""
                                    width: Math.min(cellObj.width || (rowBox.width - 126),
                                                    Math.max(24, Math.floor((rowBox.width - 126) / Math.max(1, rowBox.rowCells.length))))
                                    height: rowBox.height

                                    // 2px vertical separator (section.colour)
                                    Rectangle {
                                        x: 0; y: 0; width: 2; height: parent.height
                                        color: root.borderCol
                                    }

                                    // Formatted stat value cell
                                    Rectangle {
                                        objectName: "pob.calcsCard.activeHl"
                                        visible: cellWrap.ctrlName.length === 0
                                        x: 2; y: 0
                                        width: parent.width - 2
                                        height: parent.height
                                        color: cellWrap.isActive ? "#40FF40" : rowBox.rowBg

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: cellWrap.isActive ? 1 : 0
                                            color: rowBox.rowBg
                                            clip: true

                                            ColorText {
                                                anchors.left: parent.left
                                                anchors.leftMargin: 3
                                                anchors.right: parent.right
                                                anchors.rightMargin: 2
                                                anchors.verticalCenter: parent.verticalCenter
                                                sourceText: cellWrap.cellObj.text || ""
                                                defaultColor: "#FFFFFF"
                                                font.pixelSize: rowBox.rowObj.textSize || 13
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MouseArea {
                                            objectName: "pob.calcsCard.cellMouse"
                                            anchors.fill: parent
                                            hoverEnabled: cellWrap.isInteractive
                                            enabled: cellWrap.isInteractive
                                            cursorShape: cellWrap.isInteractive ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onEntered: root.cellHovered(cellWrap.cellObj.key, root._rectInHost(cellWrap))
                                            onExited: root.cellUnhovered(cellWrap.cellObj.key)
                                            onClicked: root.cellClicked(cellWrap.cellObj.key, root._rectInHost(cellWrap))
                                        }
                                    }

                                    // Inline SkillSelect control cell (only in section 1 "View Skill Details")
                                    Loader {
                                        objectName: "pob.calcsCard.skillLoader"
                                        visible: cellWrap.ctrlName.length > 0
                                        active: cellWrap.ctrlName.length > 0
                                        x: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        sourceComponent: {
                                            var n = cellWrap.ctrlName
                                            if (n === "mainSocketGroup") return ctrlGroupComp
                                            if (n === "mainSkill") return ctrlSkillComp
                                            if (n === "mainSkillPart") return ctrlPartComp
                                            if (n === "mainSkillStageCount") return ctrlStageComp
                                            if (n === "mainSkillMineCount") return ctrlMineComp
                                            if (n === "showMinion") return ctrlShowMinionComp
                                            if (n === "mainSkillMinion") return ctrlMinionComp
                                            if (n === "mainSkillMinionLibrary") return ctrlSpectreComp
                                            if (n === "mainSkillMinionSkill") return ctrlMinionSkillComp
                                            if (n === "mode") return ctrlModeComp
                                            return null
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- SkillSelect control delegates (CalcsTab.lua:45-148) ---
    // Each control pushes engine state imperatively on skillSelect change with
    // a _syncing guard so refreshes never echo back as user mutations.

    Component {
        id: ctrlGroupComp
        DropDownControl {
            id: dd
            objectName: "pob.calcsCard.activeSkillDrop"
            width: 300; height: 18; size: theme.fontSize - 1
            placeholder: "<None>"
            property bool _syncing: false
            labelFor: (g) => g ? (g.label || "") : ""
            tooltipForItem: (g, tip) => {
                if (!g || g.index === undefined) return
                var lines = luaEngine.getSocketGroupTooltip(g.index)
                if (lines && lines.length !== undefined) {
                    for (var i = 0; i < lines.length; i++) tip.addLine(14, lines[i])
                }
            }
            function sync() {
                var s = root.skillSelect
                if (!s) return
                _syncing = true
                var list = (s.socketGroups && s.socketGroups.length !== undefined) ? s.socketGroups : []
                dd.model = list
                dd.currentIndex = root._indexOf(list, "index", s.mainSocketGroup)
                _syncing = false
            }
            Component.onCompleted: sync()
            Connections { target: root; function onSkillSelectChanged() { dd.sync() } }
            onSelected: (i) => {
                if (dd._syncing || !dd.model || !dd.model[i]) return
                root.skillFieldChanged("group", dd.model[i].index)
            }
        }
    }

    Component {
        id: ctrlSkillComp
        DropDownControl {
            id: dd
            objectName: "pob.calcsCard.activeSkillDrop"
            width: 300; height: 18; size: theme.fontSize - 1
            placeholder: "<None>"
            property bool _syncing: false
            labelFor: (s) => s ? (s.label || "") : ""
            function sync() {
                var s = root.skillSelect
                if (!s) return
                _syncing = true
                var list = (s.skills && s.skills.length !== undefined) ? s.skills : []
                dd.model = list
                dd.controlEnabled = s.skillsEnabled === true
                dd.currentIndex = root._indexOf(list, "index", s.mainActiveSkill)
                _syncing = false
            }
            Component.onCompleted: sync()
            Connections { target: root; function onSkillSelectChanged() { dd.sync() } }
            onSelected: (i) => {
                if (dd._syncing || !dd.model || !dd.model[i]) return
                root.skillFieldChanged("skill", dd.model[i].index)
            }
        }
    }

    Component {
        id: ctrlPartComp
        DropDownControl {
            id: dd
            objectName: "pob.calcs.drop_skill_part"
            width: 250; height: 18; size: theme.fontSize - 1
            property bool _syncing: false
            labelFor: (p) => p ? (p.label || "") : ""
            function sync() {
                var s = root.skillSelect
                if (!s) return
                _syncing = true
                var list = (s.parts && s.parts.length !== undefined) ? s.parts : []
                dd.model = list
                dd.currentIndex = root._indexOf(list, "index", s.partIndex)
                _syncing = false
            }
            Component.onCompleted: sync()
            Connections { target: root; function onSkillSelectChanged() { dd.sync() } }
            onSelected: (i) => {
                if (dd._syncing || !dd.model || !dd.model[i]) return
                root.skillFieldChanged("part", dd.model[i].index)
            }
        }
    }

    Component {
        id: ctrlStageComp
        EditControl {
            id: ed
            width: 56; height: 18; size: theme.fontSize - 1
            isNumeric: true; numericMin: 0
            property bool _syncing: false
            function sync() {
                var s = root.skillSelect
                if (!s || !s.stages) return
                _syncing = true
                ed.text = String(s.stages.value || "")
                _syncing = false
            }
            Component.onCompleted: sync()
            Connections { target: root; function onSkillSelectChanged() { ed.sync() } }
            onCommitted: (t) => {
                if (ed._syncing) return
                root.skillFieldChanged("stages", parseInt(t) || 0)
            }
        }
    }

    Component {
        id: ctrlMineComp
        EditControl {
            id: ed
            width: 56; height: 18; size: theme.fontSize - 1
            isNumeric: true; numericMin: 0
            property bool _syncing: false
            function sync() {
                var s = root.skillSelect
                if (!s || !s.mines) return
                _syncing = true
                ed.text = String(s.mines.value || "")
                _syncing = false
            }
            Component.onCompleted: sync()
            Connections { target: root; function onSkillSelectChanged() { ed.sync() } }
            onCommitted: (t) => {
                if (ed._syncing) return
                root.skillFieldChanged("mines", parseInt(t) || 0)
            }
        }
    }

    Component {
        id: ctrlShowMinionComp
        CheckBox {
            id: cb
            width: 18; height: 18
            tooltipText: "Show stats for the minion instead of the player."
            property bool _syncing: false
            function sync() {
                var s = root.skillSelect
                if (!s) return
                _syncing = true
                cb.state = s.showMinion === true
                _syncing = false
            }
            Component.onCompleted: sync()
            Connections { target: root; function onSkillSelectChanged() { cb.sync() } }
            onToggled: (newState) => {
                if (cb._syncing) return
                root.inputChanged("showMinion", newState)
            }
        }
    }

    Component {
        id: ctrlMinionComp
        DropDownControl {
            id: dd
            width: 180; height: 18; size: theme.fontSize - 1
            property bool _syncing: false
            labelFor: (m) => m ? (m.label || "") : ""
            function sync() {
                var s = root.skillSelect
                if (!s || !s.minion) return
                _syncing = true
                var list = (s.minion.list && s.minion.list.length !== undefined) ? s.minion.list : []
                dd.model = list
                dd.controlEnabled = s.minion.enabled === true
                dd.currentIndex = s.minion.isItemSet
                    ? root._indexOf(list, "itemSetId", s.minion.selected)
                    : root._indexOf(list, "minionId", s.minion.selected)
                _syncing = false
            }
            Component.onCompleted: sync()
            Connections { target: root; function onSkillSelectChanged() { dd.sync() } }
            onSelected: (i) => {
                if (dd._syncing || !dd.model || !dd.model[i]) return
                var v = dd.model[i]
                if (v.itemSetId !== undefined) root.skillFieldChanged("minion", { itemSetId: v.itemSetId })
                else if (v.minionId !== undefined) root.skillFieldChanged("minion", { minionId: v.minionId })
            }
        }
    }

    Component {
        id: ctrlSpectreComp
        Button {
            label: "Manage Spectres..."
            width: 120; height: 18
            onClicked: root.manageSpectresRequested()
        }
    }

    Component {
        id: ctrlMinionSkillComp
        DropDownControl {
            id: dd
            width: 200; height: 18; size: theme.fontSize - 1
            property bool _syncing: false
            function sync() {
                var s = root.skillSelect
                if (!s || !s.minionSkill) return
                _syncing = true
                var list = (s.minionSkill.list && s.minionSkill.list.length !== undefined) ? s.minionSkill.list : []
                dd.model = list
                dd.controlEnabled = s.minionSkill.enabled === true
                dd.currentIndex = (s.minionSkill.index || 1) - 1
                _syncing = false
            }
            Component.onCompleted: sync()
            Connections { target: root; function onSkillSelectChanged() { dd.sync() } }
            onSelected: (i) => {
                if (dd._syncing) return
                root.skillFieldChanged("minionSkill", i + 1)
            }
        }
    }

    Component {
        id: ctrlModeComp
        DropDownControl {
            id: dd
            width: 120; height: 18; size: theme.fontSize - 1
            property bool _syncing: false
            labelFor: (m) => m ? (m.label || "") : ""
            tooltipText: "This controls the calculation of the stats shown in this tab.\nThe stats in the sidebar are always shown in Effective DPS mode, regardless of this setting.\n\nUnbuffed: No auras, buffs, or other support skills or effects will apply.\nBuffed: Aura and buff skills apply.\nIn Combat: Charges and combat buffs such as Onslaught will also apply.\nEffective DPS: Curses and enemy properties will also apply."
            function sync() {
                var s = root.skillSelect
                if (!s) return
                _syncing = true
                var list = (s.buffModes && s.buffModes.length !== undefined) ? s.buffModes : []
                dd.model = list
                dd.currentIndex = root._indexOf(list, "buffMode", s.buffMode)
                _syncing = false
            }
            Component.onCompleted: sync()
            Connections { target: root; function onSkillSelectChanged() { dd.sync() } }
            onSelected: (i) => {
                if (dd._syncing || !dd.model || !dd.model[i]) return
                root.inputChanged("misc_buffMode", dd.model[i].buffMode)
            }
        }
    }
}
