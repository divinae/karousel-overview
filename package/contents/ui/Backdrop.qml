import QtQuick
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

// the desktop's wallpaper, blurred and dimmed with the theme's background color while zooming out
Item {
    id: backdrop

    required property QtObject screen
    required property QtObject desktop
    required property real zoom

    KWinComponents.DesktopBackground {
        id: background
        anchors.fill: parent
        activity: KWinComponents.Workspace.currentActivity
        desktop: backdrop.desktop
        outputName: backdrop.screen.name
    }

    FastBlur {
        anchors.fill: parent
        source: background
        radius: 64
        opacity: backdrop.zoom
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
        opacity: 0.7 * backdrop.zoom
    }
}
