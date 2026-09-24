import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../components" as Widgets

// CONFIG (ConfigTab) view. Extracted from main.qml (Part 1.1); behaviour
// unchanged. Renders the build's config options (src/Modules/ConfigOptions.lua)
// grouped by section, with the appropriate control per option type (boolean ->
// CheckBox, number -> TextField, list -> ComboBox, string -> TextField). Changing
// a control writes back via luaEngine.setConfigOption(name, value), which flags a
// rebuild. Uses a Repeater (no delegate reuse) so each model refresh recreates the
// controls and their initial state is always correct. Section headers are emitted
// when the section changes from the previous option. Visibility is parent-controlled.
Item {
    id: configView
    anchors.fill: parent
    clip: true

    // Control components (defined once; receive the option via the Loader's `cfg`
    // property). Initial state is set in Component.onCompleted because the Repeater
    // recreates the delegates on every model refresh.
    Component {
        id: cfgBoolComp
        CheckBox {
            Component.onCompleted: checked = (cfg.value === true)
            onClicked: luaEngine.setConfigOption(cfg.name, checked)
        }
    }
    Component {
        id: cfgNumComp
        TextField {
            Component.onCompleted: text = (cfg.value !== undefined && cfg.value !== null) ? String(cfg.value) : "0"
            color: theme.text
            background: Rectangle { color: theme.sideBarBg; border.color: theme.section; radius: theme.radiusControl }
            implicitWidth: 90
            onEditingFinished: {
                var n = Number(text)
                if (!isNaN(n)) luaEngine.setConfigOption(cfg.name, n)
            }
        }
    }
    Component {
        id: cfgListComp
        ComboBox {
            model: cfg.options || []
            textRole: "label"
            Component.onCompleted: {
                var idx = -1
                var opts = cfg.options || []
                for (var i = 0; i < opts.length; i++) {
                    if (opts[i].val === cfg.value) { idx = i; break }
                }
                currentIndex = idx
            }
            onActivated: {
                if (index >= 0 && cfg.options && cfg.options[index])
                    luaEngine.setConfigOption(cfg.name, cfg.options[index].val)
            }
        }
    }
    Component {
        id: cfgStrComp
        TextField {
            Component.onCompleted: text = (cfg.value !== undefined && cfg.value !== null) ? String(cfg.value) : ""
            color: theme.text
            background: Rectangle { color: theme.sideBarBg; border.color: theme.section; radius: theme.radiusControl }
            implicitWidth: 240
            onEditingFinished: luaEngine.setConfigOption(cfg.name, text)
        }
    }
    Component {
        id: sectionHeaderComp
        Rectangle {
            width: parent.width
            height: 28
            color: theme.section
            Text {
                text: secText
                color: theme.text
                font.bold: true
                font.pixelSize: theme.fontSize + 1
                anchors.left: parent.left
                anchors.leftMargin: theme.space2
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: theme.space3
        contentWidth: width
        clip: true
        background: Rectangle { color: theme.background }

        ColumnLayout {
            spacing: theme.space1
            width: parent.width

            Repeater {
                model: configModel
                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: theme.space1

                    // Section header: shown for the first option of each section
                    // (when the previous option's section differs, or this is index 0).
                    Loader {
                        Layout.fillWidth: true
                        Layout.preferredHeight: active ? 28 : 0
                        active: index === 0 || (configModel.get(index - 1) ? configModel.get(index - 1).section !== model.section : true)
                        sourceComponent: sectionHeaderComp
                        property string secText: model.section
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        MouseArea {
                            Layout.fillWidth: true
                            Layout.preferredHeight: labelText.height
                            hoverEnabled: true
                            ToolTip.text: model.tooltip ? model.tooltip : ""
                            ToolTip.visible: model.tooltip ? containsMouse : false
                            Widgets.ColorText {
                                id: labelText
                                sourceText: model.label || model.name
                                defaultColor: theme.text
                                font.pixelSize: theme.fontSize
                                width: parent.width
                                wrapMode: Text.WordWrap
                            }
                        }
                        Loader {
                            property var cfg: model
                            sourceComponent: {
                                if (model.type === "boolean") return cfgBoolComp
                                if (model.type === "number") return cfgNumComp
                                if (model.type === "list") return cfgListComp
                                return cfgStrComp
                            }
                        }
                    }
                }
            }
        }
    }
}
