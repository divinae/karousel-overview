pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

// a desktop has a window that asks for attention, in the orange the task manager uses for it, see WindowThumb
Rectangle {
    width: Kirigami.Units.smallSpacing * 3
    height: width
    radius: width / 2
    // OverviewScreen's attentionColor
    property color baseColor: Kirigami.Theme.neutralTextColor

    color: baseColor
    border.width: 1
    border.color: "white"
}
