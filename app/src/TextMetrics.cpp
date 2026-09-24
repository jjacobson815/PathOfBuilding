#include "TextMetrics.h"

#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QRegularExpression>
#include <algorithm>
#include <cmath>

TextMetrics::TextMetrics(QObject* parent) : QObject(parent) {}

// Legacy font-name → .tgf base filename. The engine passes logical names
// ("VAR", "FIXED", "FONTIN SC", …); SimpleGraphic resolves them to the real
// bundled font files. Empty/nil/unknown → FIXED (the legacy default font).
QString TextMetrics::fileForFont(const QString& font) {
    const QString f = font.trimmed().toUpper();
    if (f == "VAR")               return QStringLiteral("Liberation Sans");
    if (f == "VAR BOLD")          return QStringLiteral("Liberation Sans Bold");
    if (f == "FONTIN")            return QStringLiteral("Fontin");
    if (f == "FONTIN ITALIC")     return QStringLiteral("Fontin Italic");
    if (f == "FONTIN SC")         return QStringLiteral("Fontin SmallCaps");
    if (f == "FONTIN SC ITALIC")  return QStringLiteral("Fontin SmallCaps Italic");
    // "FIXED" and anything unrecognised (including empty) → the monospace default.
    return QStringLiteral("Bitstream Vera Sans Mono");
}

// Read a leading (optionally negative) integer from `tok`, ignoring any trailing
// non-digits (e.g. the ';' that terminates the last GLYPH field).
static int leadingInt(const QString& tok) {
    int i = 0, n = tok.size();
    bool neg = false;
    if (i < n && (tok[i] == '-' || tok[i] == '+')) { neg = tok[i] == '-'; ++i; }
    int v = 0; bool any = false;
    while (i < n && tok[i].isDigit()) { v = v * 10 + (tok[i].unicode() - '0'); ++i; any = true; }
    if (!any) return 0;
    return neg ? -v : v;
}

TextMetrics::Font* TextMetrics::loadFont(const QString& font) {
    const QString base = fileForFont(font);
    auto it = m_fonts.find(base);
    if (it != m_fonts.end()) return it->ok ? &it.value() : nullptr;

    Font fnt;
    fnt.attempted = true;
    const QString path = QDir(m_fontDir).filePath(base + ".tgf");
    QFile file(path);
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream ts(&file);
        static const QRegularExpression ws("\\s+");
        FontHeight cur;
        bool inBlock = false;
        int glyphIdx = 0;
        auto flush = [&]() {
            if (inBlock) { cur.numGlyph = glyphIdx; fnt.heights.push_back(cur); }
        };
        while (!ts.atEnd()) {
            const QString line = ts.readLine().trimmed();
            if (line.startsWith("HEIGHT")) {
                flush();
                cur = FontHeight();
                cur.height = leadingInt(line.mid(6).trimmed());
                inBlock = true;
                glyphIdx = 0;
            } else if (line.startsWith("GLYPH")) {
                if (!inBlock) continue;
                const QStringList t = line.mid(5).split(ws, Qt::SkipEmptyParts);
                // fields: x y width spLeft spRight  (x,y are atlas coords, unused here)
                if (t.size() >= 5 && glyphIdx < 128) {
                    Glyph g;
                    g.width   = leadingInt(t[2]);
                    g.spLeft  = leadingInt(t[3]);
                    g.spRight = leadingInt(t[4]);
                    cur.glyphs[glyphIdx] = g;
                }
                if (glyphIdx < 128) ++glyphIdx;
            }
        }
        flush();
        std::sort(fnt.heights.begin(), fnt.heights.end(),
                  [](const FontHeight& a, const FontHeight& b) { return a.height < b.height; });
        fnt.ok = !fnt.heights.isEmpty();
    }
    if (fnt.ok) m_anyLoaded = true;
    Font& stored = m_fonts.insert(base, fnt).value();
    return stored.ok ? &stored : nullptr;
}

const TextMetrics::FontHeight* TextMetrics::findHeight(const Font* f, int height) const {
    if (!f || f->heights.isEmpty()) return nullptr;
    if (height < 0) return &f->heights.first();
    if (height > f->heights.last().height) return &f->heights.last();
    const FontHeight* best = &f->heights.first();
    int bestD = std::abs(height - best->height);
    for (const FontHeight& h : f->heights) {
        int d = std::abs(height - h.height);
        if (d < bestD) { bestD = d; best = &h; }  // ascending order → ties keep lower height
    }
    return best;
}

const TextMetrics::FontHeight* TextMetrics::findSmaller(const Font* f, int height,
                                                       int reduction) const {
    if (!f || f->heights.isEmpty()) return nullptr;
    const int target = height - reduction;
    const FontHeight* best = nullptr;
    for (const FontHeight& h : f->heights) {            // ascending
        if (h.height <= target) best = &h;              // largest baked <= target
    }
    return best ? best : &f->heights.first();
}

int TextMetrics::glyphAdvance(const FontHeight* fh, uint cp) {
    if (!fh || cp >= 128u || (int)cp >= fh->numGlyph) return 0;
    const Glyph& g = fh->glyphs[cp];
    return g.width + g.spLeft + g.spRight;
}

