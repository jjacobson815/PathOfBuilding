import QtQuick

// UndoHandler — Tier 0 generic undo/redo ring, ported from
// src/Classes/UndoHandler.lua (the mixin CalcsTab/ConfigTab/EditControl/
// ItemsTab/PassiveSpec/PathControl/SkillsTab all use). Consumers supply two
// JS function properties mirroring the legacy class contract (the two
// methods a class using the UndoHandler mixin must define):
//   createState: () -> var             snapshot the current state
//   restoreState: (state: var) -> void  revert to a given snapshot
// `modFlag` mirrors legacy's dirty-flag (set true by addUndoState).
QtObject {
    id: root

    property var createState: function () { return null; }
    property var restoreState: function (state) {};
    property bool modFlag: false

    property var _undo: []   // [0] is the current state, ring-capped at 101 (legacy undo[102]=nil)
    property var _redo: []

    readonly property bool canUndo: _undo.length > 1
    readonly property bool canRedo: _redo.length > 0

    // Call once after the current state is first loaded/initialised.
    function resetUndo() {
        _undo = [createState()];
        _redo = [];
    }

    // Call after the user makes a change to the current state.
    function addUndoState(noClearRedo) {
        const next = _undo.slice();
        next.unshift(createState());
        if (next.length > 101) next.length = 101;
        _undo = next;
        modFlag = true;
        if (!noClearRedo) _redo = [];
    }

    // Reverts the current state to the previous undo state.
    function undo() {
        if (_undo.length < 2) return;
        const nextRedo = _redo.slice();
        const nextUndo = _undo.slice();
        nextRedo.unshift(nextUndo.shift()); // move current state onto redo
        const target = nextUndo.shift();    // the previous state becomes current
        _redo = nextRedo;
        _undo = nextUndo;
        restoreState(target);
        addUndoState(true); // re-snapshot post-restore state; redo is NOT cleared
    }

    // Reverts the most recent undo operation.
    function redo() {
        if (_redo.length === 0) return;
        const nextRedo = _redo.slice();
        const target = nextRedo.shift();
        _redo = nextRedo;
        restoreState(target);
        addUndoState(true);
    }
}
