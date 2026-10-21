pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kwin as KWinComponents

// something dragged from an app, e.g. a file: KWin keeps the pointer's events from the overview, only its position
// reaches it. Holding it over a window activates that window, to drop it there, over the minimap's card it shows
// that desktop's row
Item {
    id: externalDrag

    required property OverviewScreen overviewRoot

    property bool active: false
    property var window: null
    // the minimap's card under it, not the one for a new desktop, -1 when none
    property int card: -1

    function update() {
        const cursor = KWinComponents.Workspace.cursorPos;
        const point = Qt.point(cursor.x - overviewRoot.screenGeometry.x, cursor.y - overviewRoot.screenGeometry.y);
        // the pointer's own events would have reached the overview by now, see onCursorPosChanged
        if (pointerHover.hovered || overviewRoot.draggedWindow !== null || !overviewRoot.sceneEffect.activated || overviewRoot.activating
                || point.x < 0 || point.y < 0 || point.x >= overviewRoot.width || point.y >= overviewRoot.height) {
            end();
            return;
        }
        active = true;
        const target = targetAt(point);
        if (target.window !== window || target.card !== card) {
            window = target.window;
            card = target.card;
            timer.restart();
        }
    }

    // the window or the minimap's card, not the one for a new desktop, under a point
    function targetAt(point) {
        const index = overviewRoot.minimapIndexAt(point);
        return {
            card: index < KWinComponents.Workspace.desktops.length ? index : -1,
            window: index === -1 ? overviewRoot.thumbAt(point)?.window ?? null : null,
        };
    }

    function end() {
        timer.stop();
        active = false;
        window = null;
        card = -1;
    }

    Timer {
        id: timer
        interval: 600
        onTriggered: {
            // what's under the still pointer can have changed meanwhile, e.g. the minimap slid in under it
            const cursor = KWinComponents.Workspace.cursorPos;
            const target = externalDrag.targetAt(Qt.point(cursor.x - externalDrag.overviewRoot.screenGeometry.x, cursor.y - externalDrag.overviewRoot.screenGeometry.y));
            if (target.window !== externalDrag.window || target.card !== externalDrag.card) {
                externalDrag.window = target.window;
                externalDrag.card = target.card;
                restart();
                return;
            }
            if (externalDrag.window !== null && KWinComponents.Workspace.windows.includes(externalDrag.window)) {
                const window = externalDrag.window;
                externalDrag.end();
                externalDrag.overviewRoot.activateWindow(window);
            } else if (externalDrag.card !== -1) {
                externalDrag.overviewRoot.goToRow(externalDrag.card);
            }
        }
    }

    HoverHandler {
        id: pointerHover
        onHoveredChanged: {
            if (hovered) {
                externalDrag.end();
            }
        }
    }

    Connections {
        target: KWinComponents.Workspace
        // after the overview had the event, if it was the pointer's own
        function onCursorPosChanged() {
            // most moves are the pointer's own, over the overview
            if (externalDrag.active || !pointerHover.hovered) {
                Qt.callLater(externalDrag.update);
            }
        }
    }
}
