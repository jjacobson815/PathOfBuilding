#pragma once
#include <QObject>
#include <QString>
#include <QVariant>
#include <QVariantMap>
#include <QStringList>
#include <QElapsedTimer>
#include <lua.hpp>

// Embeds a LuaJIT state and bridges the Path of Building calc engine to Qt.
//
// The engine expects a set of "SimpleGraphic" engine globals (ConPrintf,
// SetMainObject, LoadModule, DrawImage, ...). Those are provided by a small
// Lua bootstrap (lua/pob_host.lua) which routes the few that matter through
// the C `pob` bridge table registered here. This reuses the exact seam the
// project's own src/HeadlessWrapper.lua already uses for headless runs.
class TextMetrics;

class LuaEngine : public QObject {
    Q_OBJECT
public:
    explicit LuaEngine(QObject* parent = nullptr);
    ~LuaEngine();

    // srcDir: repo/src, runtimeDir: repo/runtime, hostFile: lua/pob_host.lua.
    // launchArgs: CLI args exposed to the engine as the Lua `arg` table
    // (arg[0]=program, arg[1..]=params; the engine reads arg[1] as an
    // open-on-launch build file / import URL — fully realized in Phase 11).
    bool init(const QString& srcDir, const QString& runtimeDir, const QString& hostFile,
              const QStringList& launchArgs = {});
    lua_State* state() const { return m_L; }

    // Read a global Lua value (by name) as a QVariant.
    QVariant getGlobal(const QString& name) const;
    // Read a dotted path, e.g. "main.modes.BUILD.viewList".
    QVariant getPath(const QString& path) const;
    // Call a global Lua function, returning its (first) result.
    QVariant callGlobal(const QString& name, const QVariantList& args = {});
    // Call a method on a Lua object reached via a dotted path.
    QVariant callMethod(const QString& objectPath, const QString& method,
                        const QVariantList& args = {});

    // Convenience accessors for the QML shell.
    Q_INVOKABLE QStringList modeNames() const;
    Q_INVOKABLE QVariant viewList() const { return getPath("main.modes.BUILD.viewList"); }

    // Phase 1c: active BUILD-view control (sidebar). The engine tracks the
    // active view in buildMode.viewMode (a string id such as "TREE"/"ITEMS");
    // there is no SetActiveTab method — the engine simply assigns
    // `self.viewMode = viewId` (see src/Modules/Build.lua). We bridge that by
    // writing main.modes.BUILD.viewMode and reading it back.
    Q_INVOKABLE void setActiveView(const QString& viewId);
    Q_INVOKABLE QString currentView() const;
    Q_PROPERTY(QString currentView READ currentView NOTIFY currentViewChanged)

    // Drive an engine callback (OnInit/OnFrame/...) via the Lua runCallback global.
    Q_INVOKABLE QVariant runCallback(const QString& name, const QVariantList& args = {});
    // Switch the active engine mode (drives main:SetMode; next OnFrame inits it).
    Q_INVOKABLE void setMode(const QString& mode);
    // Current mode name string (main.mode).
    Q_INVOKABLE QString currentMode() const;
    Q_PROPERTY(QString currentMode READ currentMode NOTIFY currentModeChanged)

    // Phase 2a: convenience setter used to demonstrate that changing engine
    // state propagates to the typed models' NOTIFY signals. Writes
    // main.modes.BUILD.buildName (no-op if the build mode is unavailable).
    Q_INVOKABLE void setBuildName(const QString& name);

    // Phase 2b: build save/load bridge. These delegate to the top-level Lua
    // globals defined in app/lua/pob_host.lua (pob_saveBuild / pob_loadBuildXML
    // / pob_getBuildXML), which wrap the engine's Build:SaveDB / Build:LoadDB
    // seam so the exact same xml.lua serialiser the real app uses is exercised.
    // saveBuild writes the current build to `path` (returns false on failure).
    // loadBuildXML re-initialises the build from an XML string (returns false
    // if the engine/build mode is unavailable). getBuildXML returns the current
    // build serialised to an XML string (empty string if unavailable).
    Q_INVOKABLE bool saveBuild(const QString& path);
    Q_INVOKABLE bool loadBuildXML(const QString& xml);
    Q_INVOKABLE QString getBuildXML();

