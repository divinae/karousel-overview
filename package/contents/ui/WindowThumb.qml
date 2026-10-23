pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import "i18n.js" as I18n

Item {
    id: thumb

    required property var window
    required property DesktopRow strip
    required property OverviewScreen overviewRoot

    // Karousel's layout, also on desktops that aren't current, see OverviewScreen's geometryOf
    readonly property var slot: overviewRoot.slotOf(window, strip)
    readonly property rect geometry: slot ?? overviewRoot.layoutGeometryOf(window)
    readonly property bool selected: overviewRoot.selectedWindow === window
    readonly property bool dropTarget: overviewRoot.dropTargetWindow === window
    readonly property bool closing: overviewRoot.closing
    readonly property bool showControls: hover.hovered && overviewRoot.draggedWindow === null && overviewRoot.zoom === 1 && !closing

    // on each side, what makes the gaps between the shrunk windows as big as Karousel's are on screen,
    // grows with the zoom so that the zoom animation starts with windows at their real positions
    readonly property real restingInsetX: Math.min(overviewRoot.horizontalGap * (1 - strip.thumbScale) / 2, geometry.width * strip.thumbScale / 4)
    readonly property real restingInsetY: Math.min(overviewRoot.verticalGap * (1 - strip.thumbScale) / 2, geometry.height * strip.thumbScale / 4)
    readonly property real insetX: overviewRoot.zoom * restingInsetX
    readonly property real insetY: overviewRoot.zoom * restingInsetY

    // where the thumbnail goes, x and width follow it with an animation
    readonly property real layoutX: strip.toStripX(geometry.x) + insetX
    readonly property real layoutWidth: geometry.width * strip.thumbScale - 2 * insetX
    // where the thumbnail stays, without its inset, while Karousel's view is synced to the preview, NaN when it follows the window
    property real heldX: NaN

    // the inset keeps following the zoom, e.g. while it zooms into a clicked window; then it also glides to where the
    // window really is, for windows that Karousel doesn't move with the others, like ones it doesn't tile
    x: strip.syncingScroll && !isNaN(heldX) ? heldX + insetX + (layoutX - insetX - heldX) * strip.settleBlend : layoutX
    y: (geometry.y - strip.screenGeometry.y) * strip.thumbScale + insetY
    width: layoutWidth
    height: geometry.height * strip.thumbScale - 2 * insetY
    z: window.stackingOrder
    // minimized windows are shown after the strip instead, see DesktopRow
    visible: window.normalWindow && !window.minimized && (!overviewRoot.multipleScreens || window.output === overviewRoot.targetScreen)
    // a window that shows up while the view is synced has no place among the held thumbnails yet
    opacity: strip.syncingScroll && isNaN(heldX) ? 0 : overviewRoot.draggedWindows.includes(window) ? 0.3 : 1

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

    // how far the window seems to float above its desktop, higher when hovered or selected, like the desktops
    property real elevation: selected ? 2 : hover.hovered && overviewRoot.draggedWindow === null ? 1.5 : 1
    Behavior on elevation {
        NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
    }

    // only the shadow, cast downwards, the windows float higher than their desktop, even the selected one;
    // real windows have their own, so it fades in with the zoom
    Kirigami.ShadowedRectangle {
        anchors.fill: parent
        color: "transparent"
        radius: thumb.overviewRoot.windowRadius
        shadow.size: Kirigami.Units.gridUnit * (1.5 + 0.75 * thumb.elevation)
        shadow.yOffset: Kirigami.Units.gridUnit * (0.3 + 0.25 * thumb.elevation)
        shadow.color: Qt.rgba(0, 0, 0, 0.25 + 0.1 * thumb.elevation)
        opacity: thumb.overviewRoot.zoom
    }

    // the window and the blur behind it, with rounded corners; rendered twice as large as shown, so that shrinking it
    // averages pixels and small text stays whole instead of losing pixels, mipmaps would blur it;
    // without rounding, at the ends of the zoom, the window is drawn at its full resolution
    Item {
        anchors.fill: parent
        layer.enabled: thumb.overviewRoot.windowRadius > 0
        layer.textureSize: thumb.overviewRoot.thumbTextureSize(thumb.geometry.width * thumb.strip.thumbScale - 2 * thumb.restingInsetX,
                                                               thumb.geometry.height * thumb.strip.thumbScale - 2 * thumb.restingInsetY)
        layer.smooth: true
        layer.effect: RoundedCorners {
            radius: thumb.overviewRoot.windowRadius
        }

        // thumbnails don't get KWin's blur behind translucent windows, so blur the part of the wallpaper behind them,
        // outside the wallpaper its edge is stretched
        FastBlur {
            anchors.fill: parent
            // the row can go away before its thumbnails, when its desktop is removed
            visible: thumb.overviewRoot.config.BlurBehindWindows && thumb.strip !== null && thumb.strip.desktop !== null && thumb.slot === null
            // FastBlur's largest radius, on a texture of half the size, so it's as strong as KWin's blur
            radius: 64
            source: ShaderEffectSource {
                sourceItem: thumb.strip?.wallpaperBackground ?? null
                sourceRect: thumb.strip === null ? Qt.rect(0, 0, 0, 0) : Qt.rect((thumb.x - thumb.strip.contentX - thumb.strip.cardLeft) / thumb.strip.thumbScale,
                                    thumb.y / thumb.strip.thumbScale,
                                    thumb.width / thumb.strip.thumbScale,
                                    thumb.height / thumb.strip.thumbScale)
                textureSize: Qt.size(Math.max(1, thumb.width / 2), Math.max(1, thumb.height / 2))
                wrapMode: ShaderEffectSource.ClampToEdge
            }
        }

        // shown in its column's place, a screen's worth of window in a column: dark around it like a screen, not the
        // wallpaper, the window keeps its proportions in the middle
        Rectangle {
            anchors.fill: parent
            visible: thumb.slot !== null
            color: Qt.rgba(0, 0, 0, 0.6)
        }

        KWinComponents.WindowThumbnail {
            anchors.fill: parent
            wId: thumb.window.internalId
        }
    }

    // the half of the window a dragged one drops onto, on the side where it goes, or its middle when they get stacked
    Rectangle {
        readonly property string zone: thumb.overviewRoot.dropZoneWindow === thumb.window ? thumb.overviewRoot.dropZone : ""
        readonly property real inset: zone === "center" ? Math.min(parent.width, parent.height) * 0.15 : 0

        x: zone === "right" ? parent.width / 2 : inset
        y: zone === "bottom" ? parent.height / 2 : inset
        width: zone === "left" || zone === "right" ? parent.width / 2 : parent.width - 2 * inset
        height: zone === "top" || zone === "bottom" ? parent.height / 2 : parent.height - 2 * inset
        radius: thumb.overviewRoot.windowRadius
        color: thumb.overviewRoot.style.highlightAlpha(0.4)
        border.width: 2
        border.color: Kirigami.Theme.highlightColor
        visible: zone !== ""
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        color: "transparent"
        radius: thumb.overviewRoot.windowRadius + 3
        border.width: thumb.dropTarget ? 6 : 3
        border.color: Kirigami.Theme.highlightColor
        // while dragging, only the window the dragged one would join is highlighted, not every one passed over
        visible: thumb.selected || thumb.dropTarget || (hover.hovered && thumb.overviewRoot.draggedWindow === null)
        opacity: (thumb.selected || thumb.dropTarget ? 1 : 0.5) * thumb.overviewRoot.zoom
    }

    // app icon and window title, each can be turned off in the settings, the title also shows on hover
    Rectangle {
        id: label

        readonly property bool showIcon: thumb.overviewRoot.config.ShowIcons
        readonly property bool showTitle: thumb.overviewRoot.config.ShowTitles || thumb.showControls
        readonly property real maxWidth: thumb.width - 2 * Kirigami.Units.smallSpacing

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        width: Math.min(info.implicitWidth, maxWidth) + 2 * Kirigami.Units.smallSpacing
        height: info.implicitHeight + Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: Qt.rgba(0, 0, 0, 0.7)
        visible: (showIcon || showTitle) && !thumb.closing
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
                visible: label.showIcon
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, label.maxWidth - (label.showIcon ? Kirigami.Units.iconSizes.small + parent.spacing : 0))
                text: thumb.window.caption
                elide: Text.ElideRight
                color: "white"
                visible: label.showTitle
            }
        }
    }

    // fullscreen or maximized, shown in its column's place, see OverviewScreen.slotOf; at the top in the middle,
    // between the column's Stack button and the close button, the title is at the bottom; only the icon when narrow
    Rectangle {
        id: fillsBadge
        // the text's own width, the row's changes with it
        readonly property real fullWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing + badgeText.implicitWidth
        readonly property bool showText: thumb.width > fullWidth + 2 * Kirigami.Units.iconSizes.smallMedium + 6 * Kirigami.Units.smallSpacing
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Kirigami.Units.smallSpacing
        width: (showText ? fullWidth : Kirigami.Units.iconSizes.small) + 2 * Kirigami.Units.largeSpacing
        height: Kirigami.Units.iconSizes.smallMedium
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.7)
        visible: thumb.slot !== null && !thumb.closing
        opacity: thumb.overviewRoot.zoom

        Accessible.role: Accessible.StaticText
        Accessible.name: badgeText.text

        Row {
            id: badgeRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: Kirigami.Units.iconSizes.small
                height: width
                source: "view-fullscreen"
                color: "white"
                isMask: true
            }

            Text {
                id: badgeText
                anchors.verticalCenter: parent.verticalCenter
                text: thumb.window.fullScreen ? I18n.tr("Fullscreen") : I18n.tr("Maximized")
                color: "white"
                visible: fillsBadge.showText
            }
        }
    }

    Rectangle {
        id: closeButton
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Kirigami.Units.smallSpacing
        width: Kirigami.Units.iconSizes.smallMedium
        height: width
        radius: width / 2
        color: closeHover.hovered ? "#da4453" : Qt.rgba(0, 0, 0, 0.7)
        visible: thumb.showControls && thumb.window.closeable

        Accessible.role: Accessible.Button
        Accessible.name: I18n.trc("@action:button a window", "Close")

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

    // left of the close button: Karousel stops tiling the window, or tiles it again
    Rectangle {
        anchors.top: parent.top
        anchors.right: closeButton.visible ? closeButton.left : parent.right
        anchors.margins: Kirigami.Units.smallSpacing
        width: Kirigami.Units.iconSizes.smallMedium
        height: width
        radius: width / 2
        color: floatHover.hovered ? Kirigami.Theme.highlightColor : Qt.rgba(0, 0, 0, 0.7)
        visible: thumb.showControls && thumb.overviewRoot.karousel.available

        Accessible.role: Accessible.Button
        Accessible.name: I18n.tr("Toggle floating")

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.small
            height: width
            source: "window-restore"
            color: "white"
            isMask: true
        }

        HoverHandler {
            id: floatHover
        }

        TapHandler {
            gesturePolicy: TapHandler.WithinBounds
            onTapped: thumb.overviewRoot.karousel.toggleFloating(thumb.window)
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
        // don't let the Flickables steal the drag, but don't take it from a column's grip strip, which a floating window
        // can lie over, that would drop the column and move the window instead
        grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
            | PointerHandler.ApprovesTakeOverByHandlersOfSameType
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
