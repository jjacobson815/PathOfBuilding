#include "Theme.h"
#include "LuaEngine.h"

#include <QDebug>
#include <cmath>
#include <algorithm>

Theme::Theme(QObject* parent) : QObject(parent) {}

QColor Theme::parseColor(const QVariant& v) {
    // Form 1: RGB triple in 0..1 — the actual format used by UITheme.lua
    //         (e.g. colour.topBarBg = { 0.2, 0.2, 0.2 }).
    if (v.canConvert<QVariantList>()) {
        QVariantList l = v.toList();
        if (l.size() == 3) {
            return QColor::fromRgbF(
                l[0].toDouble(), l[1].toDouble(), l[2].toDouble());
        }
    }
    // Form 2: markup string — legacy SimpleGraphic "^RRGGBB" or "#RRGGBB".
    QString s = v.toString().trimmed();
    if (s.startsWith('^')) s = s.mid(1);
    if (s.startsWith('#')) s = s.mid(1);
    if (s.size() == 6) {
        bool ok = false;
        uint rgb = s.toUInt(&ok, 16);
        if (ok) return QColor::fromRgb(rgb);
    }
    return QColor(); // invalid / unrecognised
}

void Theme::init(LuaEngine* engine) {
    if (!engine) {
        qWarning() << "[theme] init called with null LuaEngine";
        return;
    }

    // uiTheme is a *local* in Modules/Build.lua, not a Lua global, so we load
    // the module directly through the engine's LoadModule global (the same
    // seam Build.lua uses) rather than via getPath("uiTheme...").
    QVariant themeVar = engine->callGlobal("LoadModule", { "Modules/UITheme" });
    QVariantMap theme = themeVar.toMap();
    m_raw = theme;

    // --- Sizes (top-level pixel constants) ---
    m_sideBarWidth   = theme.value("sideBarWidth").toInt();
    m_topBarHeight   = theme.value("topBarHeight").toInt();
    m_navButtonHeight = theme.value("navButtonHeight").toInt();
    m_navButtonGap   = theme.value("navButtonGap").toInt();
    m_navRowGap      = theme.value("navRowGap").toInt();

    // --- navWidth sub-table (per-group button widths) ---
    QVariantMap navWidth = theme.value("navWidth").toMap();
    m_navWidthPrimary  = navWidth.value("primary").toInt();
    m_navWidthUtility  = navWidth.value("utility").toInt();

    // --- Colours (UITheme.colour.*) ---
    QVariantMap colour = theme.value("colour").toMap();
    m_topBarBg       = parseColor(colour.value("topBarBg"));
    m_topBarLine     = parseColor(colour.value("topBarLine"));
    m_sideBarBg      = parseColor(colour.value("sideBarBg"));
    m_sideBarLine    = parseColor(colour.value("sideBarLine"));
    m_navActiveAccent = parseColor(colour.value("navActiveAccent"));
    m_groupHeader    = parseColor(colour.value("groupHeader"));
    m_accentAlt      = parseColor(colour.value("accentAlt"));
    if (!m_accentAlt.isValid()) m_accentAlt = m_accent; // fallback to primary accent

    // --- Semantic aliases (mapped from the raw colours above) ---
    m_background = m_sideBarBg;
    m_titleBar   = m_topBarBg;
    m_accent     = m_navActiveAccent;
    m_section    = m_groupHeader;

    // --- UI defaults the engine theme does not yet define ---
    // (Documented; remove once UITheme gains equivalent fields.)
    m_text       = QColor(255, 255, 255); // #FFFFFF pure white (Cyber Citrus text)
    m_muted      = QColor(148, 163, 184); // #94A3B8 slate-400 (readable on #0F172A)
    m_mutedDark  = QColor(100, 116, 139); // #64748B slate-500
    m_controlSize = m_navButtonHeight > 0 ? m_navButtonHeight : 20;

    // Bundled font families (Phase 1.2a) — the real TTFs backing these are
    // registered in main.cpp via QFontDatabase::addApplicationFont, from the
    // same runtime/SimpleGraphic/Fonts dir TextMetrics reads .tgf atlases
    // from. fontFamily's old hardcoded "sans-serif" default is replaced with
    // the bundled VAR face; UITheme.typography.fontFamily (below) can still
    // override it.
    m_fontVar     = "Liberation Sans";
    m_fontVarBold = "Liberation Sans"; // same family; pair with font.bold: true
    m_fontFixed   = "Bitstream Vera Sans Mono";
    m_fontFamily = m_fontVar;
    m_fontSize   = 14;

    // --- Extended design-system tokens (Phase 1) ---
    // Semantic / state colours (fall back to existing tokens if absent)
    m_success  = parseColor(colour.value("success"));      if (!m_success.isValid())  m_success  = m_accentAlt;
    m_warning  = parseColor(colour.value("warning"));      if (!m_warning.isValid())  m_warning  = QColor(245, 158, 11);
    m_danger   = parseColor(colour.value("danger"));       if (!m_danger.isValid())   m_danger   = QColor(239, 68, 68);
    m_info     = parseColor(colour.value("info"));         if (!m_info.isValid())     m_info     = m_section;
    m_hover    = parseColor(colour.value("hover"));        if (!m_hover.isValid())    m_hover    = m_background;
    m_active   = parseColor(colour.value("active"));       if (!m_active.isValid())   m_active   = m_accent;
    m_disabled = parseColor(colour.value("disabled"));     if (!m_disabled.isValid()) m_disabled = m_mutedDark;
    m_border   = parseColor(colour.value("border"));       if (!m_border.isValid())   m_border   = m_topBarLine;
    m_borderStrong = parseColor(colour.value("borderStrong")); if (!m_borderStrong.isValid()) m_borderStrong = m_muted;

    // Typography
    QVariantMap typography = theme.value("typography").toMap();
    if (!typography.value("fontFamily").toString().isEmpty())
        m_fontFamily = typography.value("fontFamily").toString();
    if (typography.value("fontSize").toInt())      m_fontSize     = typography.value("fontSize").toInt();
    m_fontSizeSm   = typography.value("fontSizeSm").toInt() ? typography.value("fontSizeSm").toInt() : m_fontSize - 2;
    m_fontSizeLg   = typography.value("fontSizeLg").toInt() ? typography.value("fontSizeLg").toInt() : m_fontSize + 4;
    m_lineHeight   = typography.value("lineHeight").toDouble() ? typography.value("lineHeight").toDouble() : 1.35;
    m_fontWeightNormal = typography.value("fontWeightNormal").toInt() ? typography.value("fontWeightNormal").toInt() : 400;
    m_fontWeightBold   = typography.value("fontWeightBold").toInt() ? typography.value("fontWeightBold").toInt() : 700;

    // Spacing scale
    QVariantMap spacing = theme.value("spacing").toMap();
    m_space1 = spacing.value("space1").toInt() ? spacing.value("space1").toInt() : 4;
    m_space2 = spacing.value("space2").toInt() ? spacing.value("space2").toInt() : 8;
    m_space3 = spacing.value("space3").toInt() ? spacing.value("space3").toInt() : 12;
    m_space4 = spacing.value("space4").toInt() ? spacing.value("space4").toInt() : 16;
    m_space5 = spacing.value("space5").toInt() ? spacing.value("space5").toInt() : 24;
    m_space6 = spacing.value("space6").toInt() ? spacing.value("space6").toInt() : 32;

    // Radii
    QVariantMap radii = theme.value("radii").toMap();
    m_radiusControl = radii.value("radiusControl").toInt() ? radii.value("radiusControl").toInt() : 4;
    m_radiusCard    = radii.value("radiusCard").toInt()   ? radii.value("radiusCard").toInt()   : 8;
    m_radiusPill    = radii.value("radiusPill").toInt()   ? radii.value("radiusPill").toInt()   : 999;

    // Elevation (shadow tint + per-level blur radius / y-offset)
    QVariantMap elevation = theme.value("elevation").toMap();
    m_shadowColor = parseColor(elevation.value("shadowColor"));
    if (!m_shadowColor.isValid()) m_shadowColor = QColor(0, 0, 0);
    m_shadowColor.setAlpha(120); // semi-transparent tint for drop shadows
    m_shadow1Radius = elevation.value("r1").toInt() ? elevation.value("r1").toInt() : 6;
    m_shadow1Y      = elevation.value("y1").toInt() ? elevation.value("y1").toInt() : 2;
    m_shadow2Radius = elevation.value("r2").toInt() ? elevation.value("r2").toInt() : 12;
    m_shadow2Y      = elevation.value("y2").toInt() ? elevation.value("y2").toInt() : 4;
    m_shadow3Radius = elevation.value("r3").toInt() ? elevation.value("r3").toInt() : 20;
    m_shadow3Y      = elevation.value("y3").toInt() ? elevation.value("y3").toInt() : 8;

    // --- Item rarity colours (Phase 5a) ---
    // Pulled from the engine's `colorCodes` global (src/Data/Global.lua),
    // which holds the canonical PoB rarity markup strings ("^RRGGBB").
    // parseColor handles the "^RRGGBB" form. Falls back to the UI
    // defaults above if the global is unavailable.
    QVariantMap colorCodes = engine->getGlobal("colorCodes").toMap();
    m_rarityNormal = parseColor(colorCodes.value("NORMAL"));
    m_rarityMagic   = parseColor(colorCodes.value("MAGIC"));
    m_rarityRare    = parseColor(colorCodes.value("RARE"));
    m_rarityUnique  = parseColor(colorCodes.value("UNIQUE"));
    m_rarityRelic   = parseColor(colorCodes.value("RELIC"));
    if (!m_rarityNormal.isValid()) m_rarityNormal = m_muted;
    if (!m_rarityMagic.isValid()) m_rarityMagic = m_accent;
    if (!m_rarityRare.isValid()) m_rarityRare = m_section;
    if (!m_rarityUnique.isValid()) m_rarityUnique = m_text;
    if (!m_rarityRelic.isValid()) m_rarityRelic = m_titleBar;

    // Phase 1b verification: report a few resolved values.
    qDebug().noquote() << "[theme] loaded from UITheme:"
        << "topBarBg=" << m_topBarBg.name()
        << "sideBarBg=" << m_sideBarBg.name()
        << "navActiveAccent=" << m_navActiveAccent.name()
        << "groupHeader=" << m_groupHeader.name()
        << "sideBarWidth=" << m_sideBarWidth
        << "topBarHeight=" << m_topBarHeight
        << "navButtonHeight=" << m_navButtonHeight
        << "navWidth.primary=" << m_navWidthPrimary
        << "navWidth.utility=" << m_navWidthUtility
        << "success=" << m_success.name()
        << "warning=" << m_warning.name()
        << "danger=" << m_danger.name()
        << "radiusCard=" << m_radiusCard
        << "space3=" << m_space3;
}

