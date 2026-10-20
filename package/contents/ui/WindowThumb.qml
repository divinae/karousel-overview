import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

Item {
    id: thumb

    required property QtObject window
    required property Item strip
    required property Item overviewRoot

    readonly property rect geometry: window.frameGeometry
    readonly property bool selected: overviewRoot.selectedWindow === window
    readonly property bool showControls: hover.hovered && overviewRoot.draggedWindow === null && overviewRoot.zoom === 1

    // half of the gap between windows, Karousel's own gaps get too small when zoomed out,
    // grows with the zoom so that the zoom animation starts with windows at their real positions
    readonly property real inset: overviewRoot.zoom * Math.min(effect.configuration.WindowGap / 2, geometry.width * strip.thumbScale / 4, geometry.height * strip.thumbScale / 4)

    x: strip.toStripX(geometry.x) + inset
    y: (geometry.y - strip.screenGeometry.y) * strip.thumbScale + inset
    width: geometry.width * strip.thumbScale - 2 * inset
    height: geometry.height * strip.thumbScale - 2 * inset
    z: window.stackingOrder
    visible: window.normalWindow && (!overviewRoot.multipleScreens || window.output === overviewRoot.targetScreen)
    opacity: overviewRoot.draggedWindow === window ? 0.3 : 1

    onGeometryChanged: {
        strip.updateBounds();
        if (selected) {
            strip.ensureVisible(thumb);
        }
    }
    onVisibleChanged: strip.updateBounds()

    KWinComponents.WindowThumbnail {
        anchors.fill: parent
        wId: thumb.window.internalId
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        color: "transparent"
        radius: Kirigami.Units.cornerRadius
        border.width: 3
        border.color: Kirigami.Theme.highlightColor
        visible: thumb.selected || hover.hovered
        opacity: (thumb.selected ? 1 : 0.5) * thumb.overviewRoot.zoom
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        width: Math.min(caption.implicitWidth, thumb.width) + 2 * Kirigami.Units.smallSpacing
        height: caption.implicitHeight + Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: Qt.rgba(0, 0, 0, 0.7)
        visible: thumb.showControls

        Text {
            id: caption
            anchors.centerIn: parent
            width: Math.min(implicitWidth, thumb.width)
            text: thumb.window.caption
            elide: Text.ElideRight
            color: "white"
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
            onTapped: thumb.window.closeWindow()
        }
    }

    HoverHandler {
        id: hover
    }

    TapHandler {
        onTapped: thumb.overviewRoot.activateWindow(thumb.window)
    }

    TapHandler {
        acceptedButtons: Qt.MiddleButton
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