    // Phase 3: LIST-mode (build library) operations. Each delegates to a
    // top-level Lua global in app/lua/pob_host.lua (pob_openBuild /
    // pob_createBuild / pob_deleteBuild / pob_renameBuild / pob_importBuildFromURL
    // / pob_createFolder / pob_deleteFolder) which wrap the engine's BuildList /
    // Build seams. openBuild(fullFileName) loads a build .xml into BUILD mode
    // (switching the engine to BUILD). setListMode() switches the engine to LIST
    // mode (calls setMode("LIST")). All return false on failure.
    Q_INVOKABLE bool openBuild(const QString& fullFileName);
    Q_INVOKABLE bool createBuild();
    Q_INVOKABLE bool deleteBuild(const QString& fullFileName);
    Q_INVOKABLE bool renameBuild(const QString& fullFileName, const QString& newName);
    Q_INVOKABLE bool importBuildFromURL(const QString& url);
    Q_INVOKABLE bool createFolder(const QString& name);
    Q_INVOKABLE bool deleteFolder(const QString& name);
    Q_INVOKABLE void setListMode();

    // Phase 4a: passive-tree data bridge. Delegates to the top-level Lua global
    // pob_getTreeData (callGlobal does a single lua_getglobal, so the helper MUST
    // be a top-level global, not a dotted name). Returns the tree data table
    // (nodes/groups/connectors/bounds/assets/assetBasePath) or an invalid
    // QVariant when no build/tree is loaded.
    Q_INVOKABLE QVariant getTreeData();

    // Phase 4b: passive-tree interaction bridge. Each delegates to a top-level Lua
    // global in app/lua/pob_host.lua (callGlobal does a single lua_getglobal, so
    // the helpers MUST be top-level globals, not dotted names). They wrap
    // spec:AllocNode / spec:DeallocNode / spec:CountAllocNodes and the node
    // tooltip / search seams. allocNode/deallocNode/toggleNode return a result
    // table (QVariantMap) or an invalid QVariant when the spec/node is missing;
    // getNodeTooltip returns { name, type, alloc, sd } or invalid; setTreeSearch /
    // getTreeSearchResults return the list of matching node ids.
    Q_INVOKABLE QVariant allocNode(int id);
    Q_INVOKABLE QVariant deallocNode(int id);
    Q_INVOKABLE QVariant toggleNode(int id);
    Q_INVOKABLE QVariant getNodeTooltip(int id);
    Q_INVOKABLE QVariantList setTreeSearch(const QString& str);
    Q_INVOKABLE QVariantList getTreeSearchResults();

    // Phase 5a: ItemsTab (ITEMS view) bridge. Each delegates to a top-level
    // Lua global in app/lua/pob_host.lua (callGlobal does a single
    // lua_getglobal, so the helpers MUST be top-level globals, not dotted
    // names). They wrap the engine's ItemsTab (main.modes.BUILD.itemsTab)
    // so the QML ITEMS view can browse items, equipped slots and tree jewel
    // sockets, and add/delete items from raw text. getItems/getItemSlots/
    // getJewelSockets return QVariantList of maps (or an empty list when the
    // items tab is unavailable); addItemFromRaw returns the new item id (or -1
    // on failure); deleteItem returns false on failure.
    Q_INVOKABLE QVariantList getItems();
    Q_INVOKABLE QVariantList getItemSlots();
    Q_INVOKABLE QVariantList getJewelSockets();
    Q_INVOKABLE int addItemFromRaw(const QString& raw);
    Q_INVOKABLE bool deleteItem(int id);

    // Phase 5b: SkillsTab (SKILLS view) bridge. Each delegates to a top-level
    // Lua global in app/lua/pob_host.lua (callGlobal does a single
    // lua_getglobal, so the helpers MUST be top-level globals, not dotted
    // names). getSocketGroups returns the socket group list (id/label/slot/
    // enabled/gems/mainActiveSkill); getActiveSkills returns the active-skill
    // DPS list (name/dps/totalDps/minionDps/socketGroupLabel/isMain/
    // socketGroupIndex/displaySkillIndex); addSocketGroupWithGem creates a
    // group + gem and returns its id; setActiveSkill selects a display skill
    // as the main skill and recalculates.
    Q_INVOKABLE QVariantList getSocketGroups();
    Q_INVOKABLE QVariantList getActiveSkills();
    Q_INVOKABLE int addSocketGroupWithGem(const QString& label, const QString& gemName);
    Q_INVOKABLE void setActiveSkill(int socketGroupId, int index);