QVariantMap Theme::fontFor(const QString& legacyName) const {
    const QString f = legacyName.trimmed().toUpper();
    QVariantMap r;
    r["bold"] = false;
    r["italic"] = false;
    if (f == "VAR") {
        r["family"] = m_fontVar;
    } else if (f == "VAR BOLD") {
        r["family"] = m_fontVarBold;
        r["bold"] = true;
    } else if (f == "FONTIN") {
        r["family"] = m_fontVar; // Fontin licensing deferred — see STATUS.md
    } else if (f == "FONTIN ITALIC") {
        r["family"] = m_fontVar;
        r["italic"] = true;
    } else if (f == "FONTIN SC" || f == "FONTIN SC ITALIC") {
        r["family"] = m_fontVar; // no small-caps substitute yet
        r["italic"] = (f == "FONTIN SC ITALIC");
    } else {
        // "FIXED" and anything unrecognised (including empty) — legacy default.
        r["family"] = m_fontFixed;
    }
    return r;
}

bool Theme::contrastOk(const QColor& fg, const QColor& bg) const {
    // WCAG 2.1 relative luminance
    auto lum = [](const QColor& c) -> double {
        auto f = [](double v) {
            v /= 255.0;
            return v <= 0.03928 ? v / 12.92 : std::pow((v + 0.055) / 1.055, 2.4);
        };
        return 0.2126 * f(c.red()) + 0.7152 * f(c.green()) + 0.0722 * f(c.blue());
    };
    double l1 = lum(fg), l2 = lum(bg);
    double ratio = (std::max(l1, l2) + 0.05) / (std::min(l1, l2) + 0.05);
    return ratio >= 4.5; // AA for normal text
}
