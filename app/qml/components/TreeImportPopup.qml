import QtQuick
import QtQuick.Layouts

// TreeImportPopup — Phase 4 Part 4.2 + Phase 10 Part 10.2, ports
// TreeTab:OpenImportPopup (TreeTab.lua:709-837): name + link fields, status/
// error line, Import/Cancel, plus async PoEURL redirect resolution off the UI
// thread via pob_resolvePoeUrl / pob_getPoeUrlStatus.
PopupBase {
    id: root

    signal imported(int index)

    property string msg: ""
    property bool resolving: false
    property int pendingReqId: 0
    readonly property bool canImport: !resolving
                                      && nameInput.text.match(/\S/) !== null
                                      && linkInput.text.match(/\S/) !== null

    title: "Import Tree"
    padding: 16
    acceptOnEnter: false
    onOpened: nameInput.forceActiveFocus()

    function cancelPending() {
        if (pendingReqId > 0) {
            luaEngine.invoke("pob_cancelPoeUrl", [pendingReqId])
            pendingReqId = 0
        }
        resolving = false
    }

    function openFresh() {
        cancelPending()
        nameInput.text = ""
        linkInput.text = ""
        msg = ""
        open()
        nameInput.forceActiveFocus()
    }

    function doImport() {
        if (!canImport) return
        var r = luaEngine.invoke("pob_importTree", [nameInput.text, linkInput.text])
        if (r && r.ok) {
            close()
            imported(r.index)
            return
        }
        if (r && r.needsNetwork) {
            msg = "Resolving PoEURL link..."
            resolving = true
            var nr = luaEngine.invoke("pob_resolvePoeUrl", [nameInput.text, linkInput.text])
            if (nr && nr.ok && nr.reqId) {
                pendingReqId = nr.reqId
            } else {
                resolving = false
                msg = (nr && nr.msg) ? nr.msg : "^1Failed to resolve PoEURL link^7"
            }
            return
        }
        msg = (r && r.msg) ? r.msg : "^1Import failed"
    }

    onClosed: cancelPending()

    Connections {
        target: luaEngine
        enabled: root.visible && root.resolving && root.pendingReqId > 0
        function onNetworkChanged() {
            if (!root.resolving || root.pendingReqId <= 0) return
            var st = luaEngine.invoke("pob_getPoeUrlStatus", [root.pendingReqId])
            if (!st || !st.done) return
            root.resolving = false
            root.pendingReqId = 0
            if (st.ok) {
                root.close()
                root.imported(st.index)
            } else {
                root.msg = st.msg ? st.msg : "^1Failed to resolve PoEURL link^7"
            }
        }
    }

    ColumnLayout {
        width: 540
        spacing: 8
        focus: true
        Keys.onReturnPressed: (event) => { root.doImport(); event.accepted = true }
        Keys.onEnterPressed: (event) => { root.doImport(); event.accepted = true }

        GridLayout {
            columns: 2
            columnSpacing: 8
            rowSpacing: 6
            Layout.fillWidth: true

            ColorText {
                sourceText: "Enter name for this passive tree:"
                font.pixelSize: theme.fontSize
            }
            Chrome {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                controlEnabled: !root.resolving
                TextInput {
                    id: nameInput
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    verticalAlignment: TextInput.AlignVCenter
                    color: theme.text
                    font.pixelSize: theme.fontSize
                    selectByMouse: true
                    readOnly: root.resolving
                    clip: true
                    KeyNavigation.tab: linkInput
                    onTextChanged: if (!root.resolving) root.msg = ""
                }
            }

            ColorText {
                sourceText: "Enter passive tree link:"
                font.pixelSize: theme.fontSize
            }
            Chrome {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                controlEnabled: !root.resolving
                TextInput {
                    id: linkInput
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    verticalAlignment: TextInput.AlignVCenter
                    color: theme.text
                    font.pixelSize: theme.fontSize
                    selectByMouse: true
                    readOnly: root.resolving
                    clip: true
                    KeyNavigation.tab: nameInput
                    onTextChanged: if (!root.resolving) root.msg = ""
                }
            }
        }

        ColorText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: 540
            sourceText: root.msg
            font.pixelSize: theme.fontSize
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            Button {
                implicitWidth: 80; implicitHeight: 20
                label: root.resolving ? "Resolving..." : "Import"
                controlEnabled: root.canImport
                onClicked: root.doImport()
            }
            Button {
                implicitWidth: 80; implicitHeight: 20
                label: "Cancel"
                onClicked: {
                    root.cancelPending()
                    root.reject()
                }
            }
        }
    }
}