    // Part 2.2: single recalc-orchestration entry point. Delegates to the
    // top-level Lua global pob_recalculate, which runs the legacy dirty-flag
    // sequence (wipeGlobalCache -> outputRevision++ -> BuildOutput ->
    // RefreshStatList) only when build.buildFlag is set -- a no-op otherwise.
    // Returns { ok, recalculated, outputRevision } (error instead of
    // recalculated/outputRevision on failure). Emits calcsChanged() only when
    // a recalc actually happened. outputRevision() is a cheap read of the
    // same counter (pob_getOutputRevision) without forcing a recalc -- the
    // legacy tooltip:CheckForUpdate(obj, outputRevision) cache-invalidation
    // key, for callers (e.g. tooltip memoization) that just need to know if
    // anything changed.
    Q_INVOKABLE QVariant recalculate();
    Q_INVOKABLE qint64 outputRevision();

    // Phase 5c: CalcsTab (CALCS view) bridge. Each delegates to a top-level
    // Lua global in app/lua/pob_host.lua (callGlobal does a single
    // lua_getglobal, so the helpers MUST be top-level globals, not dotted
    // names). getCalcOutput returns the full calc output table (summary +
    // sections, plus an outputRevision field mirroring the counter above) or
    // an invalid QVariant when the calcs tab is unavailable; getCalcBreakdown
    // returns the breakdown lines (QVariantList of strings) for the given
    // stat's breakdown key, or an empty list when none exists.
    Q_INVOKABLE QVariant getCalcOutput();
    Q_INVOKABLE QVariantList getCalcBreakdown(const QString& section, const QString& stat);

    // Part 2.3: sidebar output bridge. Delegates to the top-level Lua global
    // pob_getOutput, which serializes env.player.output (+ env.minion.output)
    // against the build.displayStats/minionDisplayStats schema (the same
    // schema legacy uses for both the sidebar AND node/item compare tooltips),
    // reusing buildMode:FormatStat verbatim so values are byte-for-byte legacy.
    // Returns { player = {stats, skillDPS}, minion?, warnings, outputRevision,
    // disableReason? } or an invalid QVariant when no build is loaded.
    Q_INVOKABLE QVariant getOutput();

    // Part 2.4: comparison-calculator bridge. compareOverride delegates to
    // pob_compareOverride (the whole "hovering this gives you:" surface: node
    // add/remove by id, item slot replacement by raw text, flask/tincture
    // toggle by item id) and compareNodes to pob_compareNodes (the fast
    // add-only path used by the tree heat map). Both reuse calcsTab's
    // persistent miscCalculator/nodeCalculator closures (kept fresh by every
    // recalculate()) rather than rebuilding a calculator per call. Return
    // { ok, stats, minionStats?, outputRevision } (error instead of stats on
    // failure) or an invalid QVariant when no build is loaded.
    Q_INVOKABLE QVariant compareOverride(const QVariantMap& override);
    Q_INVOKABLE QVariant compareNodes(const QVariantList& nodeIds);

    // Part 2.5: Config usage-set export. Delegates to pob_getConfigUsageSets,
    // which reduces env.conditionsUsed/enemyConditionsUsed/minionConditionsUsed/
    // multipliersUsed/enemyMultipliersUsed/perStatsUsed/enemyPerStatsUsed/
    // tagTypesUsed/modsUsed (varName -> array-of-mod-refs, not serializable) to
    // plain varName->true boolean sets, alongside skillsUsed/keystonesAdded
    // (already boolean sets). Drives Config option visibility (Phase 7).
    Q_INVOKABLE QVariant getConfigUsageSets();

