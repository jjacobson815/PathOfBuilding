-- Path of Building
--
-- Module: UITheme
-- Centralised layout & colour constants for the build-mode UI.
-- Loaded as a global (uiTheme) so all modules share one instance.
--
local UITheme = { }

-- Layout (pixels)
UITheme.sideBarWidth = 312
UITheme.topBarHeight = 32
UITheme.navButtonHeight = 20
UITheme.navButtonGap = 4
UITheme.navRowGap = 6

-- Navigation button width per group
UITheme.navWidth = {
    primary = 84,
    utility = 72,
}

-- Colours as RGB triples (0..1) — "Cyber Citrus" high-contrast tech palette
UITheme.colour = {
    topBarBg       = { 0.059, 0.090, 0.165 }, -- #0F172A deep blue-grey
    topBarLine     = { 0.200, 0.255, 0.333 }, -- #334155 slate line
    sideBarBg      = { 0.059, 0.090, 0.165 }, -- #0F172A deep blue-grey
    sideBarLine    = { 0.200, 0.255, 0.333 }, -- #334155 slate line
    navActiveAccent = { 0.639, 0.902, 0.208 }, -- #A3E635 neon lime (primary accent)
    accentAlt      = { 0.133, 0.773, 0.369 }, -- #22C55E green (secondary emphasis / positive values)
    groupHeader    = { 0.024, 0.714, 0.831 }, -- #06B6D4 bright cyan (secondary action)
    -- Semantic / state colours (Phase 1 design system)
    success        = { 0.133, 0.773, 0.369 }, -- #22C55E green (positive)
    warning        = { 0.961, 0.620, 0.043 }, -- #F59E0B amber
    danger         = { 0.937, 0.267, 0.267 }, -- #EF4444 red
    info           = { 0.024, 0.714, 0.831 }, -- #06B6D4 cyan
    hover          = { 0.145, 0.180, 0.278 }, -- #25304A row/control hover
    active         = { 0.180, 0.220, 0.330 }, -- #2E3854 active highlight
    disabled       = { 0.078, 0.094, 0.137 }, -- #141822 disabled surface
    border         = { 0.200, 0.255, 0.333 }, -- #334155 hairline border
    borderStrong   = { 0.310, 0.380, 0.490 }, -- #4F617D strong border
}

-- Typography (Phase 1)
UITheme.typography = {
    fontFamily     = "Inter, Segoe UI, sans-serif",
    fontSize       = 14,
    fontSizeSm     = 12,
    fontSizeLg     = 18,
    lineHeight     = 1.35,
    fontWeightNormal = 400,
    fontWeightBold   = 700,
}

-- Spacing scale in px (Phase 1) — canonical key names match Theme Q_PROPERTYs
UITheme.spacing = {
    space1 = 4, space2 = 8, space3 = 12, space4 = 16, space5 = 24, space6 = 32,
}

-- Corner radii in px (Phase 1) — canonical key names match Theme Q_PROPERTYs
UITheme.radii = {
    radiusControl = 4, radiusCard = 8, radiusPill = 999,
}

-- Elevation: shadow tint + per-level blur radius / y-offset (Phase 1)
UITheme.elevation = {
    shadowColor = { 0.0, 0.0, 0.0 }, -- black tint; alpha applied in Theme.cpp
    r1 = 6, y1 = 2,
    r2 = 12, y2 = 4,
    r3 = 20, y3 = 8,
}

return UITheme
