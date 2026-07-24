import QtQuick
import QtQuick.Layouts

// ToastStack — Tier 1.4, ported from ToastNotification.lua's Render() loop:
// toasts stack bottom-up from the bottom-left corner (legacy anchors at
// "BOTTOMLEFT", yOffset=58 above the bottom bar, oldest toast nearest the
// anchor). Bound to the Lua-side toast mirror via luaEngine.getToasts() /
// the toastsChanged push signal (see LuaEngine::getToasts, the
// pob_host.lua ToastNotification wrap) — the same push-then-pull pattern
// already used for cloudErrorRequested/pathErrorRequested.
//
// Show/hide is a plain opacity fade (250ms in, matching legacy's
// SHOW_DURATION; the 75ms HIDE_DURATION isn't reproduced because dismiss
// removes the Lua-side entry immediately — see the pob_host.lua wrap's
// documented deviation — so there's nothing left to animate out against;
// Repeater's own remove transition below covers the visual case instead).
Item {
    id: root

    property var toasts: luaEngine.getToasts()

    Connections {
        target: luaEngine
        function onToastsChanged() { root.toasts = luaEngine.getToasts() }
    }

    // Newest toast at the top of the stack, oldest nearest the bottom anchor —
    // matches legacy's yOffset accumulation order (toasts iterated oldest-first,
    // each subsequent one pushed further UP from the anchor).
    readonly property var _stackOrder: {
        var out = [];
        for (var i = root.toasts.length - 1; i >= 0; i--) out.push(root.toasts[i]);
        return out;
    }

    implicitWidth: 312
    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: 312
        spacing: 4

        Repeater {
            model: root._stackOrder
            delegate: Toast {
                id: toastItem
                required property var modelData
                Layout.preferredWidth: 312
                toastId: modelData.id
                message: modelData.message
                onDismissRequested: luaEngine.dismissToast(modelData.id)

                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: 250 } }
            }
        }
    }
}
