import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import "../components" as Widgets

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
        return Array.isArray(v) ? v : []
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

    RowLayout {
        anchors.fill: parent
        anchors.margins: theme.space3
        spacing: theme.space3

        // =====================================================================
        // LEFT COLUMN — GUIDED CHARACTER IMPORT (Steps 1 -> 4)
        // =====================================================================
        QC.ScrollView {
            Layout.fillWidth: true
            Layout.preferredWidth: 12
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: Math.max(360, parent.width - 14)
                spacing: theme.space2

                // Title
                Widgets.ColorText {
                    Layout.fillWidth: true
                    sourceText: "^7Import a Character"
                    font.pixelSize: theme.fontSize + 4
                    font.bold: true
                }
                Widgets.ColorText {
                    Layout.fillWidth: true
                    sourceText: "Follow the steps below to bring a Path of Exile character into a new build (or update your current one)."
                    defaultColor: theme.muted
                    wrapMode: Text.WordWrap
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

                        Widgets.ColorText {
                            sourceText: "^71. Connect your account"
                            font.pixelSize: theme.fontSize + 1
                            font.bold: true
                        }

                        // Auth method toggle + Realm selector
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: theme.space2

                            Widgets.Button {
                                label: "Sign in with Path of Exile"
                                implicitWidth: 175
                                implicitHeight: 24
                                locked: root._isOAuth
                                onClicked: root._invoke("pob_importSetAuthMethod", ["oauth"])
                            }
                            Widgets.Button {
                                label: "Enter Account Name"
                                implicitWidth: 145
                                implicitHeight: 24
                                locked: !root._isOAuth
                                onClicked: root._invoke("pob_importSetAuthMethod", ["account"])
                            }
                            Item { Layout.fillWidth: true }
                            Widgets.ColorText {
                                sourceText: "Realm:"
                                defaultColor: theme.muted
                            }
                            Widgets.DropDownControl {
                                id: realmDrop
                                implicitWidth: 74
                                implicitHeight: 24
                                onSelected: (idx) => {
                                    if (root._syncing) return
                                    const item = realmDrop.model[idx]
                                    if (item && item.id) root._invoke("pob_importSetRealm", [item.id])
                                }
                            }
                        }

                        // OAuth controls
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root._isOAuth
                            spacing: theme.space1

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: theme.space2

                                Widgets.Button {
                                    visible: !(root.st && root.st.oauthAuthorized) && !(root.st && root.st.oauthWaiting)
                                    label: "Authorize with Path of Exile"
                                    implicitWidth: 195
                                    implicitHeight: 26
                                    onClicked: root._invoke("pob_importOAuthStart", [])
                                }
                                Widgets.Button {
                                    visible: !!(root.st && root.st.oauthWaiting)
                                    label: "Cancel Sign-In"
                                    implicitWidth: 120
                                    implicitHeight: 26
                                    onClicked: root._invoke("pob_importOAuthCancel", [])
                                }
                                Widgets.Button {
                                    visible: !!(root.st && root.st.oauthAuthorized)
                                    label: "Fetch Characters"
                                    implicitWidth: 135
                                    implicitHeight: 26
                                    controlEnabled: !!(root.st && root.st.canFetchCharacters)
                                    tooltipText: (root.st && root.st.fetchDisabledReason) || ""
                                    onClicked: root._invoke("pob_importFetchCharacters", [])
                                }
                                Widgets.Button {
                                    visible: !!(root.st && root.st.oauthAuthorized)
                                    label: "Sign Out"
                                    implicitWidth: 85
                                    implicitHeight: 26
                                    onClicked: root._invoke("pob_importOAuthLogout", [])
                                }
                                Item { Layout.fillWidth: true }
                            }

                            Widgets.ColorText {
                                Layout.fillWidth: true
                                visible: !!(root.st && root.st.oauthAuthorized && !root.st.canFetchCharacters && root.st.fetchDisabledReason)
                                sourceText: (root.st && root.st.fetchDisabledReason) || ""
                                defaultColor: theme.muted
                                wrapMode: Text.WordWrap
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
                                    implicitWidth: 130
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

                            Widgets.ColorText {
                                Layout.fillWidth: true
                                visible: !!(root.st && !root.st.canFetchCharacters && root.st.fetchDisabledReason && !root.st.accountNameHint)
                                sourceText: (root.st && root.st.fetchDisabledReason) || ""
                                defaultColor: theme.muted
                                wrapMode: Text.WordWrap
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
                            RowLayout {
                                spacing: theme.space1
                                Widgets.Button {
                                    label: root.sessionIdExpanded ? "Hide Private Profile Session ID" : "Private profile? Use POESESSID (optional)"
                                    implicitWidth: 240
                                    implicitHeight: 22
                                    onClicked: root.sessionIdExpanded = !root.sessionIdExpanded
                                }
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
                                Widgets.ColorText {
                                    Layout.fillWidth: true
                                    sourceText: "Only needed if your Path of Exile profile is private and you prefer not to use OAuth sign-in."
                                    defaultColor: theme.muted
                                    wrapMode: Text.WordWrap
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
                            sourceText: "^72. Pick a character"
                            font.pixelSize: theme.fontSize + 1
                            font.bold: true
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
                                implicitWidth: 160
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
                                Layout.fillWidth: true
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
                            sourceText: "^73. Choose what to import"
                            font.pixelSize: theme.fontSize + 1
                            font.bold: true
                        }

                        // What to bring in (both checked by default)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: theme.space3

                            RowLayout {
                                spacing: theme.space1
                                Widgets.CheckBox {
                                    state: !!(root.st && root.st.importTree)
                                    onToggled: (v) => root._invoke("pob_importSetOptions", [{ importTree: v }])
                                }
                                Widgets.ColorText { sourceText: "^7Passive Tree & Jewels" }
                            }

                            RowLayout {
                                spacing: theme.space1
                                Widgets.CheckBox {
                                    state: !!(root.st && root.st.importItems)
                                    onToggled: (v) => root._invoke("pob_importSetOptions", [{ importItems: v }])
                                }
                                Widgets.ColorText { sourceText: "^7Items & Skills" }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        // Target: new build (default) vs overwrite open build
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: theme.space2

                            Widgets.ColorText {
                                sourceText: "Destination:"
                                defaultColor: theme.muted
                            }
                            Widgets.Button {
                                label: "New build (default)"
                                implicitWidth: 145
                                implicitHeight: 24
                                locked: (root.st && root.st.targetMode) !== "overwrite"
                                onClicked: root._invoke("pob_importSetOptions", [{ targetMode: "new" }])
                            }
                            Widgets.Button {
                                label: "Overwrite current build"
                                implicitWidth: 165
                                implicitHeight: 24
                                locked: (root.st && root.st.targetMode) === "overwrite"
                                onClicked: root._invoke("pob_importSetOptions", [{ targetMode: "overwrite" }])
                            }
                            Item { Layout.fillWidth: true }
                        }

                        Widgets.ColorText {
                            Layout.fillWidth: true
                            sourceText: (root.st && root.st.targetMode) === "overwrite"
                                ? ("^xF59E0BWill overwrite \"" + ((root.st && root.st.currentBuildName) || "Unnamed build") + "\" after confirmation.")
                                : "Creates a new build named after the selected character so your current build stays untouched."
                            defaultColor: theme.muted
                            wrapMode: Text.WordWrap
                        }

                        // Collapsed Options disclosure
                        Widgets.Button {
                            label: root.optionsExpanded ? "Hide Options" : "Options (delete / weapon swap)"
                            implicitWidth: 215
                            implicitHeight: 22
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
                                            sourceText: "^7" + (modelData.label || "")
                                        }
                                        Widgets.ColorText {
                                            Layout.fillWidth: true
                                            sourceText: modelData.description || ""
                                            defaultColor: theme.muted
                                            wrapMode: Text.WordWrap
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

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: theme.space2

                            Widgets.Button {
                                label: (root.st && root.st.importButtonLabel) || "Import as New Build"
                                implicitWidth: 250
                                implicitHeight: 30
                                controlEnabled: !!(root.st && root.st.canImportCharacter)
                                tooltipText: (root.st && root.st.importDisabledReason) || ""
                                onClicked: root._triggerCharacterImport(false)
                            }
                            Item { Layout.fillWidth: true }
                        }

                        Widgets.ColorText {
                            Layout.fillWidth: true
                            visible: !!(root.st && !root.st.canImportCharacter && root.st.importDisabledReason)
                            sourceText: (root.st && root.st.importDisabledReason) || ""
                            defaultColor: theme.muted
                            wrapMode: Text.WordWrap
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
            Layout.fillWidth: true
            Layout.preferredWidth: 10
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: Math.max(320, parent.width - 14)
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
                            sourceText: "^7Share this build"
                            font.pixelSize: theme.fontSize + 3
                            font.bold: true
                        }
                        Widgets.ColorText {
                            Layout.fillWidth: true
                            sourceText: "Generate a build code to copy directly, or upload it to a build site to get a short link."
                            defaultColor: theme.muted
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: theme.space2

                            Widgets.Button {
                                label: "Generate Code"
                                implicitWidth: 120
                                implicitHeight: 26
                                onClicked: root._invoke("pob_importGenerateCode", [])
                            }
                            Widgets.Button {
                                label: "Copy"
                                implicitWidth: 74
                                implicitHeight: 26
                                controlEnabled: !!root._share.canCopy
                                tooltipText: root._share.copyDisabledReason || ""
                                onClicked: root._invoke("pob_importCopyShareCode", [])
                            }
                            Item { Layout.fillWidth: true }
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
                                implicitHeight: 24
                                onSelected: (idx) => {
                                    if (root._syncing) return
                                    const site = shareSiteDrop.model[idx]
                                    if (site && site.id) root._invoke("pob_importSetShareSite", [site.id])
                                }
                            }
                            Widgets.Button {
                                label: root._share.busy ? "Uploading..." : "Share Link"
                                implicitWidth: 105
                                implicitHeight: 24
                                controlEnabled: !!root._share.canUpload
                                tooltipText: root._share.uploadDisabledReason || ""
                                onClicked: root._invoke("pob_importUploadBuild", [])
                            }
                        }

                        Widgets.ColorText {
                            Layout.fillWidth: true
                            visible: !root._share.canUpload && !!(root._share.uploadDisabledReason)
                            sourceText: root._share.uploadDisabledReason || ""
                            defaultColor: theme.muted
                            wrapMode: Text.WordWrap
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
                                Widgets.ColorText { sourceText: "^7Export Support (Party buffs)" }
                                Widgets.ColorText {
                                    Layout.fillWidth: true
                                    sourceText: root._share.exportPartyDescription || ""
                                    defaultColor: theme.muted
                                    wrapMode: Text.WordWrap
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
                            sourceText: "^7Open a build from a link or code"
                            font.pixelSize: theme.fontSize + 3
                            font.bold: true
                        }
                        Widgets.ColorText {
                            Layout.fillWidth: true
                            sourceText: "Paste a pobb.in, Maxroll, Pastebin, or poe.ninja link — or a raw build share code. Opens as a new build by default."
                            defaultColor: theme.muted
                            wrapMode: Text.WordWrap
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
                                label: root._open.importButtonLabel || "Open as New Build"
                                implicitWidth: 165
                                implicitHeight: 26
                                controlEnabled: !!root._open.canImport
                                tooltipText: root._open.importDisabledReason || ""
                                onClicked: root._triggerOpenBuild(false)
                            }
                        }

                        Widgets.ColorText {
                            Layout.fillWidth: true
                            visible: !root._open.canImport && !!(root._open.importDisabledReason)
                            sourceText: root._open.importDisabledReason || ""
                            defaultColor: theme.muted
                            wrapMode: Text.WordWrap
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
