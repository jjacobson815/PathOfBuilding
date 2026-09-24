#pragma once

#include <QObject>
#include <QColor>
#include <QString>
#include <QVariantList>

// ColorText — the single shared parser for PoB's inline colour-code markup
// (legacy `IsColorEscape`, common.cpp:201-218), exposed to QML as the
// "colorText" context property. Every text-bearing component (Label,
// Tooltip, ListControl rows, item names, ...) routes through this rather
// than each re-implementing the escape grammar or reusing Theme::parseColor
// (which only handles a single leading token and would misparse "^7" as one
// hex digit).
//
// Grammar (no `^^` escape — anything after `^` that isn't a recognised form
// is a LITERAL `^`):
//   ^0..^9         -> palette index (2 chars)
//   ^xRRGGBB/^X..  -> explicit colour (8 chars, case-insensitive hex)
//   ^<anything else> or trailing `^` -> literal '^', 1 char consumed
// An inline escape changes the "current" colour for the remainder of the
// string (carry-forward); by convention ^7 (white) means "reset to default".
class ColorText : public QObject {
    Q_OBJECT
public:
    explicit ColorText(QObject* parent = nullptr);

    // The exact ^0..^9 palette (common.cpp:188-199).
    static QColor paletteColor(int digit);

    // Parse `text` into ordered (colour, text) runs, starting in `defaultColor`
    // (the pen colour a DrawString call would have started with). Each run is
    // a QVariantMap{ "color": QColor, "text": QString }; runs never contain
    // embedded escapes and are never empty except for a wholly-empty input.
    Q_INVOKABLE QVariantList parse(const QString& text, const QColor& defaultColor) const;

    // Convenience for QML: render `text` as a Text.StyledText-ready markup
    // string (<font color="#rrggbb">escaped run</font> spans concatenated),
    // so a single Text{textFormat: Text.StyledText} element can display it.
    Q_INVOKABLE QString toStyledText(const QString& text, const QColor& defaultColor) const;

    // Strip all colour escapes, returning the plain visible text (e.g. for
    // width estimation fallbacks or plain-text contexts). Note: TextMetrics
    // already skips escapes when MEASURING — this is for display contexts
    // that want plain text instead of colour runs.
    Q_INVOKABLE QString stripColorCodes(const QString& text) const;

private:
    // Length in chars of a colour escape starting at text[i] (2 or 8), or 0
    // if `text[i]` is a literal '^' (not the start of a recognised escape).
    // Mirrors TextMetrics::colorEscapeLen (kept independent — this parser
    // must not depend on font/atlas state).
    static int escapeLen(const QString& text, int i);

    // Resolve a recognised escape (length already known to be 2 or 8) to a
    // colour: ^0..^9 -> paletteColor, ^xRRGGBB -> that hex colour.
    static QColor resolveEscape(const QString& text, int i, int len);
};
