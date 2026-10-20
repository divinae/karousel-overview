import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import "layout.js" as Layout

// dragging a window: the thumbnail following the pointer, and scrolling and switching desktops on the way
Item {
    id: controller

    required property Item overviewRoot

    property QtObject window: null
    // pointer position and its offset from the dragged thumbnail's corner, in the controller's coordinates
    property point position
    property point offset
    readonly property Item hoveredRow: window !== null ? overviewRoot.rowAt(position) : null

    signal dropped(QtObject window, point position, real centerX)

    function start(window, item, scenePosition) {
        const itemPosition = item.mapToItem(controller, 0, 0);
        position = controller.mapFromItem(null, scenePosition.x, scenePosition.y);
        offset = Qt.point(position.x - itemPosition.x, position.y - itemPosition.y);
        controller.window = window;
    }

    function move(scenePosition) {
        position = controller.mapFromItem(null, scenePosition.x, scenePosition.y);
    }

    function end() {
        const window = controller.window;
        controller.window = null;
        if (window !== null) {
            dropped(window, position, position.x - offset.x + window.frameGeometry.width * overviewRoot.thumbScale / 2);
        }
    }

    // pushing it against the left or right edge scrolls the row under it
    Timer {
        interval: 16
        repeat: true
        running: controller.window !== null
        onTriggered: {
            const speed = Layout.edgeScrollSpeed(controller.position.x, controller.width, Kirigami.Units.gridUnit * 4);
            if (speed !== 0) {
                controller.hoveredRow?.scrollBy(speed * Kirigami.Units.gridUnit * 1.5);
            }
        }
    }

    // pushing it against the top or bottom edge moves between rows
    Timer {
        interval: 500
        repeat: true
        running: controller.window !== null
        onTriggered: {
            const zone = Kirigami.Units.gridUnit * 3;
            if (controller.position.y < zone) {
                controller.overviewRoot.showRow(-1);
            } else if (controller.position.y > controller.height - zone) {
                controller.overviewRoot.showRow(1);
            }
        }
    }

    // holding it over another desktop switches to that desktop
    onHoveredRowChanged: hoverTimer.restart()
    Timer {
        id: hoverTimer
        interval: 700
        onTriggered: {
            const row = controller.hoveredRow;
            if (row !== null && row.desktop !== null) {
                controller.overviewRoot.switchToDesktopKeepingOverview(row);
            }
        }
    }

    Loader {
        active: controller.window !== null
        x: controller.position.x - controller.offset.x
        y: controller.position.y - controller.offset.y
        sourceComponent: KWinComponents.WindowThumbnail {
            wId: controller.window.internalId
            width: controller.window.frameGeometry.width * controller.overviewRoot.thumbScale
            height: controller.window.frameGeometry.height * controller.overviewRoot.thumbScale
            opacity: 0.8
        }
    }
}
