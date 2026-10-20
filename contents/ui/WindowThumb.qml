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

    x: strip.toStripX(geometry.x)
    y: (geometry.y - strip.screenGeometry.y) * strip.thumbScale
    width: geometry.width * strip.thumbScale
    height: geometry.height * strip.thumbScale
    z: window.stackingOrder
    visible: window.normalWindow
    opacity: overviewRoot.draggedWindow === window ? 0.3 : 1

    onGeometryChanged: strip.updateBounds()

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
        opacity: thumb.selected ? 1 : 0.5
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        width: Math.min(caption.implicitWidth, thumb.width) + 2 * Kirigami.Units.smallSpacing
        height: caption.implicitHeight + Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: Qt.rgba(0, 0, 0, 0.7)
        visible: hover.hovered && thumb.overviewRoot.draggedWindow === null

        Text {
            id: caption
            anchors.centerIn: parent
            width: Math.min(implicitWidth, thumb.width)
            text: thumb.window.caption
            elide: Text.ElideRight
            color: "white"
        }
    }

    HoverHandler {
        id: hover
    }

    TapHandler {
        onTapped: thumb.overviewRoot.activateWindow(thumb.window)
    }

    DragHandler {
        id: drag
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
