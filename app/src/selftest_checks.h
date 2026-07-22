#pragma once
#include <QDebug>
#include <QString>
#include "LuaEngine.h"

// Shared headless self-test suite for the LuaJIT bridge.
//
// Used by both the standalone `pob-selftest` binary (selftest.cpp) and the
// `pob-qt --headless` mode (LuaEngine::runSelfTest). Keeping the checks in one
// place guarantees the GUI binary and the CI binary exercise the exact same
// assertions, so a regression in either surface is caught identically.
//
// Returns true only if every check passed; prints progress via qDebug and
// failures via qCritical.
inline bool pob_run_all_selftests(LuaEngine& engine) {
    QStringList modes = engine.modeNames();
    qDebug() << "modes:" << modes;
    if (!modes.contains("BUILD") || !modes.contains("LIST")) {
        qCritical() << "expected modes LIST and BUILD";
        return false;
    }

    QVariant viewList = engine.getPath("main.modes.BUILD.viewList");
    if (viewList.typeId() == QMetaType::QVariantList) {
        const QVariantList vl = viewList.toList();
        qDebug() << "viewList entries:" << vl.size();
        for (const QVariant& e : vl) {
            const QVariantMap m = e.toMap();
            qDebug().noquote() << "  -" << m.value("id").toString()
                     << m.value("label").toString()
                     << "key=" << m.value("key").toString()
                     << "group=" << m.value("group").toString();
        }
    } else {
        qCritical() << "viewList is not a list:" << viewList.typeName();
        return false;
    }

    // Build:Init runs calcsTab:BuildOutput() during OnInit/OnFrame, so output exists.
    // Read only the scalar values we check via a Lua helper to avoid converting the
    // (potentially circular) full output table through the bridge.
    QVariant output = engine.callGlobal("pob_selftestCalcOutput");
    if (output.typeId() != QMetaType::QVariantMap) {
        qCritical() << "calc output missing or wrong type:" << output.typeName();
        return false;
    }
    const QVariantMap o = output.toMap();
    qDebug() << "calc output keys:" << o.size();
    // Core keys are always present for any built character.
    QStringList required = { "Life", "Mana", "TotalDPS" };
    // Optional keys may be absent for a build with no active skill (e.g. DPS/AttackSpeed).
    QStringList optional = { "EnergyShield", "DPS", "CritChance", "AttackSpeed" };
    bool ok = true;
    for (const QString& k : required) {
        if (!o.contains(k)) {
            qCritical() << "  missing required calc output key:" << k;
            ok = false;
        } else {
            qDebug().noquote() << "  " << k << "=" << o.value(k).toString();
        }
    }
    for (const QString& k : optional) {
        if (o.contains(k))
            qDebug().noquote() << "  " << k << "=" << o.value(k).toString();
        else
            qDebug().noquote() << "  " << k << "= (nil, no active skill)";
    }
    if (!ok) return false;

    // Phase 0d: verify the zlib bridge (Inflate/Deflate round-trip) and that the
    // native-module shims (lcurl.safe, lzip) load. These must not regress.
    QVariant inflateCheck = engine.callGlobal("pob_selftestInflate");
    if (inflateCheck.typeId() != QMetaType::QVariantMap) {
        qCritical() << "pob_selftestInflate missing or wrong type:" << inflateCheck.typeName();
        return false;
    }
    {
        const QVariantMap ic = inflateCheck.toMap();
        qDebug().noquote() << "inflate round-trip ok =" << ic.value("ok").toBool()
                 << " compressedLen =" << ic.value("compressedLen").toInt();
        if (!ic.value("ok").toBool()) {
            qCritical() << "Inflate/Deflate round-trip FAILED";
            return false;
        }
    }

    QVariant reqCheck = engine.callGlobal("pob_selftestRequires");
    if (reqCheck.typeId() != QMetaType::QVariantMap) {
        qCritical() << "pob_selftestRequires missing or wrong type:" << reqCheck.typeName();
        return false;
    }
    {
        const QVariantMap rc = reqCheck.toMap();
        qDebug().noquote() << "require lcurl.safe =" << rc.value("lcurl").toBool()
                 << " require lzip =" << rc.value("lzip").toBool();
        if (!rc.value("lcurl").toBool() || !rc.value("lzip").toBool()) {
            qCritical() << "native-module shim require FAILED";
            return false;
        }
    }

    // Phase 2b: verify the build save/load bridge round-trips through the real
    // xml.lua serialiser. Save the current build to an XML string, load it back,
    // and assert the buildName survives.
    QVariant slCheck = engine.callGlobal("pob_selftestSaveLoad");
    if (slCheck.typeId() != QMetaType::QVariantMap) {
        qCritical() << "pob_selftestSaveLoad missing or wrong type:" << slCheck.typeName();
        return false;
    }
    {
        const QVariantMap sc = slCheck.toMap();
        qDebug().noquote() << "save/load round-trip ok =" << sc.value("ok").toBool()
                 << " before =" << sc.value("before").toString()
                 << " after =" << sc.value("after").toString()
                 << " xmlLen =" << sc.value("xmlLen").toInt();
        if (!sc.value("ok").toBool()) {
            qCritical() << "save/load round-trip FAILED:"
                        << sc.value("error").toString();
            return false;
        }
    }

    // Phase 3: verify the LIST-mode (build library) bridge.
    QVariant blCheck = engine.callGlobal("pob_selftestBuildList");
    if (blCheck.typeId() != QMetaType::QVariantMap) {
        qCritical() << "pob_selftestBuildList missing or wrong type:" << blCheck.typeName();
        return false;
    }
    {
        const QVariantMap bc = blCheck.toMap();
        const bool ok = bc.value("ok").toBool();
        const int count = bc.value("count").toInt();
        qDebug().noquote() << "build-list ok =" << ok
                 << " count =" << count;
        if (!ok) {
            qCritical() << "build-list check FAILED:"
                        << bc.value("error").toString();
            return false;
        }
        if (count < 0) {
            qCritical() << "build-list count negative:" << count;
            return false;
        }
    }

    // Phase 3 (flow): prove the LIST -> BUILD transition works end-to-end.
    QVariant lfCheck = engine.callGlobal("pob_selftestListFlow");
    if (lfCheck.typeId() != QMetaType::QVariantMap) {
        qCritical() << "pob_selftestListFlow missing or wrong type:" << lfCheck.typeName();
        return false;
    }
    {
        const QVariantMap lf = lfCheck.toMap();
        const bool ok = lf.value("ok").toBool();
        qDebug().noquote() << "list-flow ok =" << ok
                 << " mode =" << lf.value("mode").toString()
                 << " buildName =" << lf.value("buildName").toString();
        if (!ok) {
            qCritical() << "list-flow check FAILED:"
                        << lf.value("error").toString();
            return false;
        }
    }

    // Phase 4a: prove the passive-tree data seam (pob_getTreeData) yields a
    // non-empty, well-formed tree.
    QVariant trCheck = engine.callGlobal("pob_selftestTreeRender");
    if (trCheck.typeId() != QMetaType::QVariantMap) {
        qCritical() << "pob_selftestTreeRender missing or wrong type:" << trCheck.typeName();
        return false;
    }
    {
        const QVariantMap tr = trCheck.toMap();
        const bool ok = tr.value("ok").toBool();
        const int nodeCount = tr.value("nodeCount").toInt();
        const int groupCount = tr.value("groupCount").toInt();
        const int connectorCount = tr.value("connectorCount").toInt();
        qDebug().noquote() << "tree-render ok =" << ok
                 << " nodeCount =" << nodeCount
                 << " groupCount =" << groupCount
                 << " connectorCount =" << connectorCount;
        if (!ok) {
            qCritical() << "tree-render check FAILED: tree data seam returned empty/invalid tree";
            return false;
        }
        if (nodeCount <= 0 || groupCount <= 0 || connectorCount <= 0) {
            qCritical() << "tree-render check FAILED: counts not all positive"
                        << "(nodes=" << nodeCount
                        << " groups=" << groupCount
                        << " connectors=" << connectorCount << ")";
            return false;
        }
    }

    // Phase 4b: prove the passive-tree interaction seam works end-to-end.
    QVariant tiCheck = engine.callGlobal("pob_selftestTreeInteract");
    if (tiCheck.typeId() != QMetaType::QVariantMap) {
        qCritical() << "pob_selftestTreeInteract missing or wrong type:" << tiCheck.typeName();
        return false;
    }
    {
        const QVariantMap ti = tiCheck.toMap();
        const bool ok = ti.value("ok").toBool();
        qDebug().noquote() << "tree-interact ok =" << ok
                 << " allocOk =" << ti.value("allocOk").toBool()
                 << " deallocOk =" << ti.value("deallocOk").toBool()
                 << " searchOk =" << ti.value("searchOk").toBool()
                 << " searchClearOk =" << ti.value("searchClearOk").toBool();
        if (!ok) {
            qCritical() << "tree-interact check FAILED:"
                        << ti.value("error").toString();
            return false;
        }
    }

    // Phase 5a: prove the ItemsTab (ITEMS view) bridge works end-to-end.
    QVariant icCheck = engine.callGlobal("pob_selftestItems");
    if (icCheck.typeId() != QMetaType::QVariantMap) {
        qCritical() << "pob_selftestItems missing or wrong type:" << icCheck.typeName();
        return false;
    }
    {
        const QVariantMap ic = icCheck.toMap();
        const bool ok = ic.value("ok").toBool();
        qDebug().noquote() << "items ok =" << ok
                 << " before =" << ic.value("before").toInt()
                 << " after =" << ic.value("after").toInt();
        if (!ok) {
            qCritical() << "items check FAILED:"
                        << ic.value("error").toString();
            return false;
        }
    }

    // Phase 5b: prove the SkillsTab (SKILLS view) bridge works end-to-end.
    QVariant skCheck = engine.callGlobal("pob_selftestSkills");
    if (skCheck.typeId() != QMetaType::QVariantMap) {
        qCritical() << "pob_selftestSkills missing or wrong type:" << skCheck.typeName();
        return false;
    }
    {
        const QVariantMap sk = skCheck.toMap();
        const bool ok = sk.value("ok").toBool();
        qDebug().noquote() << "skills ok =" << ok
                 << " before =" << sk.value("before").toInt()
                 << " after =" << sk.value("after").toInt()
                 << " id =" << sk.value("id").toInt()
                 << " gemOk =" << sk.value("gemOk").toBool();
        if (!ok) {
            qCritical() << "skills check FAILED:"
                        << sk.value("error").toString();
            return false;
        }
    }

    // Phase 5c: prove the CalcsTab (CALCS view) bridge works end-to-end.
    QVariant ccCheck = engine.callGlobal("pob_selftestCalcs");
    if (ccCheck.typeId() != QMetaType::QVariantMap) {
        qCritical() << "pob_selftestCalcs missing or wrong type:" << ccCheck.typeName();
        return false;
    }
    {
        const QVariantMap cc = ccCheck.toMap();
        const bool ok = cc.value("ok").toBool();
        qDebug().noquote() << "calcs ok =" << ok
                 << " sections =" << cc.value("sections").toInt()
                 << " statCount =" << cc.value("statCount").toInt();
        if (!ok) {
            qCritical() << "calcs check FAILED:"
                        << cc.value("error").toString();
            return false;
        }
    }

    // Phase 5d: config (ConfigTab) check.
    QVariant cfgCheck = engine.callGlobal("pob_selftestConfig");
    if (cfgCheck.typeId() != QMetaType::QVariantMap) {
        qCritical() << "pob_selftestConfig missing or wrong type:" << cfgCheck.typeName();
        return false;
    }
    {
        const QVariantMap cfg = cfgCheck.toMap();
        const bool ok = cfg.value("ok").toBool();
        qDebug().noquote() << "config ok =" << ok
                 << " count =" << cfg.value("count").toInt()
                 << " toggled =" << cfg.value("toggled").toString();
        if (!ok) {
            qCritical() << "config check FAILED:"
                        << cfg.value("error").toString();
            return false;
        }
    }

    // Phase 5e: Notes/Import/Compare/Party (utility) tabs check.
    QVariant mtCheck = engine.callGlobal("pob_selftestMiscTabs");
    if (mtCheck.typeId() != QMetaType::QVariantMap) {
        qCritical() << "pob_selftestMiscTabs missing or wrong type:" << mtCheck.typeName();
        return false;
    }
    {
        const QVariantMap mt = mtCheck.toMap();
        const bool ok = mt.value("ok").toBool();
        qDebug().noquote() << "misc-tabs ok =" << ok
                 << " notesOk =" << mt.value("notesOk").toBool()
                 << " importOk =" << mt.value("importOk").toBool()
                 << " compareOk =" << mt.value("compareOk").toBool()
                 << " compareCount =" << mt.value("compareCount").toInt()
                 << " partyOk =" << mt.value("partyOk").toBool()
                 << " partyCount =" << mt.value("partyCount").toInt();
        if (!ok) {
            qCritical() << "misc-tabs check FAILED:"
                        << mt.value("error").toString();
            return false;
        }
    }

    qDebug() << "SELFTEST PASSED";
    return true;
}
