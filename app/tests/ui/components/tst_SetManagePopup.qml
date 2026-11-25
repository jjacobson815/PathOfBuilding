import QtQuick
import QtTest
import "qrc:/qml/components" as Widgets
import "../UiTestOracle.js" as Oracle

Item {
    id: container
    width: 1100
    height: 720

    Widgets.SetManagePopup {
        id: dlg
        title: "Manage Item Sets"
        noun: "item set"
        deleteTitle: "Delete Item Set"
        fn: ({
            list: "pob_itemsGetSetList",
            setActive: "pob_itemsSetActiveSet",
            create: "pob_itemsNewSet",
            copy: "pob_itemsCopySet",
            rename: "pob_itemsRenameSet",
            remove: "pob_itemsDeleteSet",
            move: "pob_itemsMoveSet",
        })
        sharedFn: ({
            list: "pob_itemsGetSharedSets",
            tooltip: "pob_itemsSharedSetTooltip",
            share: "pob_itemsShareSet",
            importSet: "pob_itemsImportSharedSet",
            rename: "pob_itemsRenameSharedSet",
            remove: "pob_itemsDeleteSharedSet",
        })
    }

    TestCase {
        id: tc
        name: "SetManagePopupTest"
        when: windowShown

        function initTestCase() {
            uiTest.resetEngineForTest()
        }

        function init() {
            uiTest.resetWarnings()
            dlg.close()
            wait(10)
        }

        function test_all_ac() {
            dlg.openFresh()
            tryCompare(dlg, "visible", true)

            Oracle.findRequired(tc, uiTest, dlg, "pob.setmanage.root")
            var btnCopy = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.setmanage.btn_copy")
            var btnDel = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.setmanage.btn_delete")
            Oracle.findRequired(tc, uiTest, container.Window.window, "pob.setmanage.btn_new")
            var btnRen = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.setmanage.btn_rename")
            var btnUp = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.setmanage.btn_up")
            var btnDown = Oracle.findRequired(tc, uiTest, container.Window.window, "pob.setmanage.btn_down")

            verify(dlg.count >= 1)
            verify(!dlg.hasSel)
            verify(!btnDel.controlEnabled)

            // AC-02 & AC-04: Synthetic 2-set QVariantList check
            dlg.sets = uiTest.toVariantList([
                { title: "Default", rawTitle: "Default", listLabel: "Default (Active)", isActive: true },
                { title: "Boss", rawTitle: "Boss", listLabel: "Boss", isActive: false }
            ])
            dlg.selIndex = 0
            wait(10)
            verify(btnCopy.controlEnabled)
            verify(btnRen.controlEnabled)
            verify(btnDel.controlEnabled)
            verify(!btnUp.controlEnabled)
            verify(btnDown.controlEnabled)

            dlg.selIndex = 1
            wait(10)
            verify(btnUp.controlEnabled)
            verify(!btnDown.controlEnabled)

            dlg.refresh()
            Oracle.assertMultiResLayout(tc, container, container.Window.window, uiTest, "SetManagePopup")

            keyClick(Qt.Key_Escape)
            tryCompare(dlg, "visible", false)
            Oracle.assertZeroWarnings(tc, uiTest, "SetManagePopup")
        }
    }
}
