import QtQuick

// Chrome — Tier 0 shared border+fill "chrome" for interactive controls
// (buttons, checkboxes, sliders, dropdowns, ...). Formalizes the
// border+background+hover/pressed/disabled pattern already used ad hoc for
// the sidebar nav buttons (main.qml), over the existing Theme design tokens
// (border/borderStrong/hover/active/disabled/radiusControl).
//
// NOT literal legacy SimpleGraphic greyscale bevels — this app's shell
// already committed to the flat "Cyber Citrus" design system (navy/lime/
// cyan, rounded corners, tinted hover fills), so widget chrome stays
// consistent with that rather than reintroducing 5-step grey bevels.
//
// `controlEnabled` is used instead of Item's built-in `enabled` (which
// disables input handling entirely) so a disabled-looking-but-still-hit-
// testable state stays possible if a future widget needs one.
Rectangle {
    id: root

    property bool pressed: false
    property bool hovered: false
    property bool locked: false        // forces the hovered/active look (e.g. a toggled-on state)
    property bool controlEnabled: true

    radius: theme.radiusControl
    border.width: 1
    border.color: !controlEnabled ? theme.border
                : (hovered || locked || pressed) ? theme.borderStrong
                : theme.border
    color: !controlEnabled ? theme.disabled
         : pressed ? theme.active
         : (hovered || locked) ? theme.hover
         : "transparent"
}