    // ---- Phase 3: Build Shell -------------------------------------------
    //
    // These exist because the Qt host has NO FRAME LOOP. Everything
    // buildMode:OnFrame recomputed every frame (Build.lua:1162) is dead code
    // here, so each of those responsibilities becomes an explicit call:
    //
    //   getUnsaved()   replaces reading main.modes.BUILD.unsaved, which is
    //                  written only inside OnFrame (Build.lua:1254) and is
    //                  therefore permanently stale under Qt.
    //   getShellState() is the whole top-bar payload in ONE call. Do not bind
    //                  it to a QML property expression: it runs
    //                  EstimatePlayerProgress, which mutates characterLevel in
    //                  auto mode and appends point-overflow warnings.
    //   saveDBFile()   is the recalc-gated save. buildMode:Save denormalizes
    //                  <PlayerStat>/<FullDPSSkill> out of calcsTab.mainOutput,
    //                  so saving before a completed calc pass silently ships a
    //                  build with stale or missing stats. Returns a structured
    //                  {ok=false, error=...}, never a bare null.
    Q_INVOKABLE QVariant getUnsaved();
    Q_INVOKABLE QVariant getShellState();
    Q_INVOKABLE QVariant getClassList();
    // mode: "check" (apply only if free, else report needsConfirm and change
    // nothing) | "force" (accept the tree reset) | "connect" (try ConnectToClass).
    Q_INVOKABLE QVariant setClass(int classId, const QString& mode);
    Q_INVOKABLE QVariant setAscendClass(int ascendClassId);
    Q_INVOKABLE QVariant setSecondaryAscendClass(int ascendClassId);
    Q_INVOKABLE QVariant setCharacterLevel(int level);
    Q_INVOKABLE QVariant setLevelAutoMode(bool autoMode);
    Q_INVOKABLE QVariant setSideBarCollapsed(bool collapsed);
    Q_INVOKABLE QVariant saveDBFile(const QString& path = QString());
    Q_INVOKABLE QVariant closeBuild();
    Q_INVOKABLE QVariant sanitizeBuildName(const QString& name, const QString& subPath);

    // Part 3.2: the main-skill selector stack (a data port of
    // buildMode:RefreshSkillSelectControls, Build.lua:1511).
    //
    // `suffix` selects WHICH of the two independent main-skill selections you
    // are reading or writing: "" is the side bar's, "Calcs" is the Calcs tab's.
    // Legacy keeps them separate on purpose — the Calcs tab lets you inspect a
    // different skill than the side bar displays — so never collapse them.
    //
    // getMainSkillControls() forces a recalc: displayLabel/displaySkillList are
    // engine write-backs that only exist after a calc pass. It deliberately
    // does NOT go through getActiveSkills(), which costs 61-470ms because it
    // runs one full BuildOutput per displayed skill.
    Q_INVOKABLE QVariant getMainSkillControls(const QString& suffix = QString());
    Q_INVOKABLE QVariant setMainSocketGroup(int index);
    Q_INVOKABLE QVariant setMainActiveSkill(int index, const QString& suffix = QString());
    Q_INVOKABLE QVariant setMainSkillPart(int index, const QString& suffix = QString());
    Q_INVOKABLE QVariant setSkillStageCount(int count, const QString& suffix = QString());
    Q_INVOKABLE QVariant setSkillMineCount(int count, const QString& suffix = QString());
    // value: { "minionId": "Metadata/..." } or { "itemSetId": 2 }.
    Q_INVOKABLE QVariant setSkillMinion(const QVariantMap& value, const QString& suffix = QString());
    Q_INVOKABLE QVariant setSkillMinionSkill(int index, const QString& suffix = QString());
    Q_INVOKABLE QStringList getSocketGroupTooltip(int index);
    Q_INVOKABLE QVariant getConversionState();
    Q_INVOKABLE QVariant convertBuild();

    // full list of config option descriptors (QVariantList of QVariantMap with
    // name/label/type/value/options/section/tooltip); setConfigOption writes a
    // value back into the active config set and triggers a rebuild.
    Q_INVOKABLE QVariantList getConfigOptions();
    Q_INVOKABLE QVariant setConfigOption(const QString& name, const QVariant& value);

    // Part 1.4: Options dialog bridge (main:OpenOptionsPopup). getOptions returns
    // the full ~28-setting descriptor list (each a QVariantMap: key/label/type/
    // value/section/tooltip/options/min/max/step/maxChars/commit). previewOption
    // LIVE-applies a field onto self.* (the fields legacy mutates as the control
    // changes; Cancel reverts by replaying the pre-open snapshot through this same
    // method). commitOptions applies the Save-button-only fields
    // (connectionProtocol/proxy/buildPath) and persists Settings.xml. Delegates to
    // the top-level Lua globals pob_getOptions / pob_previewOption /
    // pob_commitOptions (callGlobal resolves only top-level globals). Each mutation
    // emits configChanged so any live-bound QML (e.g. a node-power swatch) refreshes.
    Q_INVOKABLE QVariantList getOptions();
    Q_INVOKABLE QVariant previewOption(const QString& key, const QVariant& value);
    Q_INVOKABLE bool commitOptions(const QVariantMap& values);

