import QtQuick

// NewFolderPopup — canned dialog, ports legacy main:OpenNewFolderPopup.
// A TextInputPopup specialization: same prompt+field+Create/Cancel shape,
// with the Create button/Enter additionally disabled on illegal filename
// characters (legacy's EditControl filter pattern `\/:%*%?"<>|%c` — control
// chars + `\ / : * ? " < > |`). The actual MakeDir(...) call is the
// caller's responsibility (read `text` in onAccepted), matching legacy
// (OpenNewFolderPopup's Create handler owns the MakeDir call + error popup,
// not the popup class itself).
TextInputPopup {
    id: root

    prompt: "Enter folder name:"
    confirmLabel: "Create"
    confirmEnabled: text.match(/\S/) !== null && !/[\\/:*?"<>|\x00-\x1f]/.test(text)
}
