pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kwin as KWinComponents

// panels stay where they are and fade out while zooming out
Item {
    id: panels

    required property var screen
    required property var desktop
    required property real zoom

    Repeater {
        model: KWinComponents.WindowFilterModel {
            desktop: panels.desktop
            screenName: panels.screen.name
            windowType: KWinComponents.WindowFilterModel.Dock
            windowModel: KWinComponents.WindowModel {}
        }

        KWinComponents.WindowThumbnail {
            required property var window

            wId: window.internalId
            x: window.x - panels.screen.geometry.x
            y: window.y - panels.screen.geometry.y
            width: window.width
            height: window.height
            opacity: 1 - panels.zoom
            visible: !window.hidden && opacity > 0
        }
    }
}
