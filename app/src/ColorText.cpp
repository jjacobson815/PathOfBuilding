#include "ColorText.h"

ColorText::ColorText(QObject* parent) : QObject(parent) {}

QColor ColorText::paletteColor(int digit) {
    switch (digit) {
        case 0: return QColor(0x00, 0x00, 0x00);            // black
        case 1: return QColor(0xFF, 0x00, 0x00);            // red
        case 2: return QColor(0x00, 0xFF, 0x00);            // green
        case 3: return QColor(0x00, 0x00, 0xFF);            // blue
        case 4: return QColor(0xFF, 0xFF, 0x00);            // yellow
        case 5: return QColor(0xFF, 0x00, 0xFF);            // magenta
        case 6: return QColor(0x00, 0xFF, 0xFF);            // cyan
        case 7: return QColor(0xFF, 0xFF, 0xFF);            // white
        case 8: return QColor::fromRgbF(0.7, 0.7, 0.7);     // gray
        case 9: return QColor::fromRgbF(0.4, 0.4, 0.4);     // darkGray
        default: return QColor();
    }
}

int ColorText::escapeLen(const QString& text, int i) {
    const int n = text.size();
    if (i >= n || text[i] != QLatin1Char('^')) return 0;
    if (i + 1 >= n) return 0;
    const QChar c1 = text[i + 1];
    if (c1.isDigit()) return 2;                              // ^0..^9
    if (c1 == QLatin1Char('x') || c1 == QLatin1Char('X')) {   // ^xRRGGBB
        if (i + 8 > n) return 0;
        for (int k = i + 2; k < i + 8; ++k) {
            const QChar h = text[k];
            const bool hex = (h >= QLatin1Char('0') && h <= QLatin1Char('9'))
                           || (h >= QLatin1Char('a') && h <= QLatin1Char('f'))
                           || (h >= QLatin1Char('A') && h <= QLatin1Char('F'));
            if (!hex) return 0;
        }
        return 8;
    }
    return 0;                                                 // literal '^'
}

QColor ColorText::resolveEscape(const QString& text, int i, int len) {
    if (len == 2) return paletteColor(text[i + 1].digitValue());
    // len == 8: ^xRRGGBB
    return QColor::fromRgb(text.mid(i + 2, 6).toUInt(nullptr, 16));
}

QVariantList ColorText::parse(const QString& text, const QColor& defaultColor) const {
    QVariantList runs;
    QColor cur = defaultColor;
    QString buf;
    const int n = text.size();
    auto flush = [&]() {
        if (!buf.isEmpty()) {
            QVariantMap run;
            run["color"] = cur;
            run["text"] = buf;
            runs.append(run);
            buf.clear();
        }
    };
    int i = 0;
    while (i < n) {
        const int len = escapeLen(text, i);
        if (len > 0) {
            flush();
            cur = resolveEscape(text, i, len);
            i += len;
            continue;
        }
        if (text[i] == QLatin1Char('^')) {
            // Literal '^' (no ^^ escape, no recognised form follows).
            buf += text[i];
            ++i;
            continue;
        }
        buf += text[i];
        ++i;
    }
    flush();
    return runs;
}

static QString htmlEscape(const QString& s) {
    QString out;
    out.reserve(s.size());
    for (const QChar c : s) {
        if (c == QLatin1Char('&')) out += QStringLiteral("&amp;");
        else if (c == QLatin1Char('<')) out += QStringLiteral("&lt;");
        else if (c == QLatin1Char('>')) out += QStringLiteral("&gt;");
        else if (c == QLatin1Char('\n')) out += QStringLiteral("<br>");
        else out += c;
    }
    return out;
}

QString ColorText::toStyledText(const QString& text, const QColor& defaultColor) const {
    const QVariantList runs = parse(text, defaultColor);
    QString out;
    for (const QVariant& rv : runs) {
        const QVariantMap run = rv.toMap();
        const QColor c = run.value("color").value<QColor>();
        const QString t = htmlEscape(run.value("text").toString());
        out += QStringLiteral("<font color=\"%1\">%2</font>").arg(c.name(), t);
    }
    return out;
}

QString ColorText::stripColorCodes(const QString& text) const {
    QString out;
    out.reserve(text.size());
    const int n = text.size();
    int i = 0;
    while (i < n) {
        const int len = escapeLen(text, i);
        if (len > 0) { i += len; continue; }
        out += text[i];
        ++i;
    }
    return out;
}
