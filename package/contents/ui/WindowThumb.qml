import QtQuick
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

Item {
    id: thumb

    required property QtObject window
    required property Item strip
    required property Item overviewRoot

    readonly property rect geometry: window.frameGeometry
    readonly property bool selected: overviewRoot.selectedWindow === window
    readonly property bool dropTarget: overviewRoot.dropTargetWindow === window
    readonly property bool showControls: hover.hovered && overviewRoot.draggedWindow === null && overviewRoot.zoom === 1

    // half of the gap between windows, Karousel's own gaps get too small when zoomed out,
    // grows with the zoom so that the zoom animation starts with windows at their real positions
    readonly property real inset: overviewRoot.zoom * Math.min(effect.configuration.WindowGap / 2, geometry.width * strip.thumbScale / 4, geometry.height * strip.thumbScale / 4)

    // where the thumbnail goes, x and width follow it with an animation
    readonly property real layoutX: strip.toStripX(geometry.x) + inset
    readonly property real layoutWidth: geometry.width * strip.thumbScale - 2 * inset
    // where the thumbnail stays while Karousel's view is synced to the preview, NaN when it follows the window
    property real heldX: NaN

    x: strip.syncingScroll && !isNaN(heldX) ? heldX : layoutX
    y: (geometry.y - strip.screenGeometry.y) * strip.thumbScale + inset
    width: layoutWidth
    height: geometry.height * strip.thumbScale - 2 * inset
    z: window.stackingOrder
    visible: window.normalWindow && (!overviewRoot.multipleScreens || window.output === overviewRoot.targetScreen)
    // a window that shows up while the view is synced has no place among the held thumbnails yet
    opacity: strip.syncingScroll && isNaN(heldX) ? 0 : overviewRoot.draggedWindow === window ? 0.3 : 1

    Accessible.role: Accessible.Button
    Accessible.name: window.caption
    Accessible.focused: selected

    // follow Karousel's rearranging smoothly, but not while zooming or dragging, when the position has to be exact
    readonly property bool animateMovement: overviewRoot.zoom === 1 && overviewRoot.draggedWindow === null && !strip.holdThumbs
    Behavior on x {
        enabled: thumb.animateMovement
        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
    }
    Behavior on y {
        enabled: thumb.animateMovement
        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
    }
    Behavior on width {
        enabled: thumb.animateMovement
        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
    }
    Behavior on height {
        enabled: thumb.animateMovement
        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
    }

    onGeometryChanged: strip.scheduleUpdateBounds()
    onVisibleChanged: strip.scheduleUpdateBounds()
    // the drag would never end without the DragHandler that tracks it
    Component.onDestruction: {
        if (overviewRoot.draggedWindow === window) {
            overviewRoot.cancelDrag();
        }
    }

    // the window and the blur behind it, with rounded corners
    Item {
        anchors.fill: parent
        layer.enabled: thumb.overviewRoot.windowRadius > 0
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: thumb.width
                height: thumb.height
                radius: thumb.overviewRoot.windowRadius
            }
        }

        // thumbnails don't get KWin's blur behind translucent windows, so blur the part of the wallpaper behind them,
        // outside the wallpaper its edge is stretched
        FastBlur {
            anchors.fill: parent
            visible: effect.configuration.BlurBehindWindows && thumb.strip.desktop !== null
            radius: 32
            source: ShaderEffectSource {
                sourceItem: thumb.strip.wallpaperBackground
                sourceRect: Qt.rect((thumb.x - thumb.strip.contentX - thumb.strip.viewportLeft) / thumb.strip.thumbScale,
                                    thumb.y / thumb.strip.thumbScale,
                                    thumb.width / thumb.strip.thumbScale,
                                    thumb.height / thumb.strip.thumbScale)
                textureSize: Qt.size(Math.max(1, thumb.width), Math.max(1, thumb.height))
                wrapMode: ShaderEffectSource.ClampToEdge
            }
        }

        KWinComponents.WindowThumbnail {
            anchors.fill: parent
            wId: thumb.window.internalId
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        color: "transparent"
        radius: thumb.overviewRoot.windowRadius + 3
        border.width: thumb.dropTarget ? 6 : 3
        border.color: Kirigami.Theme.highlightColor
        visible: thumb.selected || thumb.dropTarget || hover.hovered
        opacity: (thumb.selected || thumb.dropTarget ? 1 : 0.5) * thumb.overviewRoot.zoom
    }

    // app icon and window title, each can be turned off in the settings, the title also shows on hover
    Rectangle {
        readonly property bool showIcon: effect.configuration.ShowIcons
        readonly property bool showTitle: effect.configuration.ShowTitles || thumb.showControls
        readonly property real maxWidth: thumb.width - 2 * Kirigami.Units.smallSpacing

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        width: Math.min(info.implicitWidth, maxWidth) + 2 * Kirigami.Units.smallSpacing
        height: info.implicitHeight + Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: Qt.rgba(0, 0, 0, 0.7)
        visible: showIcon || showTitle
        opacity: thumb.overviewRoot.zoom

        Row {
            id: info
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: Kirigami.Units.iconSizes.small
                height: width
                source: thumb.window.icon
                visible: parent.parent.showIcon
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.parent.maxWidth - (parent.parent.showIcon ? Kirigami.Units.iconSizes.small + parent.spacing : 0))
                text: thumb.window.caption
                elide: Text.ElideRight
                color: "white"
                visible: parent.parent.showTitle
            }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Kirigami.Units.smallSpacing
        width: Kirigami.Units.iconSizes.smallMedium
        height: width
        radius: width / 2
        color: closeHover.hovered ? "#da4453" : Qt.rgba(0, 0, 0, 0.7)
        visible: thumb.showControls && thumb.window.closeable

        Text {
            anchors.centerIn: parent
            text: "✕"
            color: "white"
        }

        HoverHandler {
            id: closeHover
        }

        TapHandler {
            // takes the click for itself, so that the thumbnail's own handler doesn't activate the window too
            gesturePolicy: TapHandler.WithinBounds
            onTapped: thumb.window.closeWindow()
        }
    }

    HoverHandler {
        id: hover
    }

    // both take the click for themselves, so that the row behind doesn't switch desktops too
    TapHandler {
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: thumb.overviewRoot.activateWindow(thumb.window)
    }

    TapHandler {
        acceptedButtons: Qt.MiddleButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: thumb.window.closeWindow()
    }

    DragHandler {
        target: null
        // don't let the Flickables steal the drag
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onActiveChanged: {
            if (active) {
                thumb.overviewRoot.startDrag(thumb.window, thumb, centroid.scenePressPosition);
            } else {
                thumb.overviewRoot.endDrag();
            }
        }
        onCentroidChanged: {
            if (active) {
                thumb.overviewRoot.moveDrag(centroid.scenePosition);
            }
        }
    }
}
