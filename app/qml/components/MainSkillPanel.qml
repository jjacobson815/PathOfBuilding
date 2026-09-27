import QtQuick
import QtQuick.Layouts

// MainSkillPanel — Phase 3 Part 3.2, the side bar's main-skill selector stack.
// Ports the eight controls buildMode:Init builds at Build.lua:487-575, driven by
// the data payload from pob_getMainSkillControls (a port of
// buildMode:RefreshSkillSelectControls, Build.lua:1511).
//
// Legacy re-ran RefreshSkillSelectControls EVERY FRAME to decide which of these
// controls are shown; with no frame loop we re-read the payload on
// skillsChanged/calcsChanged instead and bind `visible` to the payload's own
// shown flags. The conditional set is not cosmetic — which controls appear tells
// you what kind of skill is selected (parts, stages, mines, minion, minion skill).
//
// `suffix` selects WHICH main-skill selection this instance edits: "" is the
// side bar's, "Calcs" is the Calcs tab's. They are deliberately independent in
// legacy, so Phase 8 can instantiate this same component with suffix "Calcs"
// and get a correctly-separate selector.
//
// getMainSkillControls() forces a recalc, so it is called from refresh(), never
// from a binding. It deliberately does not touch getActiveSkills(), which runs
// one full BuildOutput per displayed skill (61-470ms).
ColumnLayout {
    id: root

    // The root IS the layout. An earlier revision wrapped a ColumnLayout inside
    // a plain Item and drove it with `col.width: root.width`; as a fillWidth
    // child of the sidebar's own ColumnLayout that width never resolved, so the
    // panel reserved its full height and rendered nothing at all. Being the
    // layout removes the plumbing entirely.
    spacing: 2

    property string suffix: ""
    // NAMED payload, NOT `data`. `data` is QtObject's DEFAULT property -- the
    // list every declared child is appended to. Shadowing it with a `var`
    // silently swallows every child of this component: the layout still
    // reserved space but drew nothing, with ZERO QML warnings to say why. This
    // only surfaced when the root became the layout itself; while the children
    // belonged to an inner ColumnLayout the shadowed name was harmless.
    property var payload: ({ socketGroups: [], skills: [], parts: [],
                          stages: { shown: false, value: "" },
                          mines: { shown: false, value: "" },
                          minion: { shown: false, list: [] },
                          minionSkill: { shown: false, list: [] } })

    signal manageSpectresRequested()

    // True while refresh() is pushing engine state into the controls, so the
    // controls' own `selected` handlers don't treat that as a user edit and
    // write it straight back.
    property bool _syncing: false

    function refresh() {
        var d = luaEngine.getMainSkillControls(root.suffix)
        if (!d) return
        _syncing = true
        root.payload = d
        groupDrop.model = d.socketGroups
        groupDrop.currentIndex = _indexOf(d.socketGroups, "index", d.mainSocketGroup)
        skillDrop.model = d.skills
        skillDrop.currentIndex = _indexOf(d.skills, "index", d.mainActiveSkill)
        partDrop.model = d.parts
        partDrop.currentIndex = _indexOf(d.parts, "index", d.partIndex)
        stageEdit.text = d.stages.value
        mineEdit.text = d.mines.value
        minionDrop.model = d.minion.list
        minionDrop.currentIndex = d.minion.isItemSet
            ? _indexOf(d.minion.list, "itemSetId", d.minion.selected)
            : _indexOf(d.minion.list, "minionId", d.minion.selected)
        minionSkillDrop.model = d.minionSkill.list
        minionSkillDrop.currentIndex = d.minionSkill.index - 1
        _syncing = false
    }

    function _indexOf(list, key, value) {
        if (!list) return -1
        for (var i = 0; i < list.length; i++)
            if (list[i] && list[i][key] === value) return i
        return list.length > 0 ? 0 : -1
    }

    Component.onCompleted: refresh()
    Connections {
        target: luaEngine
        function onSkillsChanged() { root.refresh() }
        function onCalcsChanged() { root.refresh() }
        function onModeChanged() { root.refresh() }
    }

        Label {
            label: "^7Main Skill:"
            size: theme.fontSize
        }

        DropDownControl {
            id: groupDrop
            Layout.fillWidth: true
            Layout.preferredHeight: 18
            size: theme.fontSize
            labelFor: (g) => g.label
            // The socket-group tooltip is the real legacy one, rebuilt by the
            // engine via skillsTab:AddSocketGroupTooltip.
            tooltipForItem: (g, tip) => {
                var lines = luaEngine.getSocketGroupTooltip(g.index)
                for (var i = 0; i < lines.length; i++) tip.addLine(14, lines[i])
            }
            onSelected: (i) => {
                if (root._syncing) return
                luaEngine.setMainSocketGroup(model[i].index)
            }
        }

        DropDownControl {
            id: skillDrop
            Layout.fillWidth: true
            Layout.preferredHeight: 18
            size: theme.fontSize
            visible: !root.payload.noSkills
            controlEnabled: root.payload.skillsEnabled === true
            labelFor: (s) => s.label
            onSelected: (i) => {
                if (root._syncing) return
                luaEngine.setMainActiveSkill(model[i].index, root.suffix)
            }
        }

        DropDownControl {
            id: partDrop
            Layout.fillWidth: true
            Layout.preferredHeight: 18
            size: theme.fontSize
            visible: root.payload.partsShown === true
            labelFor: (p) => p.label
            onSelected: (i) => {
                if (root._syncing) return
                luaEngine.setMainSkillPart(model[i].index, root.suffix)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: root.payload.stages.shown === true
            Label { label: "^7Stages:"; size: theme.fontSize }
            EditControl {
                id: stageEdit
                Layout.preferredWidth: 60
                Layout.preferredHeight: 18
                isNumeric: true
                numericMin: 0
                size: theme.fontSize
                onCommitted: (t) => {
                    if (root._syncing) return
                    luaEngine.setSkillStageCount(parseInt(t) || 0, root.suffix)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: root.payload.mines.shown === true
            Label { label: "^7Active Mines:"; size: theme.fontSize }
            EditControl {
                id: mineEdit
                Layout.preferredWidth: 60
                Layout.preferredHeight: 18
                isNumeric: true
                numericMin: 0
                size: theme.fontSize
                onCommitted: (t) => {
                    if (root._syncing) return
                    luaEngine.setSkillMineCount(parseInt(t) || 0, root.suffix)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 2
            visible: root.payload.minion.shown === true
            DropDownControl {
                id: minionDrop
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                size: theme.fontSize
                controlEnabled: root.payload.minion.enabled === true
                labelFor: (m) => m.label
                onSelected: (i) => {
                    if (root._syncing) return
                    var v = model[i]
                    // Animate Guardian's dropdown carries item sets, everything
                    // else carries minion ids — the bridge dispatches on which
                    // key is present.
                    if (v.itemSetId !== undefined)
                        luaEngine.setSkillMinion({ itemSetId: v.itemSetId }, root.suffix)
                    else if (v.minionId !== undefined)
                        luaEngine.setSkillMinion({ minionId: v.minionId }, root.suffix)
                }
            }
            Button {
                label: "Manage Spectres..."
                visible: root.payload.minion.libraryShown === true
                Layout.preferredWidth: 120
                Layout.preferredHeight: 18
                onClicked: root.manageSpectresRequested()
            }
        }

        DropDownControl {
            id: minionSkillDrop
            Layout.fillWidth: true
            Layout.preferredHeight: 16
            size: theme.fontSize
            visible: root.payload.minionSkill.shown === true
            controlEnabled: root.payload.minionSkill.enabled === true
            onSelected: (i) => {
                if (root._syncing) return
                luaEngine.setSkillMinionSkill(i + 1, root.suffix)
            }
        }
}
