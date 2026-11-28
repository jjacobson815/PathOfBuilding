import QtQuick
import QtTest
import "qrc:/qml/views" as Views
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Views.ImportView {
        id: view
        anchors.fill: parent
    }

    TestCase {
        id: tc
        name: "ImportViewTest"
        when: windowShown

        function init() {
            uiTest.restoreLuaMocks()
            uiTest.resetWarnings()
            luaEngine.createBuild()
            luaEngine.setActiveView("IMPORT")
            view.refresh()
            mouseMove(container, 1, 1)
            wait(20)
        }

        function cleanup() {
            uiTest.restoreLuaMocks()
            uiTest.resetEngineForTest()
        }

        function installCharacterFetchMocks() {
            var setupLua = [
                "local allChars = {",
                "  { index = 1, name = 'ColdVortexOcc', level = 98, class = 'Occultist', league = 'Settlers', label = 'Lv98 Occultist - ColdVortexOcc' },",
                "  { index = 2, name = 'HexblastTrick', level = 94, class = 'Trickster', league = 'Settlers', label = 'Lv94 Trickster - HexblastTrick' },",
                "  { index = 3, name = 'LaDeadeye', level = 90, class = 'Deadeye', league = 'Settlers', label = 'Lv90 Deadeye - LaDeadeye' },",
                "  { index = 4, name = 'CycloneSlayer', level = 100, class = 'Slayer', league = 'Standard', label = 'Lv100 Slayer - CycloneSlayer' },",
                "  { index = 5, name = 'SrsNecro', level = 96, class = 'Necromancer', league = 'Standard', label = 'Lv96 Necromancer - SrsNecro' },",
                "  { index = 6, name = 'BoneshatterJugg', level = 92, class = 'Juggernaut', league = 'Standard', label = 'Lv92 Juggernaut - BoneshatterJugg' }",
                "}",
                "_G.__mockImport = {",
                "  authMethod = 'account',",
                "  realmId = 'pc',",
                "  accountName = 'TestExile#1234',",
                "  leagues = { 'All', 'Settlers', 'Standard' },",
                "  selectedLeague = 'All',",
                "  allChars = allChars,",
                "  characters = allChars,",
                "  selectedCharIndex = 0,",
                "  targetMode = 'overwrite',",
                "  rateLimitSecondsLeft = 0,",
                "  oauthWaiting = false,",
                "  statusText = '',",
                "  confirmCount = 0",
                "}",
                "_G.__mockImportSnapshot = function()",
                "  local m = _G.__mockImport",
                "  return {",
                "    ok = true,",
                "    authMethod = m.authMethod,",
                "    oauthAuthorized = false,",
                "    oauthWaiting = m.oauthWaiting,",
                "    oauthSecondsLeft = 0,",
                "    rateLimitSecondsLeft = m.rateLimitSecondsLeft,",
                "    realmId = m.realmId,",
                "    realms = {",
                "      { id = 'pc', label = 'PC' },",
                "      { id = 'xbox', label = 'Xbox' }",
                "    },",
                "    accountName = m.accountName,",
                "    accountHistory = { m.accountName },",
                "    accountNameValid = true,",
                "    accountNameHint = '',",
                "    sessionId = '',",
                "    leagues = m.leagues,",
                "    selectedLeague = m.selectedLeague,",
                "    characters = m.characters,",
                "    selectedCharIndex = m.selectedCharIndex,",
                "    importTree = true,",
                "    importItems = true,",
                "    targetMode = m.targetMode,",
                "    currentBuildName = 'Mocked Build',",
                "    options = {},",
                "    busy = false,",
                "    busyStep = '',",
                "    statusText = m.statusText,",
                "    errorText = '',",
                "    canFetchCharacters = true,",
                "    fetchDisabledReason = '',",
                "    canImportCharacter = (m.selectedCharIndex >= 1 and m.selectedCharIndex <= #m.characters),",
                "    importDisabledReason = '',",
                "    importButtonLabel = m.targetMode == 'overwrite' and 'Overwrite & Import' or 'Import as New Build',",
                "    share = { code = '', sites = { { id = 'pobbin', label = 'pobb.in' } }, selectedSiteId = 'pobbin', canCopy = false, canUpload = false },",
                "    open = { input = '', valid = false, mode = 'new', canImport = false }",
                "  }",
                "end",
                "return _G.__mockImportSnapshot()"
            ].join("\n")

            verify(uiTest.mockLuaGlobal("pob_mockInitImport", setupLua))
            verify(luaEngine.invoke("pob_mockInitImport", []).ok)
            verify(uiTest.mockLuaGlobal("pob_mockSetRate", "local sec = ...; _G.__mockImport.rateLimitSecondsLeft = sec; return true"))
            verify(uiTest.mockLuaGlobal("pob_importGetState", "function() return _G.__mockImportSnapshot() end"))
            verify(uiTest.mockLuaGlobal("pob_importSetRealm", "function(id) _G.__mockImport.realmId = id; return _G.__mockImportSnapshot() end"))
            verify(uiTest.mockLuaGlobal("pob_importSetAuthMethod", "function(meth) _G.__mockImport.authMethod = meth; return _G.__mockImportSnapshot() end"))
            verify(uiTest.mockLuaGlobal("pob_importSetLeague", [
                "local lg = ...",
                "local m = _G.__mockImport",
                "m.selectedLeague = lg",
                "if lg == 'All' then",
                "  m.characters = m.allChars",
                "else",
                "  local filtered = {}",
                "  for _, c in ipairs(m.allChars) do",
                "    if c.league == lg then table.insert(filtered, c) end",
                "  end",
                "  m.characters = filtered",
                "end",
                "m.selectedCharIndex = 0",
                "return _G.__mockImportSnapshot()"
            ].join("\n")))
            verify(uiTest.mockLuaGlobal("pob_importSetCharacter", "function(idx) _G.__mockImport.selectedCharIndex = idx; return _G.__mockImportSnapshot() end"))
            verify(uiTest.mockLuaGlobal("pob_importFetchCharacters", "function() _G.__mockImport.statusText = 'Fetched 6 characters'; return _G.__mockImportSnapshot() end"))
            verify(uiTest.mockLuaGlobal("pob_importExecuteCharacter", [
                "local confirmed = ...",
                "local m = _G.__mockImport",
                "if not confirmed then",
                "  return { ok = true, needsConfirm = true, confirmTitle = 'Overwrite Current Build?', confirmMessage = 'Overwrite mocked build?' }",
                "end",
                "m.confirmCount = m.confirmCount + 1",
                "m.statusText = 'Character imported!'",
                "return _G.__mockImportSnapshot()"
            ].join("\n")))
        }

        function pickDropdownRow(drop, idx) {
            mouseClick(drop)
            tryCompare(drop, "open", true)
            var list = Oracle.findRequired(tc, uiTest, drop, "pob.dropdown.list")
            tryVerify(function() { return list.itemAtIndex(idx) !== null })
            var rowItem = list.itemAtIndex(idx)
            mouseClick(rowItem)
            tryCompare(drop, "open", false)
        }

        function test_all_ac() {
            var realmDrop = Oracle.findRequired(tc, uiTest, view, "pob.import.realm_drop")
            var authOAuth = Oracle.findRequired(tc, uiTest, view, "pob.import.auth_oauth")
            var leagueDrop = Oracle.findRequired(tc, uiTest, view, "pob.import.league_drop")
            var charDrop = Oracle.findRequired(tc, uiTest, view, "pob.import.char_drop")
            var btnImport = Oracle.findRequired(tc, uiTest, view, "pob.import.btn_import")
            var shareBtn = Oracle.findRequired(tc, uiTest, view, "pob.import.share_btn")
            var openBtn = Oracle.findRequired(tc, uiTest, view, "pob.import.open_btn")
            var openEdit = Oracle.findRequired(tc, uiTest, view, "pob.import.open_edit")
            var confirmPopup = Oracle.findRequired(tc, uiTest, view, "pob.import.confirm_popup")
            var countdownTimer = Oracle.findRequired(tc, uiTest, view, "pob.import.countdown_timer")

            // AC-01: Mount & state initialization
            Oracle.step(tc, "AC-01: verify initial ImportView mount and disabled actions")
            verify(realmDrop.width > 0)
            verify(charDrop.width > 0)
            compare(btnImport.controlEnabled, false)
            compare(openBtn.controlEnabled, false)
            compare(countdownTimer.running, false)

            mouseClick(authOAuth)
            wait(10)
            mouseClick(shareBtn)
            wait(20)
            verify(view._share.code && view._share.code.length > 0)

            // Mocked 6-character / 2-league PoE account fetch
            Oracle.step(tc, "Install mocked 6-character / 2-league PoE fetch state")
            installCharacterFetchMocks()
            view.refresh()
            tryCompare(charDrop, "controlEnabled", true)
            compare(realmDrop.controlEnabled, true)
            compare(realmDrop.count, 2)
            compare(leagueDrop.controlEnabled, true)
            compare(leagueDrop.count, 3) // All + Settlers + Standard
            compare(charDrop.count, 6)

            // Interactive Realm dropdown click-through
            Oracle.step(tc, "Select Xbox realm from dropdown")
            pickDropdownRow(realmDrop, 1)
            tryCompare(realmDrop, "currentIndex", 1)

            // Interactive League dropdown click-through (filter 6 -> 3 chars in Settlers)
            Oracle.step(tc, "Select Settlers league from dropdown")
            pickDropdownRow(leagueDrop, 1)
            tryCompare(charDrop, "count", 3)

            // Interactive Character dropdown click-through -> enables Import button
            Oracle.step(tc, "Select character from dropdown")
            pickDropdownRow(charDrop, 0)
            tryCompare(btnImport, "controlEnabled", true)

            // AC-02: Overwrite ConfirmPopup flow
            Oracle.step(tc, "AC-02: click Import and confirm overwrite popup")
            mouseClick(btnImport)
            tryCompare(confirmPopup, "visible", true)
            var confirmBtn = Oracle.findRequired(tc, uiTest, confirmPopup.contentItem, "pob.confirm.btn_confirm")
            mouseClick(confirmBtn)
            tryCompare(confirmPopup, "visible", false)
            compare(view.st.statusText, "Character imported!")

            // AC-03: Rate-limit Timer active when rateLimitSecondsLeft > 0
            Oracle.step(tc, "AC-03: activate rate-limit countdown timer")
            verify(luaEngine.invoke("pob_mockSetRate", [12]))
            view.refresh()
            tryCompare(countdownTimer, "running", true)

            verify(luaEngine.invoke("pob_mockSetRate", [0]))
            view.refresh()
            tryCompare(countdownTimer, "running", false)

            // AC-04: Restore real bridge & paste URL into openCodeEdit -> enables Open Build
            Oracle.step(tc, "AC-04: paste URL into openCodeEdit and verify Open Build enables")
            uiTest.restoreLuaMocks()
            view.refresh()
            tryCompare(openBtn, "controlEnabled", false)
            var openInput = Oracle.findRequired(tc, uiTest, openEdit, "pob.edit.input")
            mouseClick(openEdit)
            wait(10)
            openInput.text = "https://pobb.in/test12345"
            openEdit.edited(openInput.text)
            tryCompare(openBtn, "controlEnabled", true)

            Oracle.assertMultiResLayout(tc, container, view, uiTest, "ImportView")
            Oracle.assertZeroWarnings(tc, uiTest, "ImportView")
        }
    }
}