int TextMetrics::colorEscapeLen(const QString& text, int i) {
    const int n = text.size();
    if (i >= n || text[i] != '^') return 0;
    if (i + 1 >= n) return 0;
    const QChar c1 = text[i + 1];
    if (c1.isDigit()) return 2;                         // ^0..^9
    if (c1 == 'x' || c1 == 'X') {                       // ^xRRGGBB / ^XRRGGBB
        if (i + 8 > n) return 0;
        for (int k = i + 2; k < i + 8; ++k) {
            const QChar h = text[k];
            const bool hex = (h >= '0' && h <= '9') || (h >= 'a' && h <= 'f') || (h >= 'A' && h <= 'F');
            if (!hex) return 0;
        }
        return 8;
    }
    return 0;                                           // literal '^' (no ^^ escape)
}

double TextMetrics::lineWidth(const Font* f, const FontHeight* fh, double scale,
                              int height, const QString& line) const {
    double width = 0.0;
    const int n = line.size();
    int i = 0;
    const FontHeight* tofuFh = nullptr;   // resolved lazily on first non-ASCII char
    while (i < n) {
        const int esc = colorEscapeLen(line, i);
        if (esc > 0) { i += esc; continue; }            // color escape: zero width
        const uint cp = line[i].unicode();
        if (cp == uint('\t')) {
            width += glyphAdvance(fh, 32) * 4.0 * scale;
            width = std::ceil(width);
        } else if (cp >= 128u) {
            if (!tofuFh) tofuFh = findSmaller(f, height, 3);
            if (tofuFh) {
                // Render as "[U+XXXX]" (uppercase hex) measured at scale 1.0,
                // ceil()'d per replacement char (recursive measure in legacy).
                const QString tofu = QStringLiteral("[U+%1]")
                                         .arg(cp, 4, 16, QChar('0')).toUpper();
                for (const QChar tc : tofu) {
                    width += glyphAdvance(tofuFh, tc.unicode());
                    width = std::ceil(width);
                }
            }
            width = std::ceil(width);
        } else {
            width += glyphAdvance(fh, cp) * scale;
            width = std::ceil(width);
        }
        ++i;
    }
    return width;
}

int TextMetrics::stringWidth(int height, const QString& font, const QString& text) {
    Font* f = loadFont(font);
    const FontHeight* fh = f ? findHeight(f, height) : nullptr;
    if (!fh) {
        // Fonts unavailable (should not happen — the .tgf assets ship). Fall back to
        // a rough estimate so layout math stays finite rather than collapsing to 0.
        int visible = 0;
        for (int i = 0; i < text.size(); ) {
            const int esc = colorEscapeLen(text, i);
            if (esc > 0) { i += esc; continue; }
            if (text[i] != '\n') ++visible;
            ++i;
        }
        return (int)std::ceil(visible * height * 0.5);
    }
    const double scale = (double)height / fh->height;
    double maxw = 0.0;
    const QVector<QStringView> lines = QStringView(text).split(u'\n');
    for (const QStringView lv : lines)
        maxw = std::max(maxw, lineWidth(f, fh, scale, height, lv.toString()));
    return (int)std::ceil(maxw);
}

int TextMetrics::stringCursorIndex(int height, const QString& font, const QString& text,
                                   int curX, int curY) {
    Font* f = loadFont(font);
    const FontHeight* fh = f ? findHeight(f, height) : nullptr;
    if (!fh) return 0;
    const double scale = (double)height / fh->height;
    const FontHeight* tofuFh = nullptr;
    const int n = text.size();
    int pos = 0;
    int lineY = 0;
    while (pos <= n) {
        const int nl = text.indexOf(u'\n', pos);
        const int lineEnd = (nl < 0) ? n : nl;
        const bool lastLine = (nl < 0);
        lineY += height;
        if (curY <= lineY || lastLine) {
            double x = 0.0;
            int i = pos;
            while (i < lineEnd) {
                const int esc = colorEscapeLen(text, i);
                if (esc > 0) { i += esc; continue; }
                const uint cp = text[i].unicode();
                double before = x;
                if (cp == uint('\t')) {
                    const double fullW = glyphAdvance(fh, 32) * 4.0 * scale;
                    // Legacy tab split: first half, test, second half.
                    x += std::ceil(fullW / 2.0);
                    if (curX <= x) return i;
                    x += fullW - std::ceil(fullW / 2.0);
                    x = std::ceil(x);
                } else if (cp >= 128u) {
                    if (!tofuFh) tofuFh = findSmaller(f, height, 3);
                    if (tofuFh) {
                        const QString tofu = QStringLiteral("[U+%1]")
                                                 .arg(cp, 4, 16, QChar('0')).toUpper();
                        for (const QChar tc : tofu) {
                            x += glyphAdvance(tofuFh, tc.unicode());
                            x = std::ceil(x);
                        }
                    }
                    if (curX <= (before + x) / 2.0) return i;   // midpoint hit-test
                } else {
                    x += glyphAdvance(fh, cp) * scale;
                    x = std::ceil(x);
                    if (curX <= (before + x) / 2.0) return i;   // midpoint hit-test
                }
                ++i;
            }
            return lineEnd;   // past the last glyph → caret at line end
        }
        pos = lineEnd + 1;
    }
    return n;
}
