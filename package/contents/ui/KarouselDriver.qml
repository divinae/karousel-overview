pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kwin as KWinComponents
import "layout.js" as Layout

// drives Karousel, which has no API of its own, through its key bindings, which act on the focused window
Item {
    id: driver

    required property OverviewScreen overviewRoot

    // whether Karousel's key bindings are there to drive it
    property bool available: false

    function check() {
        karouselCheck.call();
    }

    function invoke(shortcuts) {
        for (const shortcut of shortcuts) {
            invokeShortcut.arguments = [shortcut];
            invokeShortcut.call();
        }
    }

    // runs Karousel key bindings for a window, which stays selected
    function moveWindow(window, moves) {
        overviewRoot.focusWindow(window);
        invoke(moves);
        overviewRoot.selectedWindow = window;
    }

    function moveColumn(window, delta) {
        moveWindow(window, Layout.repeat(delta < 0 ? Layout.KarouselShortcuts.columnMoveLeft : Layout.KarouselShortcuts.columnMoveRight, Math.abs(delta)));
    }

    // scrolls Karousel's view of the current desktop by whole columns, positive to the left
    function scroll(columns) {
        invoke(Layout.repeat(columns > 0 ? Layout.KarouselShortcuts.scrollLeftColumn : Layout.KarouselShortcuts.scrollRightColumn, Math.abs(columns)));
    }

    // between Karousel's stacked layout for the window's column and its windows one under another
    function toggleStacked(window) {
        moveWindow(window, [Layout.KarouselShortcuts.columnToggleStacked]);
    }

    // lets Karousel stop tiling a window, or tile it again
    function toggleFloating(window) {
        moveWindow(window, [Layout.KarouselShortcuts.windowToggleFloating]);
    }

    // moves a window into the column of another window on the same desktop, above it for side -1 or below for 1,
    // and gives that column Karousel's stacked layout or not
    function stackWindow(window, targetWindow, side, stacked, row, checkLayout = true) {
        const plan = row.stackPlan(window, targetWindow, side, stacked);
        if (plan === null) {
            return;
        }
        if (plan.moves === null) {
            bringThen(window, row, () => stackWindow(window, targetWindow, side, stacked, row, checkLayout));
            return;
        }
        moveWindow(window, plan.moves);
        if (!checkLayout) {
            return;
        }
        // a column that gets a second window has Karousel's default layout, which can't be read, so check it once
        // Karousel has laid it out, and switch it if it isn't the wanted one
        const joined = () => row.karouselColumns().find(column => column.windows.includes(window) && column.windows.includes(targetWindow));
        waitThen(row, () => joined() !== undefined, () => {
            const column = joined();
            if (column !== undefined && row.isStackedColumn(column) !== stacked) {
                overviewRoot.focusWindow(window);
                invoke([Layout.KarouselShortcuts.columnToggleStacked]);
            }
        });
    }

    // a whole column, its windows given from top to bottom, dropped onto a window: they join that window's column one
    // after another, the first above or below it, the others below the one before, once Karousel has placed that one
    function mergeColumn(windows, targetWindow, side, stacked, row) {
        const step = (index, anchor, anchorSide) => {
            const window = windows[index];
            const last = index === windows.length - 1;
            stackWindow(window, anchor, anchorSide, stacked, row, last);
            if (!last) {
                waitThen(row, () => row.karouselColumns().some(column => column.windows.includes(window) && column.windows.includes(anchor)),
                         () => step(index + 1, window, 1));
            }
        };
        if (windows.length > 0) {
            step(0, targetWindow, side);
        }
    }

    // moves a whole column beside another window's column, side -1 left or 1 right
    function tileColumn(window, targetWindow, side, row) {
        const columns = row.karouselColumns();
        const source = Layout.columnIndex(columns, window);
        const target = Layout.columnIndex(columns, targetWindow);
        const moves = source === -1 || target === -1 ? []
            : Layout.tileMoves(columns.map((column, i) => i === source ? 1 : column.windows.length), source, target, side);
        if (moves.length > 0) {
            moveWindow(window, moves);
        }
    }

    // moves a window into a column of its own beside another window's column on the same desktop, side -1 left or 1 right
    function tileWindow(window, targetWindow, side, row) {
        if (row.arrives(window)) {
            bringThen(window, row, () => tileWindow(window, targetWindow, side, row));
            return;
        }
        const columns = row.karouselColumns();
        const source = Layout.columnIndex(columns, window);
        const target = Layout.columnIndex(columns, targetWindow);
        const moves = source === -1 || target === -1 ? [] : Layout.tileMoves(columns.map(column => column.windows.length), source, target, side);
        // already there, the column stays too
        if (moves.length > 0) {
            moveWindow(window, moves);
        }
    }

    // a floating window, or one from another desktop, dropped at a place among the row's columns: Karousel tiles it
    // first, next to the last focused column, then action moves it from there once Karousel has laid it out
    function bringThen(window, row, action) {
        // floating on its own desktop, it floats here too until Karousel tiles it again
        const home = window.desktops.length === 1 ? overviewRoot.rowForDesktop(window.desktops[0]) : null;
        const floating = home !== null && home.isFloating(window);
        if (!row.hasWindow(window)) {
            overviewRoot.desktopActions.moveWindowToDesktop(window, row.desktop);
        }
        if (floating) {
            toggleFloating(window);
        }
        waitThen(row, () => row.karouselColumns().some(column => column.windows.includes(window)), action);
    }

    // runs action once ready returns true and the row's columns have stopped moving, Karousel is done then;
    // several can wait at once, e.g. a column merging while another window is dropped
    function waitThen(row, ready, action) {
        waitChecks.push({ row: row, ready: ready, action: action, signature: "", ticks: 0 });
        waitTimer.start();
    }

    property var waitChecks: []

    Timer {
        id: waitTimer
        interval: 150
        repeat: true
        onTriggered: {
            const checks = driver.waitChecks;
            driver.waitChecks = [];
            const done = [];
            for (const check of checks) {
                // Karousel's key bindings go through D-Bus, give it a few seconds
                if (++check.ticks > 40) {
                    continue;
                }
                if (!check.ready()) {
                    driver.waitChecks.push(check);
                    continue;
                }
                // the same for two checks in a row, when Karousel is done
                const signature = JSON.stringify(check.row.karouselColumns().map(column => [column.x, column.width, column.y, column.bottom, column.windows.length]));
                if (signature !== check.signature) {
                    check.signature = signature;
                    driver.waitChecks.push(check);
                    continue;
                }
                done.push(check);
            }
            if (driver.waitChecks.length === 0) {
                stop();
            }
            // after the list is settled, the actions can wait again
            for (const check of done) {
                check.action();
            }
        }
    }

    KWinComponents.DBusCall {
        id: invokeShortcut
        service: "org.kde.kglobalaccel"
        path: "/component/kwin"
        method: "invokeShortcut"
    }

    KWinComponents.DBusCall {
        id: karouselCheck
        service: "org.kde.kglobalaccel"
        path: "/component/kwin"
        dbusInterface: "org.kde.kglobalaccel.Component"
        method: "shortcutNames"
        onFinished: returnValue => {
            // the list of names may not arrive as a JavaScript array, as a string it's a comma-separated list
            driver.available = String(returnValue[0]).includes(Layout.KarouselShortcuts.scrollLeftColumn);
        }
    }
}
