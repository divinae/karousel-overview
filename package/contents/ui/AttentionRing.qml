pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

// around a window that asks for attention, in the orange the task manager uses for it, see WindowThumb
Rectangle {
    // the window's corner radius
    property real windowRadius: 0
    property color baseColor: Kirigami.Theme.neutralTextColor

    anchors.fill: parent
    anchors.margins: -2
    color: "transparent"
    radius: windowRadius + 2
    border.width: 2
    // see-through, it only has to be noticed
    border.color: Qt.alpha(baseColor, 0.45)
}
