pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kwin as KWinComponents
import "layout.js" as Layout

// creating and switching desktops, and moving windows and columns to them, also by dropping them there
QtObject {
    id: actions

    required property OverviewScreen overviewRoot

    // desktops created here while the setting is on are temporary, removed again once empty, see removeEmptyDesktops
    function createDesktop(position = KWinComponents.Workspace.desktops.length) {
        KWinComponents.Workspace.createDesktop(position, "");
        const desktops = KWinComponents.Workspace.desktops;
        const desktop = desktops[position];
        if (overviewRoot.config.RemoveEmptyDesktops) {
            const ids = desktops.map(desktop => desktop.id);
            overviewRoot.sceneEffect.temporaryDesktops = overviewRoot.sceneEffect.temporaryDesktops.filter(id => ids.includes(id)).concat([desktop.id]);
        }
        return desktop;
    }

    function switchToDesktop(desktop) {
        if (desktop === null) {
            desktop = createDesktop();
        }
        if (desktop !== overviewRoot.currentDesktop()) {
            KWinComponents.Workspace.setCurrentDesktopForScreen(desktop, overviewRoot.targetScreen);
        }
        overviewRoot.sceneEffect.deactivate();
    }

    // a normal window on the desktop, in the current activity or all of them, on this screen; what the desktop's row shows
    function belongsTo(window, desktop) {
        return window.normalWindow && window.desktops.length === 1 && window.desktops[0] === desktop
            && (window.activities.length === 0 || window.activities.includes(KWinComponents.Workspace.currentActivity))
            && (!overviewRoot.multipleScreens || window.output === overviewRoot.targetScreen);
    }

    // Karousel has key bindings that move a whole column for the first twelve desktops, index is the desktop's, the
    // number of desktops for a new one
    function canMoveColumnTo(index) {
        return index < 12;
    }

    // a whole column, its windows given from top to bottom, through Karousel, which keeps it together and puts it at the
    // end of the desktop's strip
    function moveColumnToDesktop(windows, desktop) {
        const index = KWinComponents.Workspace.desktops.indexOf(desktop);
        if (index === -1 || !canMoveColumnTo(index) || windows.length === 0) {
            return;
        }
        rememberAtEnd(windows, desktop);
        overviewRoot.focusWindow(windows[0]);
        overviewRoot.karousel.invoke([Layout.KarouselShortcuts.columnMoveToDesktop + (index + 1)]);
        Qt.callLater(overviewRoot.refreshSelection);
    }

    // the overview stays where it is; Karousel only lays out the current desktop, it adds the window as a column at the
    // end of the desktop's strip once that desktop is current, or puts it in the middle of an empty one, so it's shown
    // there until then, see main.qml's layouts
    function moveWindowToDesktop(window, desktop) {
        // before it moves, its thumbnail on the other desktop reads it right away
        rememberAtEnd([window], desktop);
        window.desktops = [desktop];
        // once the rows have caught up
        Qt.callLater(overviewRoot.refreshSelection);
    }

    // where windows moved to another desktop show there until Karousel lays them out, which it does only for the current
    // desktop: as a column at the end of its strip, as tall as the others there, its windows stacked or one under another
    // as they were; also what tells them from floating windows, see DesktopRow.isFloating
    function rememberAtEnd(windows, desktop) {
        const others = KWinComponents.Workspace.windows.filter(other => !windows.includes(other) && !other.minimized && belongsTo(other, desktop))
            .map(other => overviewRoot.geometryOf(other));
        const geometries = windows.map(window => overviewRoot.geometryOf(window));
        const left = Math.min(...geometries.map(geometry => geometry.x));
        const top = Math.min(...geometries.map(geometry => geometry.y));
        const width = Math.max(...geometries.map(geometry => geometry.x + geometry.width)) - left;
        const height = Math.max(...geometries.map(geometry => geometry.y + geometry.height)) - top;
        const area = KWinComponents.Workspace.clientArea(KWinComponents.Workspace.MaximizeArea, overviewRoot.targetScreen, desktop);
        const place = Layout.placeAtEnd(others, area, width, overviewRoot.horizontalGap);
        const scale = height > 0 ? place.height / height : 1;
        windows.forEach((window, i) => {
            const geometry = geometries[i];
            overviewRoot.sceneEffect.layouts[overviewRoot.sceneEffect.layoutKey(window)] = {
                geometry: Qt.rect(place.x + geometry.x - left, place.y + (geometry.y - top) * scale, geometry.width, geometry.height * scale),
                desktop: desktop.id,
            };
        });
    }

    // what a dragged window does when dropped, see DragController: columnWindows are its column's when the whole column
    // was dragged by its grip, dropX is the pointer's
    function dropWindow(window, position, dropX, targetWindow, tileWith, side, stacked, columnWindows, minimapIndex) {
        const wholeColumn = columnWindows.length > 0;
        const karousel = overviewRoot.karousel;
        // a whole column moves with Karousel's key bindings
        const move = desktop => {
            if (wholeColumn) {
                moveColumnToDesktop(columnWindows, desktop);
            } else {
                moveWindowToDesktop(window, desktop);
            }
        };
        // over the minimap only its cards are targets, not the rows behind it
        if (minimapIndex !== -2) {
            const desktops = KWinComponents.Workspace.desktops;
            if (minimapIndex === desktops.length) {
                move(createDesktop());
            } else if (minimapIndex !== -1 && !overviewRoot.isOnDesktop(window, desktops[minimapIndex])) {
                move(desktops[minimapIndex]);
            }
            return;
        }
        const row = overviewRoot.rowAt(position);
        if (wholeColumn && row !== null && row.hasWindow(window)) {
            if (targetWindow !== null && row.hasWindow(targetWindow)) {
                karousel.mergeColumn(columnWindows, targetWindow, side, stacked, row);
            } else if (tileWith !== null && row.hasWindow(tileWith)) {
                karousel.tileColumn(window, tileWith, side, row);
            } else {
                row.reorderColumn(window, dropX, true);
            }
            return;
        }
        if (!wholeColumn && row !== null && row.placesWindow(window)) {
            if (targetWindow !== null && row.hasWindow(targetWindow)) {
                karousel.stackWindow(window, targetWindow, side, stacked, row);
            } else if (tileWith !== null && row.hasWindow(tileWith)) {
                karousel.tileWindow(window, tileWith, side, row);
            } else {
                row.reorderColumn(window, dropX, false);
            }
            return;
        }

        let desktop;
        if (row !== null) {
            desktop = row.desktop ?? createDesktop();
        } else {
            // dropping between two rows creates a new desktop there
            const gap = overviewRoot.gapAt(position);
            if (gap === -1) {
                return;
            }
            desktop = createDesktop(gap);
        }
        move(desktop);
    }
}
