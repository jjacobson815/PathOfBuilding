import QtQuick
import QtTest
import "../UiTestOracle.js" as Oracle

Item {
    id: harness
    width: 100
    height: 100

    TestCase {
        id: tc
        name: "PlaywrightJourneyTest"
        when: windowShown

        property var win: null

        function init() {
            uiTest.restoreLuaMocks()
            uiTest.resetWarnings()
            uiTest.resetEngineForTest()
            var comp = Qt.createComponent("qrc:/qml/main.qml")
            compare(comp.status, Component.Ready, comp.errorString())
            win = comp.createObject(null, { width: 1100, height: 720, visible: true })
            verify(win !== null)
            win.requestActivate()
            waitForRendering(win.contentItem)
            wait(30)
        }

        function cleanup() {
            if (win) {
                win.visible = false
                win.destroy()
                win = null
                wait(25)
            }
            uiTest.restoreLuaMocks()
            uiTest.resetEngineForTest()
        }

        function readStatPanelSnapshot() {
            var rows = uiTest.findObjectsByPrefix(win.contentItem, "pob.statpanel.row.stat")
            var out = []
            for (var i = 0; i < rows.length; i++) {
                var r = rows[i]
                if (r && r.modelData) {
                    out.push(String(r.modelData.left || "") + "=" + String(r.modelData.right || ""))
                }
            }
            return out.join("|")
        }

        function findInteractiveCalcsCell() {
            var cells = uiTest.findObjectsByPrefix(win.contentItem, "pob.calcsCard.cellMouse")
            for (var i = 0; i < cells.length; i++) {
                var c = cells[i]
                if (!c || !c.visible || !c.enabled || c.width <= 4 || c.height <= 4) continue
                var pt = c.mapToItem(win.contentItem, c.width / 2, c.height / 2)
                if (pt.x >= 200 && pt.x <= win.width - 20 && pt.y >= 60 && pt.y <= win.height - 40) {
                    return c
                }
            }
            return null
        }

        function test_e2e_occvortex_journey() {
            // 1. Load real OccVortex 3.13 build without touching src/Builds/
            Oracle.step(tc, "Load spec/TestBuilds/3.13/OccVortex.xml")
            verify(uiTest.loadTestBuild("../spec/TestBuilds/3.13/OccVortex.xml"),
                   "Failed to load ../spec/TestBuilds/3.13/OccVortex.xml")
            wait(40)

            // Handle ConversionPopup if 3.13 triggers target-version conversion
            var convertBtn = uiTest.findObject(win.contentItem, "pob.conversion.convertBtn")
            if (convertBtn && convertBtn.visible) {
                Oracle.step(tc, "Convert 3.13 tree to live tree version")
                mouseClick(convertBtn)
                tryCompare(convertBtn, "visible", false, 5000)
            }
            compare(luaEngine.currentMode, "BUILD")

            // 2. Drive TopBar/Sidebar tabs via Ctrl+1..8 shortcuts
            Oracle.step(tc, "Cycle all 8 BUILD views via Ctrl+1..8")
            var views = luaEngine.viewList()
            verify(views && views.length >= 8)
            for (var i = 0; i < 8; i++) {
                var v = views[i]
                var keyCode = Qt.Key_1 + i
                uiTest.sendKeyClick(win, keyCode, Qt.ControlModifier)
                tryCompare(luaEngine, "currentView", v.id)
                Oracle.step(tc, "Switched via Ctrl+" + (i + 1) + " -> " + v.id)
            }

            // 3. Tree tab: hover canvas + search via Ctrl+F
            Oracle.step(tc, "Tree: click sidebar tab, hover, and search")
            var treeNav = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.shell.sidebar.btn_nav_TREE")
            mouseClick(treeNav)
            tryCompare(luaEngine, "currentView", "TREE")
            wait(20)
            mouseMove(win.contentItem, win.width * 0.55, win.height * 0.45)
            wait(15)
            uiTest.sendKeyClick(win, Qt.Key_F, Qt.ControlModifier)
            wait(15)
            var searchKeys = [Qt.Key_E, Qt.Key_N, Qt.Key_E, Qt.Key_R, Qt.Key_G, Qt.Key_Y]
            for (var k = 0; k < searchKeys.length; k++) {
                uiTest.sendKeyClick(win, searchKeys[k], Qt.NoModifier)
            }
            tryVerify(function() { return luaEngine.getTreeSearchResults().length > 0 })
            uiTest.sendKeyClick(win, Qt.Key_Escape, Qt.NoModifier)
            wait(15)

            // 4. Skills tab: toggle socket group enabled checkbox
            Oracle.step(tc, "Skills: toggle socket group enabled checkbox")
            var skillsNav = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.shell.sidebar.btn_nav_SKILLS")
            mouseClick(skillsNav)
            tryCompare(luaEngine, "currentView", "SKILLS")
            var groupChk = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.skills.check_group_enabled")
            var wasEnabled = groupChk.state
            mouseClick(groupChk)
            tryVerify(function() { return groupChk.state !== wasEnabled })

            // 5. Items tab: weapon swap + CraftNewPopup open/Esc
            Oracle.step(tc, "Items: toggle weapon swap and open/Esc CraftNewPopup")
            var itemsNav = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.shell.sidebar.btn_nav_ITEMS")
            mouseClick(itemsNav)
            tryCompare(luaEngine, "currentView", "ITEMS")
            var ws1 = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.items.btn_weapon_set_1")
            var ws2 = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.items.btn_weapon_set_2")
            mouseClick(ws2)
            tryCompare(ws2, "locked", true)
            mouseClick(ws1)
            tryCompare(ws1, "locked", true)

            var craftBtn = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.items.btn_craft_item")
            // Scroll ItemsView horizontal Flickable so col3 ("Craft item...") is in viewport
            var fp = craftBtn.parent
            while (fp && fp.contentX === undefined) fp = fp.parent
            if (fp) {
                fp.contentX = Math.max(0, fp.contentWidth - fp.width)
                wait(15)
            }
            mouseClick(craftBtn)
            var craftCreateBtn = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.craftNew.createBtn")
            tryCompare(craftCreateBtn, "visible", true)
            uiTest.sendKeyClick(win, Qt.Key_Escape, Qt.NoModifier)
            tryCompare(craftCreateBtn, "visible", false)

            // 6. Config tab: toggle an option and verify StatPanel updates
            Oracle.step(tc, "Config: toggle config option and verify StatPanel update")
            var configNav = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.shell.sidebar.btn_nav_CONFIG")
            mouseClick(configNav)
            tryCompare(luaEngine, "currentView", "CONFIG")
            wait(25)
            var statBefore = readStatPanelSnapshot()
            verify(statBefore.length > 0, "StatPanel should display OccVortex stats")

            var cfgChecks = uiTest.findObjectsByPrefix(win.contentItem, "pob.configRow.checkCtrl")
            verify(cfgChecks.length > 0, "Expected visible Config checkboxes")
            var statChanged = false
            for (var ci = 0; ci < cfgChecks.length && ci < 20; ci++) {
                var chk = cfgChecks[ci]
                if (!chk || !chk.visible || chk.width <= 0 || chk.height <= 0) continue
                // Only click checkboxes currently inside the visible Flickable viewport
                var pt = chk.mapToItem(win.contentItem, chk.width / 2, chk.height / 2)
                if (pt.y < 80 || pt.y > win.height - 60 || pt.x < 180 || pt.x > win.width - 30) continue
                mouseClick(chk)
                wait(25)
                var statAfter = readStatPanelSnapshot()
                if (statAfter !== statBefore) {
                    statChanged = true
                    break
                }
            }
            verify(statChanged, "Toggling a visible Config option should change StatPanel output")

            // 7. Calcs tab: pin breakdown panel then dismiss with Esc
            Oracle.step(tc, "Calcs: pin breakdown and dismiss with Esc")
            var calcsNav = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.shell.sidebar.btn_nav_CALCS")
            mouseClick(calcsNav)
            tryCompare(luaEngine, "currentView", "CALCS")
            wait(30)
            var bdPanel = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.calcs.breakdownPanel")
            var cell = findInteractiveCalcsCell()
            verify(cell !== null, "Expected clickable breakdown cell in CalcsView")
            mouseClick(cell)
            tryCompare(bdPanel, "visible", true)
            uiTest.sendKeyClick(win, Qt.Key_Escape, Qt.NoModifier)
            tryCompare(bdPanel, "visible", false)

            // 8. Notes tab: edit notes text and verify Lua notes update
            Oracle.step(tc, "Notes: type into notes editor")
            var notesNav = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.shell.sidebar.btn_nav_NOTES")
            mouseClick(notesNav)
            tryCompare(luaEngine, "currentView", "NOTES")
            wait(40)
            var notesEditor = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.notes.text_editor")
            mouseClick(notesEditor, 10, 10)
            notesEditor.forceActiveFocus()
            tryCompare(notesEditor, "activeFocus", true)
            uiTest.sendKeyClick(win, Qt.Key_P, Qt.NoModifier)
            uiTest.sendKeyClick(win, Qt.Key_O, Qt.NoModifier)
            uiTest.sendKeyClick(win, Qt.Key_B, Qt.NoModifier)
            wait(200)
            tryVerify(function() {
                return notesEditor.text.toLowerCase().indexOf("pob") >= 0
                    && luaEngine.getNotes().toLowerCase().indexOf("pob") >= 0
            }, 1500)

            // 9. Back -> BuildListPage (discard unsaved edits so src/Builds/ is untouched)
            Oracle.step(tc, "TopBar Back -> BuildListPage")
            var backBtn = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.topbar.back")
            mouseClick(backBtn)
            wait(25)
            var savePrompt = uiTest.findObject(win.contentItem, "pob.shell.dialog.save_prompt")
            if (savePrompt && savePrompt.visible) {
                var dontSaveBtn = Oracle.findRequired(tc, uiTest, savePrompt.contentItem, "pob.confirm.btn_extra")
                mouseClick(dontSaveBtn)
            }
            tryCompare(luaEngine, "currentMode", "LIST")
            var buildList = Oracle.findRequired(tc, uiTest, win.contentItem, "pob.buildlist.root")
            verify(buildList.visible)

            Oracle.assertZeroWarnings(tc, uiTest, "PlaywrightJourney")
        }
    }
}
