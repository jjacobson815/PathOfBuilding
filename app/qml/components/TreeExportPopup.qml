import QtQuick
import QtQuick.Layouts

// TreeExportPopup — Phase 4 Part 4.2 + Phase 10 Part 10.2, ports
// TreeTab:OpenExportPopup (TreeTab.lua:832-859): the active spec's link
// (spec:EncodeURL against the version's pathofexile.com URL), async "Shrink
// with PoEURL", Copy, and Done.
PopupBase {
    id: root
    objectName: "pob.treeexport.root"

    property string link: ""
    property string errMsg: ""
    property bool shrinking: false
    property bool shrunk: false
    property int pendingReqId: 0

    title: "Export Tree"
    padding: 16

    function cancelPending() {
        if (pendingReqId > 0) {
            luaEngine.invoke("pob_cancelPoeUrl", [pendingReqId])
            pendingReqId = 0
        }
        shrinking = false
    }

    function openFresh() {
        cancelPending()
        shrunk = false
        errMsg = ""
        var r = luaEngine.invoke("pob_exportTree", [])
        link = (r && r.link) ? r.link : ""
        open()
        linkInput.forceActiveFocus()
        linkInput.selectAll()
    }

    function doShrink() {
        if (link.length === 0 || shrinking || shrunk) return
        errMsg = ""
        shrinking = true
        var r = luaEngine.invoke("pob_shrinkPoeUrl", [link])
        if (r && r.ok && r.reqId) {
            pendingReqId = r.reqId
        } else {
            shrinking = false
            errMsg = (r && r.msg) ? r.msg : "^1Failed to get PoEURL link. Try again later.^7"
        }
    }

    onClosed: cancelPending()

    Connections {
        target: luaEngine
        enabled: root.visible && root.shrinking && root.pendingReqId > 0
        function onNetworkChanged() {
            if (!root.shrinking || root.pendingReqId <= 0) return
            var st = luaEngine.invoke("pob_getShrinkPoeUrlStatus", [root.pendingReqId])
            if (!st || !st.done) return
            root.shrinking = false
            root.pendingReqId = 0
            if (st.ok && st.shortUrl) {
                root.shrunk = true
                root.link = st.shortUrl
                linkInput.forceActiveFocus()
                linkInput.selectAll()
            } else {
                root.errMsg = st.msg ? st.msg : "^1Failed to get PoEURL link. Try again later.^7"
            }
        }
    }

    ColumnLayout {
        width: 360
        spacing: 8

        ColorText {
            Layout.alignment: Qt.AlignHCenter
            sourceText: "Passive tree link:"
            font.pixelSize: theme.fontSize
        }
        Chrome {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            controlEnabled: true
            TextInput {
                id: linkInput
                objectName: "pob.treeexport.input"
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                verticalAlignment: TextInput.AlignVCenter
                color: theme.text
                font.pixelSize: theme.fontSize
                selectByMouse: true
                readOnly: true
                clip: true
                text: root.link
            }
        }
        ColorText {
            visible: root.errMsg.length > 0
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: 360
            sourceText: root.errMsg
            font.pixelSize: theme.fontSize
            wrapMode: Text.WordWrap
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            Button {
                objectName: "pob.treeexport.shrink"
                implicitWidth: 140; implicitHeight: 20
                label: root.shrinking ? "Shrinking..." : (root.shrunk ? "Done" : "Shrink with PoEURL")
                controlEnabled: root.link.length > 0 && !root.shrinking && !root.shrunk
                onClicked: root.doShrink()
            }
            Button {
                objectName: "pob.treeexport.copy"
                implicitWidth: 80; implicitHeight: 20
                label: "Copy"
                controlEnabled: root.link.length > 0
                onClicked: luaEngine.copyText(root.link)
            }
            Button {
                objectName: "pob.treeexport.done"
                implicitWidth: 80; implicitHeight: 20
                label: "Done"
                onClicked: {
                    root.cancelPending()
                    root.accept()
                }
            }
        }
    }
}
