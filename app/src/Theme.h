#pragma once
#include <QObject>
#include <QColor>
#include <QVariantMap>
#include <QString>

class LuaEngine;

// QML theme singleton (exposed from main.cpp as the context property "theme").
//
// Centralises the engine's UI layout/colour constants so QML no longer hardcodes
// hex colours or pixel sizes. Values are read ONCE from the engine's UITheme
// module (src/Modules/UITheme.lua) via LuaEngine::callGlobal("LoadModule",
// { "Modules/UITheme" }) and cached into Q_PROPERTYs.
//
// IMPORTANT — actual format vs. the original SimpleGraphic frontend:
//   The engine's UITheme.lua stores colours as RGB *triples* in 0..1, e.g.
//   colour.topBarBg = { 0.2, 0.2, 0.2 }.  The legacy SimpleGraphic UI used
//   "^RRGGBB" markup strings instead. parseColor() therefore handles BOTH forms
//   defensively so the singleton keeps working if a future UITheme revision
//   switches to markup strings.
//
// The engine's UITheme does NOT yet define a text colour, font family, or base
// font size, so a small set of documented UI defaults (text, muted, mutedDark,
// controlSize, fontFamily, fontSize) are provided by Theme itself. These are
// clearly marked as defaults and can be removed once UITheme gains the fields.
class Theme : public QObject {
    Q_OBJECT

    // --- Raw engine colours (UITheme.colour.*) -----------------------------
    Q_PROPERTY(QColor topBarBg READ topBarBg CONSTANT)
    Q_PROPERTY(QColor topBarLine READ topBarLine CONSTANT)
    Q_PROPERTY(QColor sideBarBg READ sideBarBg CONSTANT)
    Q_PROPERTY(QColor sideBarLine READ sideBarLine CONSTANT)
    Q_PROPERTY(QColor navActiveAccent READ navActiveAccent CONSTANT)
    Q_PROPERTY(QColor groupHeader READ groupHeader CONSTANT)
    Q_PROPERTY(QColor accentAlt READ accentAlt CONSTANT)     // = colour.accentAlt (#22C55E)

    // --- Sizes in pixels (UITheme.* and UITheme.navWidth.*) -----------------
    Q_PROPERTY(int sideBarWidth READ sideBarWidth CONSTANT)
    Q_PROPERTY(int topBarHeight READ topBarHeight CONSTANT)
    Q_PROPERTY(int navButtonHeight READ navButtonHeight CONSTANT)
    Q_PROPERTY(int navButtonGap READ navButtonGap CONSTANT)
    Q_PROPERTY(int navRowGap READ navRowGap CONSTANT)
    Q_PROPERTY(int navWidthPrimary READ navWidthPrimary CONSTANT)
    Q_PROPERTY(int navWidthUtility READ navWidthUtility CONSTANT)

    // --- Semantic convenience aliases (mapped from the raw colours) ---------
    Q_PROPERTY(QColor background READ background CONSTANT)   // = sideBarBg
    Q_PROPERTY(QColor titleBar READ titleBar CONSTANT)       // = topBarBg
    Q_PROPERTY(QColor accent READ accent CONSTANT)           // = navActiveAccent
    Q_PROPERTY(QColor section READ section CONSTANT)         // = groupHeader

    // --- UI defaults the engine theme does not yet define (documented) ------
    Q_PROPERTY(QColor text READ text CONSTANT)               // default light text
    Q_PROPERTY(QColor muted READ muted CONSTANT)             // default mid-grey
    Q_PROPERTY(QColor mutedDark READ mutedDark CONSTANT)     // default dark-grey
    Q_PROPERTY(int controlSize READ controlSize CONSTANT)    // default = navButtonHeight
    Q_PROPERTY(QString fontFamily READ fontFamily CONSTANT)  // default "sans-serif"
    Q_PROPERTY(int fontSize READ fontSize CONSTANT)          // default 14

    // --- Bundled font families (Phase 1.2a) ------------------------------
    // Real TTFs registered in main.cpp via QFontDatabase::addApplicationFont,
    // backing the SAME families TextMetrics measures against via the .tgf
    // atlases (runtime/SimpleGraphic/Fonts). Use fontFor() to resolve one of
    // the 7 legacy fontMap names (FIXED/VAR/VAR BOLD/FONTIN*) to a QML-ready
    // {family, bold, italic} triple; Fontin names fall back to fontVar (see
    // the Fontin-licensing decision in STATUS.md).
    Q_PROPERTY(QString fontVar READ fontVar CONSTANT)        // "Liberation Sans"
    Q_PROPERTY(QString fontVarBold READ fontVarBold CONSTANT)// same family; pair with font.bold
    Q_PROPERTY(QString fontFixed READ fontFixed CONSTANT)    // "Bitstream Vera Sans Mono"

