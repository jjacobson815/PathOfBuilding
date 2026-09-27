import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls as QC

// TimelessJewelPopup — Phase 4 Part 4.5, ports TreeTab:FindTimelessJewel
// (TreeTab.lua:1369-2891, "Find a Timeless Jewel", 916x565) over the
// pob_timeless* bridge (app/lua/pob_timeless.lua), which carries the legacy
// search, list parsing, fallback-weight generation, item creation and trade
// URL building. This file owns layout only.
//
// Left column: jewel type / conqueror / devotion (Militant Faith), jewel
// socket + mini tree preview, Filter Nodes (+ distance, protect notables),
// node search + the three weight sliders, fallback weight mode, total
// minimum weight. Right column: Desired / Fallback node lists (one
// "id, w1, w2, minW" row per line), results (double-click adds the jewel to
// the build, Shift+click selects a range for the trade URL), trade options.
//
// Deviations (documented): the socket preview shows the SELECTED socket
// rather than the hovered dropdown row; the trade league is a text field
// (legacy fetches the league list from the network — Phase 10/12).
PopupBase {
    id: root

    property var st: ({})
    property bool fallbackShown: false
    property bool _syncing: false
    property int selIndex: -1
    property int highlightIndex: -1

    // Results can run to 100k+ rows: the list model is just the COUNT and rows
    // are fetched a page at a time (pob_timelessGetResults) as they scroll in.
    readonly property int resultCount: st.resultCount || 0
    property var _rowCache: ({})
    function rowAt(i) {
        if (_rowCache[i] === undefined) {
            const page = Math.floor(i / 200) * 200
            const r = luaEngine.invoke("pob_timelessGetResults", [page + 1, 200])
            const rows = (r && r.rows && r.rows.length !== undefined) ? r.rows : []
            for (let k = 0; k < rows.length; k++) _rowCache[page + k] = rows[k]
        }
        return _rowCache[i] || ({ label: "", tooltip: [] })
    }
    property bool tradeStarted: false
    readonly property var nodeOptions: (st.nodeOptions && st.nodeOptions.length !== undefined) ? st.nodeOptions : []

    title: "Find a Timeless Jewel"
    padding: 10

    function _arr(v) { return (v && v.length !== undefined) ? v : [] }

    function apply(s) {
        if (!s) return
        _syncing = true
        _rowCache = ({})
        const first = (s.results && s.results.length !== undefined) ? s.results : []
        for (let k = 0; k < first.length; k++) _rowCache[k] = first[k]
        st = s
        jewelSelect.model = _arr(s.jewelTypes)
        jewelSelect.currentIndex = (s.jewelTypeIndex || 1) - 1
        conquerorSelect.model = _arr(s.conquerors)
        conquerorSelect.currentIndex = (s.conquerorIndex || 1) - 1
        devotion1.model = _arr(s.devotionVariants)
        devotion1.currentIndex = (s.devotion1 || 1) - 1
        devotion2.model = _arr(s.devotionVariants)
        devotion2.currentIndex = (s.devotion2 || 1) - 1
        socketSelect.model = _arr(s.sockets)
        socketSelect.currentIndex = (s.socketIndex || 1) - 1
        filterCheck.state = !!s.socketFilter
        distanceSlider.value = (s.socketFilterDistance || 0) / 10
        protectSelect.model = _arr(s.protectOptions)
        nodeSelect.model = nodeOptions
        fallbackMode.model = _arr(s.fallbackModes)
        fallbackMode.currentIndex = (s.fallbackModeIndex || 1) - 1
        if (!minWeightEdit.editing)
            minWeightEdit.text = (s.totalMinimumWeight !== undefined && s.totalMinimumWeight !== null) ? String(s.totalMinimumWeight) : ""
        if (!listArea.activeFocus)
            listArea.text = fallbackShown ? (s.searchListFallback || "") : (s.searchList || "")
        msgLabel.label = s.msg || ""
        _syncing = false
    }

    function refresh() { apply(luaEngine.invoke("pob_timelessGetState", [])) }
    function set(field, value) { apply(luaEngine.invoke("pob_timelessSet", [field, value])) }

    function openFresh() {
        selIndex = -1; highlightIndex = -1; tradeStarted = false
        refresh()
        open()
    }

    // Slider units -> list weights (legacy getNodeWeights: w1/w2 = val*10,
    // min = val*500 or "required" at the top).
    function weights() {
        return [Math.round(w1Slider.value * 10 * 1000) / 1000,
                nodeTwoStats ? Math.round(w2Slider.value * 10 * 1000) / 1000 : 0,
                w3Slider.value >= 1 ? "required" : Math.round(w3Slider.value * 500)]
    }
    readonly property bool nodeTwoStats: nodeSelect.currentIndex >= 0 && nodeSelect.currentIndex < nodeOptions.length
                                         && !!nodeOptions[nodeSelect.currentIndex].twoStats
    function setSliders(w) {
        _syncing = true
        w1Slider.value = Math.min(1, (Number(w[0]) || 0) / 10)
        w2Slider.value = Math.min(1, (Number(w[1]) || 0) / 10)
        w3Slider.value = (String(w[2]).toLowerCase() === "required") ? 1 : Math.min(1, (Number(w[2]) || 0) / 500)
        _syncing = false
    }
    function weightsChanged() {
        if (_syncing || nodeSelect.currentIndex < 0) return
        const w = weights()
        apply(luaEngine.invoke("pob_timelessSetWeights", [nodeSelect.currentIndex + 1, fallbackShown, w[0], w[1], w[2]]))
    }

    ColumnLayout {
        width: 900
        spacing: 6

        RowLayout {
            spacing: 12

            // ---------------- left column ----------------
            ColumnLayout {
                Layout.preferredWidth: 440
                Layout.alignment: Qt.AlignTop
                spacing: 5

                RowLayout {
                    Label { label: "^7Jewel Type:"; size: 16; Layout.preferredWidth: 150 }
                    DropDownControl {
                        id: jewelSelect
                        Layout.preferredWidth: 200; Layout.preferredHeight: 20
                        onSelected: function (i) { root.set("jewelType", i + 1) }
                    }
                }
                RowLayout {
                    Label { label: "^7Conqueror:"; size: 16; Layout.preferredWidth: 150 }
                    DropDownControl {
                        id: conquerorSelect
                        Layout.preferredWidth: 200; Layout.preferredHeight: 20
                        onSelected: function (i) { root.set("conqueror", i + 1) }
                    }
                }
                RowLayout {
                    visible: !!root.st.showDevotion
                    Label { label: "^7Devotion modifiers:"; size: 16; Layout.preferredWidth: 150 }
                    DropDownControl {
                        id: devotion1
                        Layout.preferredWidth: 140; Layout.preferredHeight: 20
                        popupMinWidth: 240
                        onSelected: function (i) { root.set("devotion1", i + 1) }
                    }
                    DropDownControl {
                        id: devotion2
                        Layout.preferredWidth: 140; Layout.preferredHeight: 20
                        popupMinWidth: 240
                        onSelected: function (i) { root.set("devotion2", i + 1) }
                    }
                }
                RowLayout {
                    Label { label: "^7Jewel Socket:"; size: 16; Layout.preferredWidth: 150 }
                    DropDownControl {
                        id: socketSelect
                        Layout.preferredWidth: 200; Layout.preferredHeight: 20
                        popupMinWidth: 260
                        onSelected: function (i) { root.set("socket", i + 1) }
                    }
                }
                RowLayout {
                    CheckBox {
                        id: filterCheck
                        Layout.preferredWidth: 18; Layout.preferredHeight: 18
                        Layout.leftMargin: labelWidth + 12
                        label: "Filter Nodes:"
                        tooltipText: "Only search nodes in radius that are allocated (plus unallocated nodes within the distance below)"
                        onToggled: function (s) { root.set("socketFilter", s) }
                    }
                    Label { visible: filterCheck.state; label: "^7Node Distance:"; size: 14 }
                    Slider {
                        id: distanceSlider
                        visible: filterCheck.state
                        Layout.preferredWidth: 100
                        divCount: 11
                        onValueChanged: if (!root._syncing) root.set("socketFilterDistance", Math.floor(value * 10 + 0.01))
                    }
                    Label { visible: filterCheck.state; label: "^7" + Math.floor(distanceSlider.value * 10 + 0.01); size: 14 }
                }
                RowLayout {
                    visible: !!root.st.showProtect
                    Label { label: "^7Protect allocated nodes from changing:"; size: 14 }
                    DropDownControl {
                        id: protectSelect
                        Layout.preferredWidth: 150; Layout.preferredHeight: 20
                    }
                    Button { implicitWidth: 45; implicitHeight: 20; label: "Add"
                        onClicked: if (protectSelect.currentLabel) root.apply(luaEngine.invoke("pob_timelessProtect", ["add", protectSelect.currentLabel])) }
                    Button { implicitWidth: 50; implicitHeight: 20; label: "Clear"
                        onClicked: root.apply(luaEngine.invoke("pob_timelessProtect", ["clear", ""])) }
                }
                Label {
                    visible: !!root.st.showProtect && root._arr(root.st.protectedNodes).length > 0
                    label: "^7" + root._arr(root.st.protectedNodes).join(", ")
                    size: 14
                }

                // Mini tree preview of the selected socket (TimelessJewelSocketControl:
                // zoom 5, 300x300, crosshair).
                Rectangle {
                    Layout.preferredWidth: 304; Layout.preferredHeight: 154
                    color: "black"
                    border.color: theme.border
                    TreeViewer {
                        anchors.fill: parent
                        anchors.margins: 2
                        controller: treeViewController
                        interactive: false
                        showSearch: false
                        showCrosshair: true
                        focusZoom: 5
                        focusNodeId: {
                            const s = root._arr(root.st.sockets)
                            const i = (root.st.socketIndex || 1) - 1
                            return (i >= 0 && i < s.length && s[i].id > 0) ? s[i].id : -1
                        }
                    }
                }

                RowLayout {
                    Label { label: "^7Search for Node:"; size: 16; Layout.preferredWidth: 150 }
                    DropDownControl {
                        id: nodeSelect
                        Layout.preferredWidth: 270; Layout.preferredHeight: 20
                        popupMinWidth: 420
                        labelFor: function (o) { return o ? o.name : "" }
                        tooltipForItem: function (o, tt) {
                            if (!o || !o.descriptions || o.descriptions.length === undefined) return
                            for (let i = 0; i < o.descriptions.length; i++) tt.addLine(16, "^7" + o.descriptions[i])
                        }
                        onSelected: function (i) {
                            if (!root.nodeOptions[i] || root.nodeOptions[i].id === undefined) return
                            const w = root.weights()
                            const r = luaEngine.invoke("pob_timelessSelectNode", [i + 1, root.fallbackShown, w[0], w[1], w[2]])
                            if (r && r.exists) root.setSliders([r.w1, r.w2, r.w3])
                            else if (r && r.state) root.apply(r.state)
                        }
                    }
                }
                GridLayout {
                    columns: 3
                    columnSpacing: 6
                    rowSpacing: 3
                    Label { label: "^7Primary Node Weight:"; size: 14; Layout.preferredWidth: 150 }
                    Slider { id: w1Slider; Layout.preferredWidth: 200; value: 0.1; onValueChanged: root.weightsChanged() }
                    Label { label: "^7" + (w1Slider.value * 10).toFixed(3); size: 14 }
                    Label { label: (root.nodeTwoStats ? "^7" : "^9") + "Secondary Node Weight:"; size: 14 }
                    Slider { id: w2Slider; Layout.preferredWidth: 200; controlEnabled: root.nodeTwoStats; onValueChanged: root.weightsChanged() }
                    Label { label: (root.nodeTwoStats ? "^7" : "^9") + (w2Slider.value * 10).toFixed(3); size: 14 }
                    Label { label: "^7Minimum Node Weight:"; size: 14 }
                    Slider { id: w3Slider; Layout.preferredWidth: 200; onValueChanged: root.weightsChanged() }
                    Label { label: "^7" + (w3Slider.value >= 1 ? "Required" : Math.round(w3Slider.value * 500)); size: 14 }
                }
                RowLayout {
                    Label { label: "^7Fallback Weight Mode:"; size: 14; Layout.preferredWidth: 150 }
                    DropDownControl {
                        id: fallbackMode
                        Layout.preferredWidth: 180; Layout.preferredHeight: 20
                        popupMinWidth: 240
                        onSelected: function (i) { root.set("fallbackMode", i + 1) }
                    }
                    Button { implicitWidth: 80; implicitHeight: 20; label: "Generate"
                        tooltipText: "Generate fallback node weights from the selected stat"
                        onClicked: { root.fallbackShown = true; root.apply(luaEngine.invoke("pob_timelessGenerateFallback", [])) } }
                }
                RowLayout {
                    Label { label: "^7Total Minimum Weight:"; size: 14; Layout.preferredWidth: 150 }
                    EditControl {
                        id: minWeightEdit
                        Layout.preferredWidth: 80; Layout.preferredHeight: 20
                        isNumeric: true
                        onEdited: function (t) { if (!root._syncing) luaEngine.invoke("pob_timelessSet", ["totalMinimumWeight", t]) }
                    }
                }
            }

            // ---------------- right column ----------------
            ColumnLayout {
                Layout.preferredWidth: 440
                Layout.alignment: Qt.AlignTop
                spacing: 5

                RowLayout {
                    Button { implicitWidth: 120; implicitHeight: 20; label: "Desired Nodes"
                        locked: !root.fallbackShown
                        onClicked: { root.fallbackShown = false; listArea.text = root.st.searchList || "" } }
                    Button { implicitWidth: 120; implicitHeight: 20; label: "Fallback Nodes"
                        locked: root.fallbackShown
                        onClicked: { root.fallbackShown = true; listArea.text = root.st.searchListFallback || "" } }
                }
                Rectangle {
                    Layout.preferredWidth: 440; Layout.preferredHeight: 200
                    color: theme.sideBarBg
                    border.color: theme.border
                    QC.ScrollView {
                        anchors.fill: parent
                        anchors.margins: 2
                        QC.TextArea {
                            id: listArea
                            color: theme.text
                            font.family: theme.fontFixed
                            font.pixelSize: 13
                            wrapMode: TextEdit.NoWrap
                            selectByMouse: true
                            background: null
                            onTextChanged: {
                                if (root._syncing || !activeFocus) return
                                luaEngine.invoke("pob_timelessSet", [root.fallbackShown ? "searchListFallback" : "searchList", text])
                            }
                        }
                    }
                }

                Label { label: "^7Results (" + root.resultCount + "):"; size: 14 }
                Rectangle {
                    Layout.preferredWidth: 440; Layout.preferredHeight: 160
                    color: "transparent"
                    border.color: theme.border
                    clip: true
                    ListView {
                        id: resultList
                        anchors.fill: parent
                        anchors.margins: 2
                        model: root.resultCount
                        boundsBehavior: Flickable.StopAtBounds
                        QC.ScrollBar.vertical: QC.ScrollBar {}
                        delegate: Rectangle {
                            id: resRow
                            readonly property var modelData: root.rowAt(index)
                            width: resultList.width
                            height: 16
                            readonly property bool inRange: root.highlightIndex >= 0 && root.selIndex >= 0
                                && index >= Math.min(root.selIndex, root.highlightIndex) && index <= Math.max(root.selIndex, root.highlightIndex)
                            color: index === root.selIndex ? theme.active : (inRange ? theme.hover : (resMa.containsMouse ? theme.hover : "transparent"))
                            Label { x: 3; anchors.verticalCenter: parent.verticalCenter; label: modelData.label; size: 13; font.family: theme.fontFixed }
                            MouseArea {
                                id: resMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: function (m) {
                                    if (m.modifiers & Qt.ShiftModifier) root.highlightIndex = index
                                    else { root.selIndex = index; root.highlightIndex = -1 }
                                    root.tradeStarted = false
                                }
                                onDoubleClicked: {
                                    const r = luaEngine.invoke("pob_timelessAddJewel", [index + 1])
                                    root.refresh()
                                }
                                onContainsMouseChanged: {
                                    if (!containsMouse) { resTip.hide(); return }
                                    resTip.clear()
                                    const lines = root._arr(modelData.tooltip)
                                    for (let i = 0; i < lines.length; i++) resTip.addLine(14, lines[i])
                                    const host = root.contentItem.parent
                                    resTip.parent = host
                                    const p = resRow.mapToItem(host, 0, 0)
                                    const win = resRow.Window.window
                                    const o = host.mapFromItem(null, 0, 0)
                                    resTip.showAt(p.x, p.y, resRow.width, resRow.height,
                                                  Qt.rect(o.x, o.y, win ? win.width : host.width, win ? win.height : host.height))
                                }
                            }
                        }
                    }
                }

                // Trade URL (TreeTab.lua:2277-2385; league list is network-only, so free text).
                RowLayout {
                    DropDownControl { id: realmSelect; Layout.preferredWidth: 70; Layout.preferredHeight: 20
                        model: ["PC", "Sony", "Xbox"]; currentIndex: 0 }
                    EditControl { id: leagueEdit; Layout.preferredWidth: 110; Layout.preferredHeight: 20; text: "Standard"
                        tooltipText: "Trade league name" }
                    DropDownControl { id: tradeType; Layout.preferredWidth: 150; Layout.preferredHeight: 20
                        popupMinWidth: 240
                        model: ["Instant buyout", "Instant buyout and in person", "In person (online in league)", "In person (online)", "Any (includes offline)"]
                        currentIndex: 0 }
                }
                RowLayout {
                    CheckBox { id: searchMore; Layout.preferredWidth: 18; Layout.preferredHeight: 18
                        Layout.leftMargin: labelWidth + 12; label: "Search Maximum Amount:" }
                    Button {
                        implicitWidth: 150; implicitHeight: 20
                        label: root.tradeStarted ? "Open Next Trade URL" : "Open Trade URL"
                        controlEnabled: root.resultCount > 0
                        onClicked: {
                            // Legacy passes the list's selection + Shift-highlight;
                            // the bridge keeps legacy's lastSearch paging.
                            const r = luaEngine.invoke("pob_timelessTradeUrl",
                                        [root.selIndex >= 0 ? root.selIndex + 1 : 1,
                                         root.highlightIndex >= 0 ? root.highlightIndex + 1 : null,
                                         ["pc", "sony", "xbox"][realmSelect.currentIndex], leagueEdit.text,
                                         tradeType.currentIndex + 1, searchMore.state])
                            if (r && r.url) {
                                luaEngine.openURL(r.url)
                                luaEngine.copyText(r.url)
                                root.selIndex = r.startIndex - 1
                                root.highlightIndex = r.endIndex - 1
                                resultList.positionViewAtIndex(root.selIndex, ListView.Beginning)
                                root.tradeStarted = true
                            } else if (r && r.done) {
                                msgLabel.label = "^7No more results to search."
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            Button { implicitWidth: 80; implicitHeight: 20; label: "Search"
                onClicked: {
                    root.apply(luaEngine.invoke("pob_timelessSearch", []))
                    root.selIndex = root.resultCount > 0 ? 0 : -1
                    root.highlightIndex = -1
                    root.tradeStarted = false
                } }
            Button { implicitWidth: 80; implicitHeight: 20; label: "Reset"
                onClicked: { root.apply(luaEngine.invoke("pob_timelessReset", [])); root.selIndex = -1; root.highlightIndex = -1; root.tradeStarted = false } }
            Button { implicitWidth: 80; implicitHeight: 20; label: "Cancel"
                onClicked: root.close() }
            Label { id: msgLabel; size: 14 }
        }
    }

    property Tooltip resTip: Tooltip { z: 1000 }
    onClosed: resTip.hide()
}