    // Part 1.4 (bullet 5): Toast notification bridge. getToasts() returns the
    // current [{id, message}, ...] mirror list (delegates to the top-level Lua
    // global pob_getToasts); dismissToast(id) delegates to pob_dismissToast.
    // The mirror is kept current by a pob_host.lua host seam that wraps
    // ToastNotification's Add/Update/Remove/Clear and calls pob.toastsChanged()
    // on every mutation, which this class turns into the toastsChanged() Qt
    // signal (see l_pob_toastsChanged) -- QML listens and re-fetches via
    // getToasts(), the same push-then-pull pattern as cloudErrorRequested.
    Q_INVOKABLE QVariantList getToasts();
    Q_INVOKABLE void dismissToast(const QString& id);

    // Part 1.4 (bullet 6): About popup content bridge (main:OpenAboutPopup).
    // Delegates to the top-level Lua global pob_getAboutContent, which parses
    // changelog.txt/help.txt into TextListControl-shaped row lists. Returns
    // { changeList, changeVersionHeights, helpList, helpSectionHeights,
    //   helpSections, versionNumber, versionBranch, devMode }.
    Q_INVOKABLE QVariant getAboutContent();
    // About popup's GitHub link. Delegates to the top-level Lua global OpenURL
    // (pob_host.lua), which routes through the existing pob.openURL bridge.
    Q_INVOKABLE void openURL(const QString& url);

    // Phase 5e: Notes/Import/Compare/Party (utility) tabs bridge. Delegates to
    // the top-level Lua globals pob_getNotes / pob_setNotes /
    // pob_importFromCode / pob_getCompareEntries / pob_getPartyMembers
    // (callGlobal does a single lua_getglobal, so the helpers MUST be
    // top-level globals, not dotted names). getNotes/setNotes mirror the
    // NotesTab edit buffer; importFromCode decodes a build share code; the two
    // getters return QVariantList of QVariantMap rows for the QML list models.
    Q_INVOKABLE QString getNotes();
    Q_INVOKABLE void setNotes(const QString& text);
    Q_INVOKABLE bool importFromCode(const QString& code);
    Q_INVOKABLE QVariantList getCompareEntries();
    Q_INVOKABLE QVariantList getPartyMembers();

    // Phase 6b: headless self-test entry point. Runs the full headless check
    // suite (see selftest_checks.h / pob_run_all_selftests) against the live,
    // already-initialised engine. Returns true if every check passed. Used by
    // the `pob-qt --headless` mode so the GUI binary itself can act as a CI
    // smoke test without creating a window or requiring a display.
    bool runSelfTest();

signals:
    void logMessage(const QString& msg);
    void engineReady();
    // Emitted when the engine calls SetForeground() (raise/activate window).
    // Wired to the QQuickWindow in main.cpp; a no-op in headless hosts.
    void foregroundRequested();
    // Event-driven update signals. Emitted ONLY after a genuine mutation (a
    // user action or a background recalc routed through a bridge method),
    // never from a polling timer. The typed models subscribe to these so they
    // refresh exactly once per real state change instead of every frame.
    void buildDataChanged();   // build name/level/class/socket groups
    void treeChanged();        // passive tree allocation / search
    void configChanged();      // config options
    void itemsChanged();       // items / equipped slots / jewel sockets
    void skillsChanged();      // active skills / socket groups
    void calcsChanged();       // calculation output
    void notesChanged();       // notes text
    void compareChanged();     // compare entries
    void partyChanged();       // party members
    void buildListChanged();   // LIST-mode build library
    void modeChanged();        // mode switch / new build loaded (refresh all)
    void viewChanged();        // active view (sidebar) changed
    // Part 1.4: cloud/path error dialogs. Emitted when the engine's
    // OpenCloudErrorPopup / OpenPathPopup fire (via the pob.cloudErrorPopup /
    // pob.pathErrorPopup bridge). main.qml listens and opens a real MessagePopup
    // (the SimpleGraphic control trees those functions built are inert in QML).
    void cloudErrorRequested(const QString& path, const QString& provider, const QString& status);
    void pathErrorRequested(const QString& invalidPath, const QString& errMsg);
    // Part 1.4 (bullet 5): emitted when the Lua-side toast mirror changes (via
    // pob.toastsChanged(), called from the pob_host.lua ToastNotification wrap).
    // Carries no payload -- QML re-fetches the full list via getToasts().
    void toastsChanged();
    void currentViewChanged(); // active BUILD view id changed (sidebar nav)
    void currentModeChanged(); // active mode (BUILD/LIST) changed

private:
    // Write a dotted Lua path (e.g. "main.modes.BUILD.viewMode") to `value`.
    void setPath(const QString& path, const QVariant& value);

