import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// CALCS view (calculation output browser). Extracted from main.qml (Part 1.1);
// behaviour unchanged. Bound to calcModel (sections + summary). Summary cards
// show Life/Mana/ES/TotalDPS from calcModel.summary. Each section lists its stat
// lines; clicking a stat with hasBreakdown opens a themed popup showing the
// breakdown from luaEngine.getCalcBreakdown(section, stat.breakdown). All colours
// come from the theme singleton. Visibility is parent-controlled.
Item {
    id: calcsView
    anchors.fill: parent
    clip: true

    // Breakdown popup state.
    property var breakdownLines: []
    property string breakdownTitle: ""

    function openBreakdown(sectionLabel, stat) {
        if (!stat || !stat.hasBreakdown) return
        var lines = luaEngine.getCalcBreakdown(sectionLabel, stat.breakdown)
        calcsView.breakdownLines = lines || []
        calcsView.breakdownTitle = (stat.label || "Stat") + " breakdown"
        breakdownPopup.open()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.space3
        spacing: 10

        Text {
            text: "Calculations"
            color: theme.text
            font.bold: true
            font.pixelSize: theme.fontSize + 4
        }

        // --- Summary cards ---
        RowLayout {
            spacing: theme.space2
            Repeater {
                model: [
                    { key: "life", label: "Life", val: calcModel.summary.life },
                    { key: "mana", label: "Mana", val: calcModel.summary.mana },
                    { key: "es", label: "Energy Shield", val: calcModel.summary.es },
                    { key: "totalDps", label: "Total DPS", val: calcModel.summary.totalDps },
                ]
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    color: theme.sideBarBg
                    border.color: theme.section
                    radius: theme.radiusControl
                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            text: modelData.label
                            color: theme.muted
                            font.pixelSize: theme.fontSize - 2
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.width
                        }
                        Text {
                            text: (modelData.val !== undefined && modelData.val !== null)
                                  ? String(Math.round(Number(modelData.val))) : "—"
                            color: theme.accent
                            font.bold: true
                            font.pixelSize: theme.fontSize + 2
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.width
                        }
                    }
                }
            }
        }

        // --- Sections ---
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            clip: true
            ColumnLayout {
                spacing: 10
                width: parent.width
                Repeater {
                    model: calcModel
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        color: theme.background
                        border.color: theme.section
                        radius: theme.radiusControl
                        property string secLabel: model && model.label ? model.label : ""
                        property var sectionStats: model ? model.stats : []
                        Column {
                            id: secCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: theme.space2
                            spacing: 2
                            Text {
                                text: model.label
                                color: theme.section
                                font.bold: true
                                font.pixelSize: theme.fontSize
                                width: parent.width
                            elide: Text.ElideRight
                            clip: true
                            }
                            Repeater {
                                model: sectionStats
                                delegate: Rectangle {
                                    width: secCol.width
                                    height: 22
                                    color: index % 2 ? theme.sideBarBg : "transparent"
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: theme.space1
                                        spacing: theme.space2
                                        Text {
                                            text: modelData.label ? (modelData.label + ":") : ""
                                            color: theme.text
                                            font.pixelSize: theme.fontSize - 1
                                            Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        clip: true
                                        }
                                        Text {
                                            text: modelData.value !== undefined ? String(modelData.value) : ""
                                            color: modelData.statType === "offence" ? theme.accent
                                                 : (modelData.statType === "defence" ? theme.section : theme.text)
                                            font.pixelSize: theme.fontSize - 1
                                        elide: Text.ElideRight
                                        clip: true
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: modelData.hasBreakdown
                                        cursorShape: modelData.hasBreakdown ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (modelData.hasBreakdown)
                                                calcsView.openBreakdown(secLabel, modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Breakdown popup (CalcBreakdownControl equivalent) ---
    Popup {
        id: breakdownPopup
        modal: true
        focus: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(520, calcsView.width - 40)
        height: Math.min(420, calcsView.height - 40)
        background: Rectangle { color: theme.sideBarBg; border.color: theme.accent; radius: theme.radiusCard }
        contentItem: ColumnLayout {
            spacing: theme.space1
            Text {
                text: calcsView.breakdownTitle
                color: theme.accent
                font.bold: true
                font.pixelSize: theme.fontSize + 1
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                Column {
                    spacing: 2
                    width: parent.width
                    Repeater {
                        model: calcsView.breakdownLines
                        delegate: Text {
                            text: modelData
                            color: theme.text
                            font.pixelSize: theme.fontSize - 1
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }
                    }
                }
            }
            Button {
                text: "Close"
                Layout.alignment: Qt.AlignRight
                onClicked: breakdownPopup.close()
            }
        }
    }
}
