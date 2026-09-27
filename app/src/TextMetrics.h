#pragma once

#include <QObject>
#include <QString>
#include <QHash>
#include <QVector>
#include <array>

// TextMetrics — a .tgf-backed reimplementation of the legacy SimpleGraphic
// `r_font_c` string-measurement, exposed to both Lua (real DrawStringWidth /
// DrawStringCursorIndex, replacing the pob_host.lua stubs that returned 1/0)
// and QML (Q_INVOKABLE width / cursorIndex).
//
// WHY NOT QFontMetrics: legacy PoB measures against pre-baked bitmap-font atlases
// with per-glyph integer spacing and a `ceil()` applied after EVERY character
// (cumulative per-glyph rounding). QFontMetrics reproduces neither, so it drifts
// 1..several px per string — which silently breaks caret hit-testing, ellipsis
// clip points, and dropdown/tooltip auto-width. Every ported control's layout math
// (EditControl, DropDown, ListControl, Tooltip, GemSelect) calls these, so the
// numbers must match legacy exactly. QFont is used only for *rendering* elsewhere,
// never for measurement.
//
// Algorithm mirrors r_font.cpp (upstream PathOfBuilding-SimpleGraphic):
//   * font name → .tgf file via a fixed map (see fileForFont); nil/empty → FIXED.
//   * pick the baked height nearest the requested height; scale = height/baked.
//   * per char: `^` color escapes advance 2 (^d) or 8 (^xRRGGBB) chars, zero width;
//     tab = space-glyph advance * 4; codepoint >= 128 renders as a "[U+XXXX]" tofu
//     string measured at a >=3px-smaller baked height; else advance =
//     (glyph.width + glyph.spLeft + glyph.spRight) * scale.
//   * width = ceil(width) after every character.
//   * multi-line (\n): width = max over lines.
class TextMetrics : public QObject {
    Q_OBJECT
public:
    explicit TextMetrics(QObject* parent = nullptr);

    // Directory holding the .tgf metrics files (…/SimpleGraphic/Fonts). Fonts load
    // lazily on first use, so this is cheap to call at startup.
    void setFontDir(const QString& dir) { m_fontDir = dir; }
    QString fontDir() const { return m_fontDir; }

    // Core measure API (used by the Lua bridge). `font` may be empty → FIXED.
    int stringWidth(int height, const QString& font, const QString& text);
    int stringCursorIndex(int height, const QString& font, const QString& text,
                          int curX, int curY);

    // QML-facing wrappers (same semantics).
    Q_INVOKABLE int width(int height, const QString& font, const QString& text) {
        return stringWidth(height, font, text);
    }
    Q_INVOKABLE int cursorIndex(int height, const QString& font, const QString& text,
                                int curX, int curY) {
        return stringCursorIndex(height, font, text, curX, curY);
    }

    // True once at least one .tgf loaded successfully (diagnostics/selftest).
    bool anyFontLoaded() const { return m_anyLoaded; }

private:
    struct Glyph { int width = 0; int spLeft = 0; int spRight = 0; };
    struct FontHeight {
        int height = 0;
        int numGlyph = 0;                 // count of ASCII glyphs stored (usually 128)
        std::array<Glyph, 128> glyphs {}; // indexed by codepoint 0..127
    };
    struct Font {
        bool attempted = false;           // load tried (avoid re-reading a missing file)
        bool ok = false;
        QVector<FontHeight> heights;      // ascending by height
    };

    // Resolve a legacy font name ("VAR", "FIXED", "FONTIN SC", …) to its .tgf base
    // filename. Returns FIXED's file for empty/unknown names (legacy default).
    static QString fileForFont(const QString& font);

    Font* loadFont(const QString& font);  // lazy; nullptr if no baked heights
    const FontHeight* findHeight(const Font* f, int height) const;
    const FontHeight* findSmaller(const Font* f, int height, int reduction) const;

    // Advance (unscaled) of a single codepoint in a baked height, or 0 if absent.
    static int glyphAdvance(const FontHeight* fh, uint cp);

    // Length in chars of a color escape starting at text[i], else 0 (literal ^).
    static int colorEscapeLen(const QString& text, int i);

    // Width of one line (no embedded \n) at a resolved (fh, scale).
    double lineWidth(const Font* f, const FontHeight* fh, double scale,
                     int height, const QString& line) const;

    QString m_fontDir;
    QHash<QString, Font> m_fonts;         // keyed by resolved .tgf base filename
    bool m_anyLoaded = false;
};
