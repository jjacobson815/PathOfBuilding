import QtQuick

// ColorText — Tier 0 shared widget for rendering PoB colour-coded strings
// (^0-^9 / ^xRRGGBB, see ColorText.h). Every colour-coded string (item
// names, gem tooltips, stat lines, ...) should use this rather than binding
// `text` directly, so markup renders instead of showing literal "^7" etc.
//
// `defaultColor` is the colour runs start in before any inline escape (the
// legacy DrawString pen colour) — pass theme.text unless the call site had
// its own starting colour (e.g. a rarity colour for an item name).
Text {
    id: root

    property string sourceText: ""
    property color defaultColor: theme.text

    text: colorText.toStyledText(sourceText, defaultColor)
    textFormat: Text.StyledText
    color: defaultColor
    font.family: theme.fontVar
    font.pixelSize: theme.fontSize
}
