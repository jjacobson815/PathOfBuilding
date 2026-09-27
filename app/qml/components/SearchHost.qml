import QtQuick

// SearchHost — Tier 2, ported from legacy SearchHost.lua: the type-to-filter
// engine behind DropDownControl/GemSelectControl/ItemDBControl-style
// consumers — word-order caseless substring matching (each space-separated
// search word must match, case-insensitively, AFTER the previous word's
// match end — not just "contains all words anywhere") plus per-word
// highlight ranges for the matched substrings.
//
// Range convention deviation: legacy's Lua `string.find` returns 1-based
// INCLUSIVE [from,to]; ranges here are 0-based HALF-OPEN [from,to) (JS
// string-slicing convention: `value.slice(from, to)` extracts the match).
// The word-escaping/case-insensitive-PATTERN dance in legacy's
// wordsToCaselessPatterns doesn't apply here — JS has no pattern-matching
// `string.find`; plain `indexOf` on lower-cased strings already does a
// literal, case-insensitive substring search.
QtObject {
    id: root

    property var listAccessor: null    // function(): array
    property var valueAccessor: null   // function(entry): string

    property string searchTerm: ""
    property var searchInfos: []       // parallel to listAccessor()'s array: {matches, ranges:[{from,to}]}
    property int matchCount: 0

    readonly property bool searchActive: searchTerm.length > 0

    function _splitWords(s) {
        var m = s.match(/\S+/g);
        return m || [];
    }
    function _matchWords(words, entry) {
        var value = root.valueAccessor ? root.valueAccessor(entry) : entry;
        var lowerValue = String(value).toLowerCase();
        var info = { ranges: [], matches: true };
        var lastMatchEnd = 0;
        for (var i = 0; i < words.length; i++) {
            var word = words[i].toLowerCase();
            var idx = lowerValue.indexOf(word, lastMatchEnd);
            if (idx >= 0) {
                info.ranges.push({ from: idx, to: idx + word.length });
                lastMatchEnd = idx + word.length;
            } else {
                info.matches = false;
            }
        }
        return info;
    }
    function _matchTerm(term, list) {
        if (!term || term.length === 0 || !list) return [];
        var words = root._splitWords(term);
        var out = [];
        for (var i = 0; i < list.length; i++) out.push(root._matchWords(words, list[i]));
        return out;
    }

    function onSearchChar(ch) {
        if (/\s/.test(ch)) {
            if (root.searchTerm === "" || /\s/.test(root.searchTerm.slice(-1))) return root;
        }
        if (!/[\x00-\x1f\x7f]/.test(ch)) {
            root.searchTerm = root.searchTerm + ch;
            root.updateSearch();
        }
        return root;
    }
    function onSearchKeyDown(key) {
        if (root.searchActive && key === "ESCAPE") { root.resetSearch(); return root; }
        else if (root.searchActive && key === "BACK") {
            root.searchTerm = root.searchTerm.slice(0, -1);
            root.updateSearch();
            return root;
        }
        return null;
    }
    function _updateMatchCount() {
        var count = 0;
        for (var i = 0; i < root.searchInfos.length; i++) if (root.searchInfos[i] && root.searchInfos[i].matches) count++;
        root.matchCount = count;
    }
    function updateSearch() {
        if (root.listAccessor) {
            root.searchInfos = root._matchTerm(root.searchTerm, root.listAccessor());
            root._updateMatchCount();
        }
    }
    function resetSearch() {
        root.searchTerm = "";
        root.matchCount = 0;
        root.searchInfos = [];
    }
    // Mirrors GetSearchTermPretty — a ColorText-ready string (white while
    // inactive/matching, red once active with zero matches).
    function searchTermPretty() {
        var color = (root.searchActive && root.matchCount > 0) ? "^xFFFFFF" : "^xFF0000";
        return color + root.searchTerm;
    }
}
