import QtQuick
import QtQuick.Window
import QtQuick.Controls as QC
import QtQuick.Layouts
import "../components" as Widgets
import "../components/QmlBridge.js" as QmlBridge

// IMPORT / EXPORT view — Phase 11 (bridge: app/lua/pob_import.lua).
//
// Usability redesign (2026-10-16):
//   - Left column: single top-to-bottom guided character import flow
//     (1. Connect account -> 2. Pick character -> 3. Choose what to import &
//     collapsed Options with 1-sentence descriptions -> 4. Import button).
//     No duplicate character pickers; default target is a new build named
//     after the character; overwriting the open build requires confirmation.
//   - Right column: clearly separated "Share this build" and
//     "Open a build from a link or code" cards.
//   - Plain-word status text and explicit disabled-button reasons everywhere.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property var st: ({})
    property bool _pending: false
    property bool _syncing: false
    property bool optionsExpanded: false
    property bool sessionIdExpanded: false

    // Pending confirmation context: "character" | "openBuild" | ""
    property string _confirmKind: ""

    function arr(v) {
        return QmlBridge.toArray(v)
    }

    function refresh() {
        if (_pending) return
        _pending = true
        Qt.callLater(_doRefresh)
    }

    function _doRefresh() {
        _pending = false
        if (luaEngine.currentMode !== "BUILD") return
        const s = luaEngine.invoke("pob_importGetState", [])
        if (s && s.ok) _applyState(s)
    }

    function _invoke(fn, args) {
        const res = luaEngine.invoke(fn, args || [])
        if (res && res.ok) {
            _applyState(res)
        }
        return res
    }

    function _applyState(s) {
        if (!s || !s.ok) return
        _syncing = true
        st = s

        // Sync realms
        const realmItems = arr(s.realms)
        realmDrop.model = realmItems
        let rIdx = 0
        for (let i = 0; i < realmItems.length; i++) {
            if (realmItems[i].id === s.realmId) { rIdx = i; break }
        }
        realmDrop.currentIndex = realmItems.length > 0 ? rIdx : -1

        // Sync account name & history
        if (!accountEdit.editing) {
            accountEdit.text = s.accountName || ""
        }
        if (!sessionEdit.editing) {
            sessionEdit.text = s.sessionId || ""
        }
        const hist = arr(s.accountHistory)
        historyDrop.model = hist
        historyDrop.currentIndex = hist.indexOf(s.accountName || "")

        // Sync leagues
        const lgs = arr(s.leagues)
        leagueDrop.model = lgs
        const lIdx = lgs.indexOf(s.selectedLeague || "All")
        leagueDrop.currentIndex = lIdx >= 0 ? lIdx : (lgs.length > 0 ? 0 : -1)

        // Sync characters
        const chars = arr(s.characters)
        charDrop.model = chars
        charDrop.currentIndex = (s.selectedCharIndex && s.selectedCharIndex >= 1 && s.selectedCharIndex <= chars.length)
            ? (s.selectedCharIndex - 1) : -1

        // Sync share section
        const sh = s.share || {}
        if (!shareCodeEdit.editing) {
            shareCodeEdit.text = sh.code || ""
        }
        const sites = arr(sh.sites)
        shareSiteDrop.model = sites
        let sIdx = 0
        for (let j = 0; j < sites.length; j++) {
            if (sites[j].id === sh.selectedSiteId) { sIdx = j; break }
        }
        shareSiteDrop.currentIndex = sites.length > 0 ? sIdx : -1

        // Sync open section
        const op = s.open || {}
        if (!openCodeEdit.editing) {
            openCodeEdit.text = op.input || ""
        }
        const modeMap = { "new": 0, "overwrite": 1, "compare": 2 }
        openModeDrop.currentIndex = modeMap[op.mode] !== undefined ? modeMap[op.mode] : 0

        _syncing = false
    }

    function _triggerCharacterImport(confirmed) {
        const res = luaEngine.invoke("pob_importExecuteCharacter", [confirmed === true])
        if (!res) return
        if (res.needsConfirm) {
            root._confirmKind = "character"
            confirmPopup.title = res.confirmTitle || "Overwrite Current Build?"
            confirmPopup.message = res.confirmMessage || "This will overwrite your current build."
            confirmPopup.confirmLabel = "Overwrite & Import"
            confirmPopup.open()
        } else if (res.ok) {
            _applyState(res)
        }
    }

    function _triggerOpenBuild(confirmed) {
        const res = luaEngine.invoke("pob_importOpenBuild", [confirmed === true])
        if (!res) return
        if (res.needsConfirm) {
            root._confirmKind = "openBuild"
            confirmPopup.title = res.confirmTitle || "Replace Current Build?"
            confirmPopup.message = res.confirmMessage || "This will replace your current build."
            confirmPopup.confirmLabel = "Replace Build"
            confirmPopup.open()
        } else if (res.ok) {
            _applyState(res)
        }
    }

    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: if (visible) refresh()

    Connections {
        target: luaEngine
        function onModeChanged() { if (root.visible) root.refresh() }
        function onImportChanged() { if (root.visible) root.refresh() }
        function onNetworkChanged() { if (root.visible) root.refresh() }
    }

    // 1-second tick for OAuth login & rate-limit countdowns
    Timer {
        interval: 1000
        repeat: true
        running: root.visible && (!!(root.st && root.st.oauthWaiting) || ((root.st && root.st.rateLimitSecondsLeft) || 0) > 0)
        onTriggered: root.refresh()
    }

    readonly property var _share: (st && st.share) ? st.share : ({})
    readonly property var _open: (st && st.open) ? st.open : ({})
    readonly property var _options: arr(st && st.options)
    readonly property bool _isOAuth: (st && st.authMethod) !== "account"

    // Compact inline instruction/preview line: abbreviates constrained text
    // with ElideRight ("...") and reveals the full text/instruction on hover.
    component InlineHint: Item {
        id: hintRoot
        property string text: ""
        property string hoverText: ""
        property color defaultColor: theme.muted
        property int maxLines: 1
        property int fontSize: theme.fontSizeSm

        implicitWidth: hintLabel.implicitWidth
        implicitHeight: hintLabel.implicitHeight

        Widgets.ColorText {
            id: hintLabel
            anchors.left: parent.left
            anchors.right: parent.right
            sourceText: hintRoot.text
            defaultColor: hintRoot.defaultColor
            font.pixelSize: hintRoot.fontSize
            elide: Text.ElideRight
            maximumLineCount: hintRoot.maxLines
            wrapMode: hintRoot.maxLines > 1 ? Text.WordWrap : Text.NoWrap
        }

        MouseArea {
            id: hintMa
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onContainsMouseChanged: hintRoot._updateTip()
        }

        Widgets.Tooltip {
            id: hintTip
        }

        function _updateTip() {
            const full = hintRoot.hoverText.length > 0 ? hintRoot.hoverText : hintRoot.text
            if (!hintMa.containsMouse || !full || (!hintLabel.truncated && hintRoot.hoverText.length === 0)) {
                hintTip.hide()
                return
            }
            hintTip.clear()
            hintTip.maxWidth = 360
            hintTip.addLine(14, full)
            if (hintTip.lines.length > 0) {
                const win = Window.window
                const origin = win ? hintRoot.mapToItem(win.contentItem, 0, 0) : Qt.point(0, 0)
                const viewport = win
                    ? Qt.rect(-origin.x, -origin.y, win.width, win.height)
                    : Qt.rect(0, 0, hintRoot.width, hintRoot.height)
                hintTip.showAt(0, 0, hintRoot.width, hintRoot.height, viewport)
                return
            }
            hintTip.hide()
        }

        onTextChanged: if (hintMa.containsMouse) _updateTip()
        onHoverTextChanged: if (hintMa.containsMouse) _updateTip()
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: theme.space3
        spacing: theme.space3

        // =====================================================================
        // LEFT COLUMN — GUIDED CHARACTER IMPORT (Steps 1 -> 4)
        // =====================================================================
        QC.ScrollView {
            id: leftScroll
            Layout.fillWidth: true
            Layout.preferredWidth: 12
            Layout.fillHeight: true
            clip: true
            QC.ScrollBar.horizontal.policy: QC.ScrollBar.AlwaysOff

            ColumnLayout {
                width: leftScroll.availableWidth
                spacing: theme.space2

                // Title
                Widgets.ColorText {
                    Layout.fillWidth: true
                    sourceText: "^7Import a Character"
                    font.pixelSize: theme.fontSize + 4
                    font.bold: true
                    elide: Text.ElideRight
                }
                InlineHint {
                    Layout.fillWidth: true
                    text: "Follow the steps below to bring a Path of Exile character into a new build (or update your current one)."
                }

                // -------------------------------------------------------------
                // STEP 1: Connect your account
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: step1Col.implicitHeight + theme.space3 * 2
                    color: theme.titleBar
                    border.width: 1
                    border.color: theme.border
                    radius: theme.radiusControl

                    ColumnLayout {
                        id: step1Col
                        anchors.fill: parent
                        anchors.margins: theme.space3
                        spacing: theme.space2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: theme.space2

                            Widgets.ColorText {
                                Layout.fillWidth: true
                                sourceText: "^71. Connect your account"
                                font.pixelSize: theme.fontSize + 1
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Widgets.ColorText {
                                sourceText: "Realm:"
                                defaultColor: theme.muted
                            }
                            Widgets.DropDownControl {
                                id: realmDrop
                                objectName: "pob.import.realm_drop"
                                implicitWidth: 74
                                implicitHeight: 24
                                onSelected: (idx) => {
                                    if (root._syncing) return
                                    const item = realmDrop.model[idx]
                                    if (item && item.id) root._invoke("pob_importSetRealm", [item.id])
                                }
                            }
                        }

                        // Auth method toggle
                        Flow {
                            Layout.fillWidth: true
                            spacing: theme.space2

                            Widgets.Button {
                                objectName: "pob.import.auth_oauth"
                                label: "Sign in with Path of Exile"
                                width: Math.min(implicitWidth, parent.width)
                                implicitHeight: 24
                                locked: root._isOAuth
                                onClicked: root._invoke("pob_importSetAuthMethod", ["oauth"])
                            }
                            Widgets.Button {
                                label: "Enter Account Name"
                                width: Math.min(implicitWidth, parent.width)
                                implicitHeight: 24
                                locked: !root._isOAuth
                                onClicked: root._invoke("pob_importSetAuthMethod", ["account"])
                            }
                        }

                        // OAuth controls
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root._isOAuth
                            spacing: theme.space1

                            Flow {
                                Layout.fillWidth: true
                                spacing: theme.space2

                                Widgets.Button {
                                    visible: !(root.st && root.st.oauthAuthorized) && !(root.st && root.st.oauthWaiting)
                                    label: "Authorize with Path of Exile"
                                    width: Math.min(implicitWidth, parent.width)
                                    implicitHeight: 26
                                    onClicked: root._invoke("pob_importOAuthStart", [])
                                }
                                Widgets.Button {
                                    visible: !!(root.st && root.st.oauthWaiting)
                                    label: "Cancel Sign-In"
                                    width: Math.min(implicitWidth, parent.width)
                                    implicitHeight: 26
                                    onClicked: root._invoke("pob_importOAuthCancel", [])
                                }
                                Widgets.Button {
                                    visible: !!(root.st && root.st.oauthAuthorized)
                                    label: "Fetch Characters"
                                    width: Math.min(implicitWidth, parent.width)
                                    implicitHeight: 26
                                    controlEnabled: !!(root.st && root.st.canFetchCharacters)
                                    tooltipText: (root.st && root.st.fetchDisabledReason) || ""
                                    onClicked: root._invoke("pob_importFetchCharacters", [])
                                }
                                Widgets.Button {
                                    visible: !!(root.st && root.st.oauthAuthorized)
                                    label: "Sign Out"
                                    width: Math.min(implicitWidth, parent.width)
                                    implicitHeight: 26
                                    onClicked: root._invoke("pob_importOAuthLogout", [])
                                }
                            }

                            InlineHint {
                                Layout.fillWidth: true
                                visible: !!(root.st && root.st.oauthAuthorized && !root.st.canFetchCharacters && root.st.fetchDisabledReason)
                                text: (root.st && root.st.fetchDisabledReason) || ""
                            }
                        }

                        // Account-name controls
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: !root._isOAuth
                            spacing: theme.space2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: theme.space2

                                Widgets.EditControl {
                                    id: accountEdit
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 110
                                    implicitHeight: 24
                                    placeholder: "AccountName#1234"
                                    onEdited: (txt) => {
                                        if (!root._syncing) root._invoke("pob_importSetAccountName", [txt])
                                    }
                                    onCommitted: (txt) => {
                                        if (!root._syncing) root._invoke("pob_importSetAccountName", [txt])
                                    }
                                }
                                Widgets.Button {
                                    label: "Fetch Characters"
                                    implicitHeight: 24
                                    controlEnabled: !!(root.st && root.st.canFetchCharacters)
                                    tooltipText: (root.st && root.st.fetchDisabledReason) || ""
                                    onClicked: root._invoke("pob_importFetchCharacters", [])
                                }
                            }

                            Widgets.ColorText {
                                Layout.fillWidth: true
                                visible: !!(root.st && root.st.accountNameHint)
                                sourceText: "^1" + ((root.st && root.st.accountNameHint) || "")
                                wrapMode: Text.WordWrap
                            }

                            InlineHint {
                                Layout.fillWidth: true
                                visible: !!(root.st && !root.st.canFetchCharacters && root.st.fetchDisabledReason && !root.st.accountNameHint)
                                text: (root.st && root.st.fetchDisabledReason) || ""
                            }

                            // Saved account history row
                            RowLayout {
                                Layout.fillWidth: true
                                visible: root.arr(root.st && root.st.accountHistory).length > 0
                                spacing: theme.space2

                                Widgets.ColorText {
                                    sourceText: "Recent accounts:"
                                    defaultColor: theme.muted
                                }
                                Widgets.DropDownControl {
                                    id: historyDrop
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 90
                                    implicitHeight: 22
                                    placeholder: "Select a recent account..."
                                    onSelected: (idx) => {
                                        if (root._syncing) return
                                        const name = historyDrop.model[idx]
                                        if (name) root._invoke("pob_importSetAccountName", [name])
                                    }
                                }
                                Widgets.Button {
                                    label: "x"
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    controlEnabled: historyDrop.currentIndex >= 0
                                    tooltipText: "Remove selected account from history"
                                    onClicked: {
                                        const name = historyDrop.model[historyDrop.currentIndex]
                                        if (name) root._invoke("pob_importRemoveAccountHistory", [name])
                                    }
                                }
                            }

                            // Optional POESESSID fallback disclosure
                            Widgets.Button {
                                label: root.sessionIdExpanded ? "Hide Private Profile Session ID" : "Private profile? Use POESESSID (optional)"
                                Layout.maximumWidth: parent.width
                                implicitHeight: 22
                                onClicked: root.sessionIdExpanded = !root.sessionIdExpanded
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.sessionIdExpanded
                                spacing: theme.space1

                                Widgets.EditControl {
                                    id: sessionEdit
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    useFixedFont: true
                                    placeholder: "Optional POESESSID cookie value for private profiles..."
                                    onEdited: (txt) => {
                                        if (!root._syncing) root._invoke("pob_importSetSessionId", [txt])
                                    }
                                    onCommitted: (txt) => {
                                        if (!root._syncing) root._invoke("pob_importSetSessionId", [txt])
                                    }
                                }
                                InlineHint {
                                    Layout.fillWidth: true
                                    text: "Only needed if your Path of Exile profile is private and you prefer not to use OAuth sign-in."
                                }
                            }
                        }
                    }
                }

                // -------------------------------------------------------------
                // STEP 2: Pick a character (single character picker!)
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: step2Col.implicitHeight + theme.space3 * 2
                    color: theme.titleBar
                    border.width: 1
                    border.color: theme.border
                    radius: theme.radiusControl

                    ColumnLayout {
                        id: step2Col
                        anchors.fill: parent
                        anchors.margins: theme.space3
                        spacing: theme.space2

                        Widgets.ColorText {
                            Layout.fillWidth: true
                            sourceText: "^72. Pick a character"
                            font.pixelSize: theme.fontSize + 1
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: theme.space2

                            Widgets.ColorText {
                                sourceText: "League:"
                                defaultColor: theme.muted
                            }
                            Widgets.DropDownControl {
                                id: leagueDrop
                                Layout.preferredWidth: 115
                                Layout.minimumWidth: 80
                                implicitHeight: 24
                                controlEnabled: root.arr(root.st && root.st.characters).length > 0 || root.arr(root.st && root.st.leagues).length > 1
                                onSelected: (idx) => {
                                    if (root._syncing) return
                                    const lg = leagueDrop.model[idx]
                                    if (lg) root._invoke("pob_importSetLeague", [lg])
                                }
                            }
                            Widgets.ColorText {
                                sourceText: "Character:"
                                defaultColor: theme.muted
                            }
                            Widgets.DropDownControl {
                                id: charDrop
                                objectName: "pob.import.char_drop"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 100
                                implicitHeight: 24
                                searchable: true
                                placeholder: "Fetch characters in Step 1 first..."
                                controlEnabled: root.arr(root.st && root.st.characters).length > 0
                                onSelected: (idx) => {
                                    if (root._syncing) return
                                    root._invoke("pob_importSetCharacter", [idx + 1])
                                }
                            }
                        }
                    }
                }

                // -------------------------------------------------------------
                // STEP 3: Choose what to import & Target & Collapsed Options
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: step3Col.implicitHeight + theme.space3 * 2
                    color: theme.titleBar
                    border.width: 1
                    border.color: theme.border
                    radius: theme.radiusControl

                    ColumnLayout {
                        id: step3Col
                        anchors.fill: parent
                        anchors.margins: theme.space3
                        spacing: theme.space2

                        Widgets.ColorText {
                            Layout.fillWidth: true
                            sourceText: "^73. Choose what to import"
                            font.pixelSize: theme.fontSize + 1
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        // What to bring in (both checked by default)
                        Flow {
                            Layout.fillWidth: true
                            spacing: theme.space3

                            Row {
                                spacing: theme.space1
                                Widgets.CheckBox {
                                    anchors.verticalCenter: parent.verticalCenter
                                    state: !!(root.st && root.st.importTree)
                                    onToggled: (v) => root._invoke("pob_importSetOptions", [{ importTree: v }])
                                }
                                Widgets.ColorText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    sourceText: "^7Passive Tree & Jewels"
                                }
                            }

                            Row {
                                spacing: theme.space1
                                Widgets.CheckBox {
                                    anchors.verticalCenter: parent.verticalCenter
                                    state: !!(root.st && root.st.importItems)
                                    onToggled: (v) => root._invoke("pob_importSetOptions", [{ importItems: v }])
                                }
                                Widgets.ColorText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    sourceText: "^7Items & Skills"
                                }
                            }
                        }

                        // Target: new build (default) vs overwrite open build
                        Flow {
                            Layout.fillWidth: true
                            spacing: theme.space2

                            Widgets.ColorText {
                                height: 24
                                verticalAlignment: Text.AlignVCenter
                                sourceText: "Destination:"
                                defaultColor: theme.muted
                            }
                            Widgets.Button {
                                label: "New build (default)"
                                width: Math.min(implicitWidth, parent.width)
                                implicitHeight: 24
                                locked: (root.st && root.st.targetMode) !== "overwrite"
                                onClicked: root._invoke("pob_importSetOptions", [{ targetMode: "new" }])
                            }
                            Widgets.Button {
                                label: "Overwrite current build"
                                width: Math.min(implicitWidth, parent.width)
                                implicitHeight: 24
                                locked: (root.st && root.st.targetMode) === "overwrite"
                                onClicked: root._invoke("pob_importSetOptions", [{ targetMode: "overwrite" }])
                            }
                        }

                        InlineHint {
                            Layout.fillWidth: true
                            text: (root.st && root.st.targetMode) === "overwrite"
                                ? ("^xF59E0BWill overwrite \"" + ((root.st && root.st.currentBuildName) || "Unnamed build") + "\" after confirmation.")
                                : "Creates a new build named after the selected character so your current build stays untouched."
                        }

                        // Collapsed Options disclosure
                        Widgets.Button {
                            label: root.optionsExpanded ? "Hide Options" : "Options (delete / weapon swap)"
                            Layout.maximumWidth: parent.width
                            implicitHeight: 24
                            onClicked: root.optionsExpanded = !root.optionsExpanded
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.optionsExpanded
                            spacing: theme.space2

                            Repeater {
                                model: root._options
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: theme.space2

                                    Widgets.CheckBox {
                                        Layout.alignment: Qt.AlignTop
                                        state: !!modelData.checked
                                        onToggled: (v) => {
                                            const patch = {}
                                            patch[modelData.key] = v
                                            root._invoke("pob_importSetOptions", [patch])
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Widgets.ColorText {
                                            Layout.fillWidth: true
                                            sourceText: "^7" + (modelData.label || "")
                                            elide: Text.ElideRight
                                        }
                                        InlineHint {
                                            Layout.fillWidth: true
                                            text: modelData.description || ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // -------------------------------------------------------------
                // STEP 4: Import action + plain-word status & disabled reason
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: step4Col.implicitHeight + theme.space3 * 2
                    color: theme.titleBar
                    border.width: 1
                    border.color: theme.border
                    radius: theme.radiusControl

                    ColumnLayout {
                        id: step4Col
                        anchors.fill: parent
                        anchors.margins: theme.space3
                        spacing: theme.space2

                        Widgets.Button {
                            objectName: "pob.import.btn_import"
                            label: (root.st && root.st.importButtonLabel) || "Import as New Build"
                            Layout.maximumWidth: parent.width
                            implicitHeight: 28
                            controlEnabled: !!(root.st && root.st.canImportCharacter)
                            tooltipText: (root.st && root.st.importDisabledReason) || ""
                            onClicked: root._triggerCharacterImport(false)
                        }

                        InlineHint {
                            Layout.fillWidth: true
                            visible: !!(root.st && !root.st.canImportCharacter && root.st.importDisabledReason)
                            text: (root.st && root.st.importDisabledReason) || ""
                        }

                        Widgets.ColorText {
                            Layout.fillWidth: true
                            visible: !!(root.st && root.st.statusText)
                            sourceText: "^7" + ((root.st && root.st.statusText) || "")
                            wrapMode: Text.WordWrap
                        }

                        Widgets.ColorText {
                            Layout.fillWidth: true
                            visible: !!(root.st && root.st.errorText)
                            sourceText: "^1" + ((root.st && root.st.errorText) || "")
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Item { Layout.preferredHeight: theme.space2 }
            }
        }

        // =====================================================================
        // RIGHT COLUMN — BUILD SHARING ("Share this build" & "Open a build")
        // =====================================================================
        QC.ScrollView {
            id: rightScroll
            Layout.fillWidth: true
            Layout.preferredWidth: 10
            Layout.fillHeight: true
            clip: true
            QC.ScrollBar.horizontal.policy: QC.ScrollBar.AlwaysOff

            ColumnLayout {
                width: rightScroll.availableWidth
                spacing: theme.space3

                // -------------------------------------------------------------
                // SHARE THIS BUILD
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: shareCol.implicitHeight + theme.space3 * 2
                    color: theme.titleBar
                    border.width: 1
                    border.color: theme.border
                    radius: theme.radiusControl

                    ColumnLayout {
                        id: shareCol
                        anchors.fill: parent
                        anchors.margins: theme.space3
                        spacing: theme.space2

                        Widgets.ColorText {
                            Layout.fillWidth: true
                            sourceText: "^7Share this build"
                            font.pixelSize: theme.fontSize + 3
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        InlineHint {
                            Layout.fillWidth: true
                            text: "Generate a build code to copy directly, or upload it to a build site to get a short link."
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: theme.space2

                            Widgets.Button {
                                objectName: "pob.import.share_btn"
                                label: "Generate Code"
                                width: Math.min(implicitWidth, parent.width)
                                implicitHeight: 26
                                onClicked: root._invoke("pob_importGenerateCode", [])
                            }
                            Widgets.Button {
                                label: "Copy"
                                width: Math.min(implicitWidth, parent.width)
                                implicitHeight: 26
                                controlEnabled: !!root._share.canCopy
                                tooltipText: root._share.copyDisabledReason || ""
                                onClicked: root._invoke("pob_importCopyShareCode", [])
                            }
                        }

                        Widgets.EditControl {
                            id: shareCodeEdit
                            Layout.fillWidth: true
                            implicitHeight: 24
                            readOnly: true
                            useFixedFont: true
                            placeholder: "Click Generate Code to create a shareable build code..."
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: theme.space2

                            Widgets.ColorText {
                                sourceText: "Upload to:"
                                defaultColor: theme.muted
                            }
                            Widgets.DropDownControl {
                                id: shareSiteDrop
                                Layout.fillWidth: true
                                Layout.minimumWidth: 80
                                implicitHeight: 24
                                onSelected: (idx) => {
                                    if (root._syncing) return
                                    const site = shareSiteDrop.model[idx]
                                    if (site && site.id) root._invoke("pob_importSetShareSite", [site.id])
                                }
                            }
                            Widgets.Button {
                                label: root._share.busy ? "Uploading..." : "Share Link"
                                implicitHeight: 24
                                controlEnabled: !!root._share.canUpload
                                tooltipText: root._share.uploadDisabledReason || ""
                                onClicked: root._invoke("pob_importUploadBuild", [])
                            }
                        }

                        InlineHint {
                            Layout.fillWidth: true
                            visible: !root._share.canUpload && !!(root._share.uploadDisabledReason)
                            text: root._share.uploadDisabledReason || ""
                        }

                        // Export Support checkbox (feeds PartyTab)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: theme.space2

                            Widgets.CheckBox {
                                Layout.alignment: Qt.AlignTop
                                state: !!root._share.exportParty
                                onToggled: (v) => root._invoke("pob_importSetExportParty", [v])
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Widgets.ColorText {
                                    Layout.fillWidth: true
                                    sourceText: "^7Export Support (Party buffs)"
                                    elide: Text.ElideRight
                                }
                                InlineHint {
                                    Layout.fillWidth: true
                                    maxLines: 2
                                    text: root._share.exportPartyDescription || ""
                                }
                            }
                        }

                        Widgets.ColorText {
                            Layout.fillWidth: true
                            visible: !!(root._share.statusText)
                            sourceText: "^2" + (root._share.statusText || "")
                            wrapMode: Text.WordWrap
                        }
                        Widgets.ColorText {
                            Layout.fillWidth: true
                            visible: !!(root._share.errorText)
                            sourceText: "^1" + (root._share.errorText || "")
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // -------------------------------------------------------------
                // OPEN A BUILD FROM A LINK OR CODE
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: openCol.implicitHeight + theme.space3 * 2
                    color: theme.titleBar
                    border.width: 1
                    border.color: theme.border
                    radius: theme.radiusControl

                    ColumnLayout {
                        id: openCol
                        anchors.fill: parent
                        anchors.margins: theme.space3
                        spacing: theme.space2

                        Widgets.ColorText {
                            Layout.fillWidth: true
                            sourceText: "^7Open a build from a link or code"
                            font.pixelSize: theme.fontSize + 3
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        InlineHint {
                            Layout.fillWidth: true
                            maxLines: 2
                            text: "Paste a pobb.in, Maxroll, Pastebin, or poe.ninja link — or a raw build share code. Opens as a new build by default."
                        }

                        Widgets.EditControl {
                            id: openCodeEdit
                            Layout.fillWidth: true
                            implicitHeight: 26
                            useFixedFont: true
                            placeholder: "Paste build link or share code..."
                            onEdited: (txt) => {
                                if (!root._syncing) root._invoke("pob_importValidateInput", [txt])
                            }
                            onCommitted: (txt) => {
                                if (!root._syncing) root._invoke("pob_importValidateInput", [txt])
                            }
                        }

                        Widgets.ColorText {
                            Layout.fillWidth: true
                            visible: !!(root._open.detail)
                            sourceText: (root._open.valid ? "^2" : "^1") + (root._open.detail || "")
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: theme.space2

                            Widgets.DropDownControl {
                                id: openModeDrop
                                Layout.fillWidth: true
                                Layout.minimumWidth: 100
                                implicitHeight: 26
                                model: [
                                    "Open as a new build (default)",
                                    "Replace current build",
                                    "Open as comparison"
                                ]
                                onSelected: (idx) => {
                                    if (root._syncing) return
                                    const modes = ["new", "overwrite", "compare"]
                                    root._invoke("pob_importSetOpenMode", [modes[idx] || "new"])
                                }
                            }

                            Widgets.Button {
                                objectName: "pob.import.open_btn"
                                label: root._open.importButtonLabel || "Open as New Build"
                                implicitHeight: 26
                                controlEnabled: !!root._open.canImport
                                tooltipText: root._open.importDisabledReason || ""
                                onClicked: root._triggerOpenBuild(false)
                            }
                        }

                        InlineHint {
                            Layout.fillWidth: true
                            visible: !root._open.canImport && !!(root._open.importDisabledReason)
                            text: root._open.importDisabledReason || ""
                        }

                        Widgets.ColorText {
                            Layout.fillWidth: true
                            visible: !!(root._open.statusText)
                            sourceText: "^2" + (root._open.statusText || "")
                            wrapMode: Text.WordWrap
                        }
                        Widgets.ColorText {
                            Layout.fillWidth: true
                            visible: !!(root._open.errorText)
                            sourceText: "^1" + (root._open.errorText || "")
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Item { Layout.preferredHeight: theme.space2 }
            }
        }
    }

    // Overwrite confirmation dialog
    Widgets.ConfirmPopup {
        id: confirmPopup
        onAccepted: {
            if (root._confirmKind === "character") {
                root._triggerCharacterImport(true)
            } else if (root._confirmKind === "openBuild") {
                root._triggerOpenBuild(true)
            }
            root._confirmKind = ""
        }
        onRejected: root._confirmKind = ""
    }
}