    // --- Item rarity colours (Phase 5a) ---------------------------------
    // Pulled from the engine's `colorCodes` global (src/Data/Global.lua),
    // which holds the canonical PoB rarity markup strings ("^RRGGBB").
    // Exposed so the ITEMS view can colour item names by rarity without
    // hardcoding hex in QML.
    Q_PROPERTY(QColor rarityNormal READ rarityNormal CONSTANT)
    Q_PROPERTY(QColor rarityMagic READ rarityMagic CONSTANT)
    Q_PROPERTY(QColor rarityRare READ rarityRare CONSTANT)
    Q_PROPERTY(QColor rarityUnique READ rarityUnique CONSTANT)
    Q_PROPERTY(QColor rarityRelic READ rarityRelic CONSTANT)

    // --- Semantic / state colours (Phase 1) -----------------------------
    Q_PROPERTY(QColor success READ success CONSTANT)
    Q_PROPERTY(QColor warning READ warning CONSTANT)
    Q_PROPERTY(QColor danger READ danger CONSTANT)
    Q_PROPERTY(QColor info READ info CONSTANT)
    Q_PROPERTY(QColor hover READ hover CONSTANT)
    Q_PROPERTY(QColor active READ active CONSTANT)
    Q_PROPERTY(QColor disabled READ disabled CONSTANT)
    Q_PROPERTY(QColor border READ border CONSTANT)
    Q_PROPERTY(QColor borderStrong READ borderStrong CONSTANT)

    // --- Typography (Phase 1) -------------------------------------------
    Q_PROPERTY(int fontSizeSm READ fontSizeSm CONSTANT)
    Q_PROPERTY(int fontSizeLg READ fontSizeLg CONSTANT)
    Q_PROPERTY(double lineHeight READ lineHeight CONSTANT)
    Q_PROPERTY(int fontWeightNormal READ fontWeightNormal CONSTANT)
    Q_PROPERTY(int fontWeightBold READ fontWeightBold CONSTANT)

    // --- Spacing scale px (Phase 1) -------------------------------------
    Q_PROPERTY(int space1 READ space1 CONSTANT)
    Q_PROPERTY(int space2 READ space2 CONSTANT)
    Q_PROPERTY(int space3 READ space3 CONSTANT)
    Q_PROPERTY(int space4 READ space4 CONSTANT)
    Q_PROPERTY(int space5 READ space5 CONSTANT)
    Q_PROPERTY(int space6 READ space6 CONSTANT)

    // --- Radii px (Phase 1) ---------------------------------------------
    Q_PROPERTY(int radiusControl READ radiusControl CONSTANT)
    Q_PROPERTY(int radiusCard READ radiusCard CONSTANT)
    Q_PROPERTY(int radiusPill READ radiusPill CONSTANT)

    // --- Elevation (Phase 1) --------------------------------------------
    Q_PROPERTY(QColor shadowColor READ shadowColor CONSTANT)
    Q_PROPERTY(int shadow1Radius READ shadow1Radius CONSTANT)
    Q_PROPERTY(int shadow1Y READ shadow1Y CONSTANT)
    Q_PROPERTY(int shadow2Radius READ shadow2Radius CONSTANT)
    Q_PROPERTY(int shadow2Y READ shadow2Y CONSTANT)
    Q_PROPERTY(int shadow3Radius READ shadow3Radius CONSTANT)
    Q_PROPERTY(int shadow3Y READ shadow3Y CONSTANT)

    // --- Fallback: the entire uiTheme table as returned by Lua --------------
    Q_PROPERTY(QVariantMap raw READ raw CONSTANT)

public:
    explicit Theme(QObject* parent = nullptr);

    // Pull values from the engine's UITheme module. Must be called AFTER
    // LuaEngine::init() so the module (and the LoadModule global) exist.
    void init(LuaEngine* engine);

    // WCAG AA contrast check (ratio >= 4.5). Useful for design-token audits.
    Q_INVOKABLE bool contrastOk(const QColor& fg, const QColor& bg) const;

    // Resolve one of the 7 legacy fontMap names (nil/"" -> FIXED, per legacy
    // default) to a QML-ready { family: string, bold: bool, italic: bool }
    // triple. FONTIN/FONTIN ITALIC/FONTIN SC/FONTIN SC ITALIC currently map to
    // the VAR face (Fontin licensing is deferred — see STATUS.md open
    // decisions); TextMetrics still measures those against the real bundled
    // Fontin .tgf atlases, so this is a rendering-only approximation.
    Q_INVOKABLE QVariantMap fontFor(const QString& legacyName) const;

    // --- accessors ----------------------------------------------------------
    QColor topBarBg() const { return m_topBarBg; }
    QColor topBarLine() const { return m_topBarLine; }
    QColor sideBarBg() const { return m_sideBarBg; }
    QColor sideBarLine() const { return m_sideBarLine; }
    QColor navActiveAccent() const { return m_navActiveAccent; }
    QColor groupHeader() const { return m_groupHeader; }
    QColor accentAlt() const { return m_accentAlt; }