    // C callbacks exposed to Lua via the `pob` table.
    static int l_pob_log(lua_State* L);
    static int l_pob_setMainObject(lua_State* L);
    static int l_pob_getScriptPath(lua_State* L);
    static int l_pob_getRuntimePath(lua_State* L);
    static int l_pob_getUserPath(lua_State* L);
    static int l_pob_getTime(lua_State* L);
    static int l_pob_copy(lua_State* L);
    static int l_pob_paste(lua_State* L);
    static int l_pob_openURL(lua_State* L);
    static int l_pob_makeDir(lua_State* L);
    static int l_pob_removeDir(lua_State* L);
    static int l_pob_isKeyDown(lua_State* L);
    static int l_pob_setForeground(lua_State* L);
    static int l_pob_inflate(lua_State* L);
    static int l_pob_deflate(lua_State* L);
    static int l_pob_http(lua_State* L);
    // Phase 3: directory listing backing the SimpleGraphic NewFileSearch stub
    // (used by BuildListHelpers.ScanFolder). Returns an array of
    // { name = string, modified = number } entries for `path` (a directory,
    // optionally with a trailing wildcard pattern). `dirsOnly` lists folders.
    static int l_pob_listDir(lua_State* L);
    // Phase 1.2a: real text metrics (replace the DrawStringWidth/CursorIndex stubs
    // in pob_host.lua). Backed by the .tgf-driven TextMetrics engine.
    static int l_pob_stringWidth(lua_State* L);
    static int l_pob_stringCursorIndex(lua_State* L);
    // Part 1.4: Win32 file-attribute probe (OneDrive dehydration detection)
    // backing the real GetCloudProvider Lua global. Returns a table
    // { exists, offline, recallOnDataAccess, recallOnOpen, reparsePoint }.
    static int l_pob_fileAttributes(lua_State* L);
    // Part 1.4: bridge the engine's OpenCloudErrorPopup / OpenPathPopup to real
    // QML dialogs by emitting cloudErrorRequested / pathErrorRequested.
    static int l_pob_cloudErrorPopup(lua_State* L);
    static int l_pob_pathErrorPopup(lua_State* L);
    // Part 1.4 (bullet 5): pob.toastsChanged() -- called from the pob_host.lua
    // ToastNotification wrap after every Add/Update/Remove/Clear; emits
    // toastsChanged() so QML re-fetches via getToasts().
    static int l_pob_toastsChanged(lua_State* L);
    // Phase 4: pob.imageSize(path) -> width, height (0, 0 when unreadable).
    // Backs the real NewImageHandle():ImageSize() in pob_host.lua, which was
    // stubbed to 1, 1 -- a value four sites in src/ divide or multiply by
    // (PassiveTree.lua:368 sprite-sheet UV divisors, :871 tree.assets dims,
    // :956 the orbit-arc radius, PassiveTreeView.lua:524/:1233). Reads only the
    // image header via QImageReader::size() -- never decodes the pixels, which
    // matters because the sheets are up to 4k x 4k -- and memoises per path.
    static int l_pob_imageSize(lua_State* L);
    static LuaEngine* selfOf(lua_State* L);

    lua_State* m_L = nullptr;
    QString m_srcDir;
    QString m_runtimeDir;
    QString m_userDir;
    QStringList m_launchArgs;   // exposed to Lua as the `arg` table
    QElapsedTimer m_clock;      // monotonic clock backing GetTime (ms since init)
    TextMetrics* m_textMetrics = nullptr;  // .tgf-backed string measurement (Phase 1.2a)

public:
    // Shared TextMetrics instance (created in init() from the runtime Fonts dir).
    // main.cpp exposes this same object to QML as the `textMetrics` context
    // property so QML and the Lua engine measure identically.
    TextMetrics* textMetrics() const { return m_textMetrics; }
};
