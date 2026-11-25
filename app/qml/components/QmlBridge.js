.pragma library

function toArray(v) {
    if (Array.isArray(v)) return v;
    if (v && typeof v !== "string" && typeof v.length === "number") {
        var out = [];
        for (var i = 0; i < v.length; i++) out.push(v[i]);
        return out;
    }
    return [];
}
