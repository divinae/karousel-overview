pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import "layout.js" as Layout
import "i18n.js" as I18n

// dragging a window: the thumbnail following the pointer, and scrolling and switching desktops on the way
Item {
    id: controller

    required property OverviewScreen overviewRoot

    property var window: null
    // pointer position and its offset from the dragged thumbnail's corner, in the controller's coordinates
    property point position
    property point offset
    // what's under the dragged window, updated by refresh() since the rows also move under a still pointer
    property DesktopRow hoveredRow: null
    // another window under the pointer, whose column the dragged window would join
    property var targetWindow: null
    // another window under the pointer's left or right side, beside which the dragged window would get a column of its own
    property var tileWindow: null
    // which side of targetWindow or tileWindow: above or left -1, below or right 1
    property int side: 0
    // over targetWindow's middle: the column it joins gets Karousel's stacked layout, otherwise its windows are one under another
    property bool stacked: false
    // the windows of the column that moves as a whole, between the columns, when dragged by its handle, from top to
    // bottom; empty when only the window moves
    property var columnWindows: []
    readonly property bool wholeColumn: columnWindows.length > 0
    // the column's windows of the last drag, kept for the drop, after reset
    property var lastColumnWindows: []
    // where dropping creates a new desktop when between two rows, -1 otherwise
    property int hoveredGap: -1
    // over the desktop minimap, and its card under the dragged window, the last one is for a new desktop
    property bool overMinimap: false
    property int minimapIndex: -1
    // what dropping here does, shown next to the dragged window, empty when nothing
    property string dropAction: ""
    // the row showing a hint of what dropping does
    property DesktopRow hintRow: null

    // minimapIndex is the minimap's card it's dropped on, -1 between its cards, -2 when not over the minimap
    // dropX is the pointer's, where the column goes among the others
    signal dropped(QtObject window, point position, real dropX, QtObject targetWindow, QtObject tileWindow, int side, bool stacked, bool wholeColumn, int minimapIndex)

    function start(window, item, scenePosition, columnWindows) {
        controller.columnWindows = columnWindows;
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
        // Karousel can't move a whole column there
        if (wholeColumn && dropAction === "") {
            reset();
            return;
        }
        const droppedWindow = window;
        lastColumnWindows = columnWindows;
        const targetWindow = controller.targetWindow;
        const tileWindow = controller.tileWindow;
        const side = controller.side;
        const stacked = controller.stacked;
        const columnDropped = controller.wholeColumn;
        // the minimap hides once nothing is dragged
        const minimapIndex = overMinimap ? controller.minimapIndex : -2;
        reset();
        dropped(droppedWindow, position, position.x, targetWindow, tileWindow, side, stacked, columnDropped, minimapIndex);
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
        tileWindow = null;
        side = 0;
        hoveredGap = -1;
        columnWindows = [];
        lastState = null;
        overMinimap = false;
        minimapIndex = -1;
    }

    // finds what's under the dragged window
    function refresh() {
        if (window === null) {
            return;
        }
        lastState = dragState();
        // the row under it works out its columns once for all that's checked here
        const row = overviewRoot.rowAt(position);
        row?.cacheColumns(true);
        try {
            update();
        } finally {
            row?.cacheColumns(false);
        }
    }

    // what refresh depends on: where the dragged window is, and what's under it, which also moves under a still
    // pointer, e.g. while the rows scroll, a row pans or Karousel rearranges
    property var lastState: null
    function dragState() {
        const row = overviewRoot.rowAt(position);
        const thumb = row !== null ? overviewRoot.thumbAt(position) : null;
        return {
            x: position.x, y: position.y, row: row, columns: row?.columns ?? null, contentX: row?.contentX ?? 0,
            rows: overviewRoot.rowsPosition, minimap: overviewRoot.minimapShown, desktop: overviewRoot.activeDesktop,
            desktops: KWinComponents.Workspace.desktops.length, thumb: thumb,
            thumbRect: thumb !== null ? [thumb.x, thumb.y, thumb.width, thumb.height].join() : "",
        };
    }

    function changed() {
        const now = dragState();
        return lastState === null || Object.keys(now).some(key => now[key] !== lastState[key]);
    }

    function update() {
        // over the minimap only its cards are targets, not the rows behind it
        overMinimap = overviewRoot.minimapContains(position);
        minimapIndex = overviewRoot.minimapIndexAt(position);
        if (overMinimap) {
            hoveredRow = null;
            hoveredGap = -1;
            targetWindow = null;
            tileWindow = null;
            setHintRow(null);
            const desktops = KWinComponents.Workspace.desktops;
            dropAction = minimapIndex === -1 || (minimapIndex < desktops.length && overviewRoot.isOnDesktop(window, desktops[minimapIndex])) ? ""
                : wholeColumn && !overviewRoot.desktopActions.canMoveColumnTo(minimapIndex) ? ""
                : minimapIndex === desktops.length ? (wholeColumn ? I18n.tr("Move column to a new desktop") : I18n.tr("Move to a new desktop"))
                : wholeColumn ? I18n.tr("Move column to %1", desktops[minimapIndex].name) : I18n.tr("Move to %1", desktops[minimapIndex].name);
            return;
        }
        hoveredRow = overviewRoot.rowAt(position);
        hoveredGap = overviewRoot.gapAt(position);
        // over the middle of another window in the same row the window gets stacked with it, over its top or bottom it
        // joins its column above or below it, over its left or right side it gets a column of its own there, between
        // windows its whole column moves there; a whole column does the same with all of its windows, on its desktop
        targetWindow = null;
        tileWindow = null;
        if (hoveredRow !== null && (wholeColumn ? hoveredRow.hasWindow(window) : hoveredRow.placesWindow(window))) {
            const thumb = overviewRoot.thumbAt(position);
            if (thumb !== null && thumb.window !== window && !columnWindows.includes(thumb.window)) {
                // the window's sides, top and bottom, or middle, see Layout.dropZone; the middle stacks only where
                // Karousel can, a window that shares a column that isn't stacked has its top and bottom halves instead
                const point = thumb.mapFromItem(controller, position.x, position.y);
                const zone = Layout.dropZone(point.x / thumb.width - 0.5, point.y / thumb.height - 0.5, hoveredRow.canStackWith(thumb.window));
                side = zone.side;
                stacked = zone.kind === "stack";
                if (zone.kind === "tile") {
                    tileWindow = thumb.window;
                } else {
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
            dropAction = hoveredGap === -1 ? "" : !wholeColumn ? I18n.tr("Move to a new desktop here")
                : overviewRoot.desktopActions.canMoveColumnTo(KWinComponents.Workspace.desktops.length) ? I18n.tr("Move column to a new desktop here") : "";
            return;
        }
        if (!row.hasWindow(window) && wholeColumn) {
            // Karousel puts it at the end of that desktop
            const index = row.desktop !== null ? KWinComponents.Workspace.desktops.indexOf(row.desktop) : KWinComponents.Workspace.desktops.length;
            if (overviewRoot.desktopActions.canMoveColumnTo(index)) {
                row.showMoveHint();
                dropAction = row.desktop !== null ? I18n.tr("Move column to %1", row.desktop.name) : I18n.tr("Move column to a new desktop");
            } else {
                row.hideHints();
                dropAction = "";
            }
        } else if (!row.placesWindow(window)) {
            // holding it there makes that desktop current, then it can be put at a place in it
            row.showMoveHint();
            dropAction = row.desktop !== null ? I18n.tr("Move to %1, hold to place it", row.desktop.name) : I18n.tr("Move to a new desktop");
        } else if (targetWindow !== null) {
            dropAction = !row.showStackHint(window, targetWindow, side, stacked) ? "" : stacked ? I18n.tr("Stack together")
                : side < 0 ? I18n.tr("Above in this column") : I18n.tr("Below in this column");
        } else if (tileWindow !== null) {
            dropAction = !row.showTileHint(window, tileWindow, side, wholeColumn) ? ""
                : wholeColumn ? (side < 0 ? I18n.tr("Column on the left") : I18n.tr("Column on the right"))
                : side < 0 ? I18n.tr("Own column on the left") : I18n.tr("Own column on the right");
        } else {
            row.showInsertHint(window, position.x, wholeColumn);
            dropAction = isNaN(row.insertHintX) ? "" : !wholeColumn && row.sharesColumn(window) ? I18n.tr("Own column here") : I18n.tr("Move column here");
        }
    }

    onHoveredRowChanged: hoverTimer.restart()

    // pushing it against the left or right edge scrolls the row under it
    Timer {
        interval: 16
        repeat: true
        running: controller.window !== null
        onTriggered: {
            // over the minimap its cards are the targets, beside it the zone ends where it starts
            const right = controller.overviewRoot.scrollEdgeRight(controller.position);
            const speed = controller.overMinimap ? 0 : Layout.edgeScrollSpeed(controller.position.x, right, Kirigami.Units.gridUnit * 4);
            if (speed !== 0) {
                controller.hoveredRow?.panBy(-speed * Kirigami.Units.gridUnit * 1.5);
            }
            // the content moves under the pointer while scrolling, also when rows change or Karousel rearranges
            if (speed !== 0 || controller.changed()) {
                controller.refresh();
            }
        }
    }

    // pushing it against the top or bottom edge moves between rows
    Timer {
        interval: 500
        repeat: true
        running: controller.window !== null
        onTriggered: {
            // aiming at the minimap's cards near the edges
            if (controller.overMinimap) {
                return;
            }
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
            // a whole column goes to the end of the other desktop anyway
            if (row !== null && row.desktop !== null && !controller.wholeColumn) {
                controller.overviewRoot.switchToDesktopKeepingOverview(row);
            }
        }
    }

    // what dropping here does, left of the pointer when it wouldn't fit on its right, e.g. over the minimap
    Rectangle {
        x: controller.position.x + Kirigami.Units.gridUnit + width <= controller.width
            ? controller.position.x + Kirigami.Units.gridUnit : controller.position.x - Kirigami.Units.gridUnit - width
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

    // over the minimap the dragged window shrinks around the pointer, so that it doesn't hide the cards
    property real ghostScale: overMinimap ? 0.3 : 1
    Behavior on ghostScale {
        NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
    }

    // the dragged window, or the whole column, at their places relative to the window
    Item {
        visible: controller.window !== null
        x: controller.position.x - controller.offset.x
        y: controller.position.y - controller.offset.y
        transform: Scale {
            origin.x: controller.offset.x
            origin.y: controller.offset.y
            xScale: controller.ghostScale
            yScale: controller.ghostScale
        }

        Repeater {
            model: controller.window === null ? [] : controller.wholeColumn ? controller.columnWindows : [controller.window]

            KWinComponents.WindowThumbnail {
                required property var modelData
                readonly property rect geometry: controller.overviewRoot.geometryOf(modelData)
                // the window goes away first when the drag ends
                readonly property rect origin: controller.window !== null ? controller.overviewRoot.geometryOf(controller.window) : Qt.rect(0, 0, 0, 0)

                x: (geometry.x - origin.x) * controller.overviewRoot.thumbScale
                y: (geometry.y - origin.y) * controller.overviewRoot.thumbScale
                z: modelData.stackingOrder
                wId: modelData.internalId
                width: geometry.width * controller.overviewRoot.thumbScale
                height: geometry.height * controller.overviewRoot.thumbScale
                opacity: 0.8
                layer.enabled: true
                // larger like the other thumbnails, see WindowThumb
                layer.textureSize: controller.overviewRoot.thumbTextureSize(width, height)
                layer.smooth: true
                layer.effect: RoundedCorners {
                    radius: controller.overviewRoot.windowRadius
                }
            }
        }
    }
}
