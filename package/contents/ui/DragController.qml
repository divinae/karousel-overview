import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import Qt5Compat.GraphicalEffects
import "layout.js" as Layout

// dragging a window: the thumbnail following the pointer, and scrolling and switching desktops on the way
Item {
    id: controller

    required property Item overviewRoot

    property QtObject window: null
    // pointer position and its offset from the dragged thumbnail's corner, in the controller's coordinates
    property point position
    property point offset
    // what's under the dragged window, updated by refresh() since the rows also move under a still pointer
    property Item hoveredRow: null
    // another window under the pointer, whose column the dragged window would join
    property QtObject targetWindow: null
    // where dropping creates a new desktop when between two rows, -1 otherwise
    property int hoveredGap: -1
    // what dropping here does, shown next to the dragged window, empty when nothing
    property string dropAction: ""
    // the row showing a hint of what dropping does
    property Item hintRow: null
    // center of the dragged thumbnail, where it gets dropped
    readonly property real centerX: window !== null ? position.x - offset.x + window.frameGeometry.width * overviewRoot.thumbScale / 2 : 0

    signal dropped(QtObject window, point position, real centerX, QtObject targetWindow)

    function start(window, item, scenePosition) {
        const itemPosition = item.mapToItem(controller, 0, 0);
        position = controller.mapFromItem(null, scenePosition.x, scenePosition.y);
        offset = Qt.point(position.x - itemPosition.x, position.y - itemPosition.y);
        controller.window = window;
        refresh();
    }

    function move(scenePosition) {
        position = controller.mapFromItem(null, scenePosition.x, scenePosition.y);
        refresh();
    }

    function end() {
        if (window === null) {
            return;
        }
        refresh();
        const droppedWindow = window;
        const targetWindow = controller.targetWindow;
        reset();
        dropped(droppedWindow, position, position.x, targetWindow);
    }

    // ends the drag without dropping, e.g. when the dragged window or its thumbnail goes away
    function cancel() {
        if (window !== null) {
            reset();
        }
    }

    function reset() {
        setHintRow(null);
        dropAction = "";
        window = null;
        hoveredRow = null;
        targetWindow = null;
        hoveredGap = -1;
    }

    // finds what's under the dragged window
    function refresh() {
        if (window === null) {
            return;
        }
        hoveredRow = overviewRoot.rowAt(position);
        hoveredGap = overviewRoot.gapAt(position);
        // over the middle of another window in the same row the window joins its column,
        // over its sides the column moves before or after it
        targetWindow = null;
        if (hoveredRow !== null && hoveredRow.hasWindow(window)) {
            const thumb = overviewRoot.thumbAt(position);
            if (thumb !== null && thumb.window !== window) {
                const x = thumb.mapFromItem(controller, position.x, position.y).x;
                if (x > thumb.width / 4 && x < thumb.width * 3 / 4) {
                    targetWindow = thumb.window;
                }
            }
        }
        updateHints();
    }

    function setHintRow(row) {
        if (hintRow !== null && hintRow !== row) {
            hintRow.hideHints();
        }
        hintRow = row;
    }

    // shows what dropping here does: the column it joins, where the column goes, or the desktop it moves to
    function updateHints() {
        const row = hoveredRow;
        setHintRow(row);
        if (row === null) {
            dropAction = hoveredGap !== -1 ? "Move to a new desktop here" : "";
            return;
        }
        if (!row.hasWindow(window)) {
            row.showMoveHint();
            dropAction = row.desktop !== null ? "Move to " + row.desktop.name : "Move to a new desktop";
        } else if (targetWindow !== null) {
            row.showStackHint(targetWindow);
            dropAction = "Add to this column";
        } else {
            row.showInsertHint(window, position.x);
            dropAction = isNaN(row.insertHintX) ? "" : "Move column here";
        }
    }

    onHoveredRowChanged: hoverTimer.restart()

    // pushing it against the left or right edge scrolls the row under it
    Timer {
        interval: 16
        repeat: true
        running: controller.window !== null
        onTriggered: {
            const speed = Layout.edgeScrollSpeed(controller.position.x, controller.width, Kirigami.Units.gridUnit * 4);
            if (speed !== 0) {
                controller.hoveredRow?.panBy(-speed * Kirigami.Units.gridUnit * 1.5);
            }
            // the content moves under the pointer while scrolling, also when rows change or Karousel rearranges
            controller.refresh();
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

    // what dropping here does
    Rectangle {
        x: controller.position.x + Kirigami.Units.gridUnit
        y: controller.position.y + Kirigami.Units.gridUnit
        z: 1
        width: actionLabel.implicitWidth + 2 * Kirigami.Units.largeSpacing
        height: actionLabel.implicitHeight + Kirigami.Units.largeSpacing
        radius: height / 2
        color: Kirigami.Theme.highlightColor
        visible: controller.window !== null && controller.dropAction !== ""

        Text {
            id: actionLabel
            anchors.centerIn: parent
            text: controller.dropAction
            color: Kirigami.Theme.highlightedTextColor
        }
    }

    Loader {
        active: controller.window !== null
        x: controller.position.x - controller.offset.x
        y: controller.position.y - controller.offset.y
        sourceComponent: KWinComponents.WindowThumbnail {
            id: ghost
            wId: controller.window.internalId
            width: controller.window.frameGeometry.width * controller.overviewRoot.thumbScale
            height: controller.window.frameGeometry.height * controller.overviewRoot.thumbScale
            opacity: 0.8
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: ghost.width
                    height: ghost.height
                    radius: controller.overviewRoot.windowRadius
                }
            }
        }
    }
}
