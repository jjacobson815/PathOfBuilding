import QtQuick
import QtQuick.Controls
import "../components" as Widgets

// TREE view — passive-tree tab view component embedding the high-performance
// SceneGraph TreeViewer. Extracted from main.qml (Part 1.1).
Item {
    id: treeViewRoot
    anchors.fill: parent

    Widgets.TreeViewer {
        id: treeViewer
        anchors.fill: parent
        controller: treeViewController
        interactive: true
        readOnly: false
        showSearch: true
    }
}