    int sideBarWidth() const { return m_sideBarWidth; }
    int topBarHeight() const { return m_topBarHeight; }
    int navButtonHeight() const { return m_navButtonHeight; }
    int navButtonGap() const { return m_navButtonGap; }
    int navRowGap() const { return m_navRowGap; }
    int navWidthPrimary() const { return m_navWidthPrimary; }
    int navWidthUtility() const { return m_navWidthUtility; }

    QColor background() const { return m_background; }
    QColor titleBar() const { return m_titleBar; }
    QColor accent() const { return m_accent; }
    QColor section() const { return m_section; }

    QColor text() const { return m_text; }
    QColor muted() const { return m_muted; }
    QColor mutedDark() const { return m_mutedDark; }
    int controlSize() const { return m_controlSize; }
    QString fontFamily() const { return m_fontFamily; }
    int fontSize() const { return m_fontSize; }

    QString fontVar() const { return m_fontVar; }
    QString fontVarBold() const { return m_fontVarBold; }
    QString fontFixed() const { return m_fontFixed; }

    QColor rarityNormal() const { return m_rarityNormal; }
    QColor rarityMagic() const { return m_rarityMagic; }
    QColor rarityRare() const { return m_rarityRare; }
    QColor rarityUnique() const { return m_rarityUnique; }
    QColor rarityRelic() const { return m_rarityRelic; }

    QColor success() const { return m_success; }
    QColor warning() const { return m_warning; }
    QColor danger() const { return m_danger; }
    QColor info() const { return m_info; }
    QColor hover() const { return m_hover; }
    QColor active() const { return m_active; }
    QColor disabled() const { return m_disabled; }
    QColor border() const { return m_border; }
    QColor borderStrong() const { return m_borderStrong; }

    int fontSizeSm() const { return m_fontSizeSm; }
    int fontSizeLg() const { return m_fontSizeLg; }
    double lineHeight() const { return m_lineHeight; }
    int fontWeightNormal() const { return m_fontWeightNormal; }
    int fontWeightBold() const { return m_fontWeightBold; }

    int space1() const { return m_space1; }
    int space2() const { return m_space2; }
    int space3() const { return m_space3; }
    int space4() const { return m_space4; }
    int space5() const { return m_space5; }
    int space6() const { return m_space6; }

    int radiusControl() const { return m_radiusControl; }
    int radiusCard() const { return m_radiusCard; }
    int radiusPill() const { return m_radiusPill; }

    QColor shadowColor() const { return m_shadowColor; }
    int shadow1Radius() const { return m_shadow1Radius; }
    int shadow1Y() const { return m_shadow1Y; }
    int shadow2Radius() const { return m_shadow2Radius; }
    int shadow2Y() const { return m_shadow2Y; }
    int shadow3Radius() const { return m_shadow3Radius; }
    int shadow3Y() const { return m_shadow3Y; }

    QVariantMap raw() const { return m_raw; }

private:
    // Parse a Lua colour value into a QColor. Supports:
    //   * a QVariantList of 3 numbers in 0..1  (UITheme.lua's actual format)
    //   * a string "^RRGGBB" or "#RRGGBB"       (legacy SimpleGraphic markup)
    static QColor parseColor(const QVariant& v);

    QColor m_topBarBg, m_topBarLine, m_sideBarBg, m_sideBarLine;
    QColor m_navActiveAccent, m_groupHeader, m_accentAlt;

    int m_sideBarWidth = 0, m_topBarHeight = 0, m_navButtonHeight = 0;
    int m_navButtonGap = 0, m_navRowGap = 0;
    int m_navWidthPrimary = 0, m_navWidthUtility = 0;

    QColor m_background, m_titleBar, m_accent, m_section;
    QColor m_text, m_muted, m_mutedDark;
    int m_controlSize = 0;
    QString m_fontFamily;
    int m_fontSize = 0;

    QString m_fontVar, m_fontVarBold, m_fontFixed;

    QColor m_rarityNormal, m_rarityMagic, m_rarityRare, m_rarityUnique, m_rarityRelic;

    // Phase 1 design-system tokens
    QColor m_success, m_warning, m_danger, m_info, m_hover, m_active, m_disabled, m_border, m_borderStrong;
    int m_fontSizeSm = 0, m_fontSizeLg = 0, m_fontWeightNormal = 400, m_fontWeightBold = 700;
    double m_lineHeight = 1.3;
    int m_space1 = 4, m_space2 = 8, m_space3 = 12, m_space4 = 16, m_space5 = 24, m_space6 = 32;
    int m_radiusControl = 4, m_radiusCard = 8, m_radiusPill = 999;
    QColor m_shadowColor;
    int m_shadow1Radius = 6, m_shadow1Y = 2, m_shadow2Radius = 12, m_shadow2Y = 4, m_shadow3Radius = 20, m_shadow3Y = 8;

    QVariantMap m_raw;
};
