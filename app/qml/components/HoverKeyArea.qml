import QtQuick

// HoverKeyArea — Tier 0 primitive for the legacy OnHoverKeyUp pattern: a key
// event acting on whichever control is merely HOVERED, independent of
// keyboard focus (the wiki hotkey on a hovered item/gem row —
// ItemSlotControl.lua/SkillListControl.lua/ItemListControl.lua/
// ItemDBControl.lua all use it this way). Wraps a HoverHandler, Qt's native
// hover-without-focus input handler.
//
// `onHoverKeyUp` is a JS function property (not a signal) so callers wire it
// inline like the other Tier 0 primitives (DropTarget's canReceiveDrag,
// UndoHandler's createState, ...).
//
// Routing an actual key press to "whatever's hovered, focus be damned"
// needs one window-level key handler that checks `hovered` across the live
// set of HoverKeyAreas — deferred to the first real consumer (Phase 5/6:
// SkillListControl/ItemSlotControl) rather than guessing a registry shape
// with nothing to integrate against yet.
Item {
    id: root

    readonly property bool hovered: hh.hovered
    property var onHoverKeyUp: function (key) {};

    HoverHandler {
        id: hh
    }
}
