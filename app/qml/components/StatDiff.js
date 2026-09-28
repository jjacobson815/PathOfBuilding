.pragma library

// Shared rendering of the bridge's stat-diff records (pob_diffStatList:
// { label, diffStr, positive, percent }) into tooltip lines — the QML side of
// buildMode:AddStatComparesToTooltip / CompareStatList (Build.lua:1811).
// Colours are legacy colorCodes.POSITIVE / NEGATIVE (Data/Global.lua:26-27).

var POSITIVE = "^x33FF77"
var NEGATIVE = "^xDD0022"

function line(rec) {
    var s = (rec.positive ? POSITIVE : NEGATIVE) + rec.diffStr + " " + rec.label
    if (rec.percent !== undefined && rec.percent !== null && isFinite(rec.percent))
        s += " (" + (rec.percent >= 0 ? "+" : "") + rec.percent.toFixed(1) + "%)"
    return s
}

// Appends `header` then one line per record; returns the number of records.
// Empty-table payloads cross the bridge as maps, so guard `.length`.
function addToTooltip(tooltip, header, stats, minionStats) {
    var n = (stats && stats.length) ? stats.length : 0
    var m = (minionStats && minionStats.length) ? minionStats.length : 0
    if (n + m === 0) return 0
    tooltip.addSeparator(10)
    tooltip.addLine(14, header)
    for (var i = 0; i < n; i++) tooltip.addLine(14, line(stats[i]))
    if (m > 0) {
        tooltip.addLine(14, "^7Minion:")
        for (var j = 0; j < m; j++) tooltip.addLine(14, line(minionStats[j]))
    }
    return n + m
}

// Fill `tooltip` from a bridge result { lines: [{size,text,center}|{sep,size}] }
// (the pob_skills* / pob_get*TooltipLines shape).
function fillFromLines(tooltip, t) {
    if (!t || !t.lines || t.lines.length === undefined) return
    for (var i = 0; i < t.lines.length; i++) {
        var l = t.lines[i]
        if (l.sep) tooltip.addSeparator(l.size)
        else tooltip.addLine(l.size, l.text.length > 0 ? l.text : " ")
    }
}
