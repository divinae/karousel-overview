import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import "layout.js" as Layout

Item {
    id: overview
    focus: true

    readonly property QtObject targetScreen: KWinComponents.SceneView.screen
    readonly property rect screenGeometry: targetScreen.geometry
    readonly property real rowHeight: Math.round(height * effect.configuration.RowHeight / 100)
    readonly property real thumbScale: screenGeometry.height > 0 ? rowHeight / screenGeometry.height : 1
    readonly property bool multipleScreens: KWinComponents.Workspace.screens.length > 1
    readonly property Item currentRow: rows.currentItem

    property QtObject selectedWindow: null
    readonly property QtObject draggedWindow: dragController.window
    // the window that a dragged window would join the column of
    readonly property QtObject dropTargetWindow: dragController.targetWindow
    // whether Karousel's key bindings are there to drive it
    property bool karouselAvailable: false
    // the current desktop of this screen, kept up to date
    property QtObject activeDesktop: currentDesktop()
    property string searchText: ""

    // set once everything is laid out, so that the zoom always animates from 0
    property bool organized: false
    // 0 shows the current desktop at its real size, 1 is fully zoomed out
    property real zoom: !organized ? 0 : effect.gestureInProgress ? effect.partialActivationFactor : (effect.activated ? 1 : 0)
    Behavior on zoom {
        enabled: !effect.gestureInProgress
        NumberAnimation { duration: effect.animationDuration; easing.type: Easing.OutCubic }
    }
    // position of the zoomed-into row's viewport frame, in rows' coordinates
    property point zoomOrigin

    readonly property QtObject style: QtObject {
        // the underlay uses the theme's background color, so draw on top of it with its text color
        readonly property color foreground: Kirigami.Theme.textColor

        function foregroundAlpha(alpha) {
            return Qt.rgba(foreground.r, foreground.g, foreground.b, alpha);
        }
    }

    function currentDesktop() {
        return KWinComponents.Workspace.currentDesktopForScreen(targetScreen);
    }

    function rowForDesktop(desktop) {
        const index = KWinComponents.Workspace.desktops.indexOf(desktop);
        return index === -1 ? null : rows.itemAtIndex(index);
    }

    // the row at a point in the overview's coordinates
    function rowAt(point) {
        const position = rows.mapFromItem(overview, point.x, point.y);
        return rows.itemAt(position.x + rows.contentX, position.y + rows.contentY);
    }

    // the window thumbnail at a point in the overview's coordinates
    function thumbAt(point) {
        return rowAt(point)?.thumbAt(point) ?? null;
    }

    // where the current desktop's viewport frame ends up once its row is centered, the rows may still be moving there
    function captureZoomOrigin() {
        const index = KWinComponents.Workspace.desktops.indexOf(currentDesktop());
        const row = index === -1 ? null : rows.itemAtIndex(index);
        if (row === null) {
            return;
        }
        rows.currentIndex = index;
        const frame = row.viewportFramePosition(row);
        zoomOrigin = Qt.point(frame.x, rows.preferredHighlightBegin + frame.y);
    }

    // where a new desktop would be inserted for a point in the gap between two rows, or -1
    function gapAt(point) {
        if (rowAt(point) !== null) {
            return -1;
        }
        const above = rowAt(Qt.point(point.x, point.y - rows.spacing));
        const below = rowAt(Qt.point(point.x, point.y + rows.spacing));
        if (below === null || below.desktop === null || (above === null && below.index !== 0)) {
            return -1;
        }
        return below.index;
    }

    function createDesktop(position = KWinComponents.Workspace.desktops.length) {
        KWinComponents.Workspace.createDesktop(position, "");
        return KWinComponents.Workspace.desktops[position];
    }

    function switchToDesktop(desktop) {
        if (desktop === null) {
            desktop = createDesktop();
        }
        if (desktop !== currentDesktop()) {
            KWinComponents.Workspace.setCurrentDesktopForScreen(desktop, targetScreen);
        }
        effect.deactivate();
    }

    function switchToDesktopKeepingOverview(row) {
        if (row.desktop !== currentDesktop()) {
            KWinComponents.Workspace.setCurrentDesktopForScreen(row.desktop, targetScreen);
            rows.currentIndex = row.index;
        }
    }

    function focusWindow(window) {
        if (window.desktops.length === 1 && window.desktops[0] !== currentDesktop()) {
            KWinComponents.Workspace.setCurrentDesktopForScreen(window.desktops[0], targetScreen);
        }
        KWinComponents.Workspace.activeWindow = window;
    }

    function activateWindow(window) {
        focusWindow(window);
        effect.deactivate();
    }

    function activateSelected() {
        const row = rows.currentItem;
        if (row === null) {
            effect.deactivate();
        } else if (selectedWindow !== null && row.hasWindow(selectedWindow)) {
            activateWindow(selectedWindow);
        } else {
            switchToDesktop(row.desktop);
        }
    }

    // Karousel doesn't expose any API, so it's driven through its key bindings, which act on the focused window
    function invokeKarousel(shortcuts) {
        for (const shortcut of shortcuts) {
            invokeShortcut.arguments = [shortcut];
            invokeShortcut.call();
        }
    }

    function moveColumn(window, delta) {
        focusWindow(window);
        invokeKarousel(Layout.repeat(delta < 0 ? Layout.KarouselShortcuts.columnMoveLeft : Layout.KarouselShortcuts.columnMoveRight, Math.abs(delta)));
        selectedWindow = window;
    }

    // moves a window into the column of another window on the same desktop
    function stackWindow(window, targetWindow, row) {
        const columns = row.karouselColumns();
        const source = columns.findIndex(column => column.windows.includes(window));
        const target = columns.findIndex(column => column.windows.includes(targetWindow));
        if (source === -1 || target === -1) {
            return;
        }
        focusWindow(window);
        invokeKarousel(Layout.stackMoves(columns.map(column => column.windows.length), source, target));
        selectedWindow = window;
    }

    // scrolls Karousel's view of the current desktop by whole columns, positive to the left
    function scrollKarousel(columns) {
        invokeKarousel(Layout.repeat(columns > 0 ? Layout.KarouselShortcuts.scrollLeftColumn : Layout.KarouselShortcuts.scrollRightColumn, Math.abs(columns)));
    }

    // moves to another row without changing focus
    function showRow(delta) {
        rows.currentIndex = Layout.clamp(rows.currentIndex + delta, 0, rows.count - 1);
    }

    // moves to another row and focuses the window closest to the middle of the view
    function selectRow(delta) {
        const index = Layout.clamp(rows.currentIndex + delta, 0, rows.count - 1);
        if (index === rows.currentIndex) {
            return;
        }
        rows.currentIndex = index;
        rows.currentItem.selectClosestToViewport(true);
    }

    function refreshSelection() {
        const row = rows.currentItem;
        if (row !== null && (selectedWindow === null || !row.hasWindow(selectedWindow))) {
            row.selectClosestToViewport(false);
        }
    }

    function startDrag(window, item, scenePosition) {
        dragController.start(window, item, scenePosition);
    }

    function moveDrag(scenePosition) {
        dragController.move(scenePosition);
    }

    function endDrag() {
        dragController.end();
    }

    function cancelDrag() {
        dragController.cancel();
    }

    function dropWindow(window, position, centerX, targetWindow) {
        const row = rowAt(position);
        if (row !== null && targetWindow !== null && row.hasWindow(window) && row.hasWindow(targetWindow)) {
            stackWindow(window, targetWindow, row);
            return;
        }
        if (row !== null && row.hasWindow(window)) {
            row.reorderColumn(window, centerX);
            return;
        }

        let desktop;
        if (row !== null) {
            desktop = row.desktop ?? createDesktop();
        } else {
            // dropping between two rows creates a new desktop there
            const gap = gapAt(position);
            if (gap === -1) {
                return;
            }
            desktop = createDesktop(gap);
        }
        moveWindowToDesktop(window, desktop);
    }

    // Karousel picks this up and moves the window to the desktop's grid, but it only lays out the current desktop,
    // so switch to it and focus the window to have it placed next to the other windows there
    function moveWindowToDesktop(window, desktop) {
        window.desktops = [desktop];
        focusWindow(window);
        selectedWindow = window;
        rows.currentIndex = KWinComponents.Workspace.desktops.indexOf(desktop);
    }

    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_Escape:
            if (searchText !== "") {
                searchText = "";
            } else {
                effect.deactivate();
            }
            break;
        case Qt.Key_Up:
            selectRow(-1);
            break;
        case Qt.Key_Down:
            selectRow(1);
            break;
        case Qt.Key_Left:
            rows.currentItem?.selectNeighbour(-1);
            break;
        case Qt.Key_Right:
            rows.currentItem?.selectNeighbour(1);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            activateSelected();
            break;
        case Qt.Key_Delete:
            selectedWindow?.closeWindow();
            break;
        case Qt.Key_Backspace:
            searchText = searchText.slice(0, -1);
            break;
        case Qt.Key_Space:
            if (searchText === "") {
                activateSelected();
            } else {
                searchText += " ";
            }
            break;
        default:
            if (event.text.length !== 1 || event.text < " " || (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier))) {
                return;
            }
            searchText += event.text;
        }
        event.accepted = true;
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
            overview.karouselAvailable = String(returnValue[0]).includes(Layout.KarouselShortcuts.scrollLeftColumn);
        }
    }

    Backdrop {
        anchors.fill: parent
        screen: overview.targetScreen
        desktop: overview.activeDesktop
        zoom: overview.zoom
    }

    ListView {
        id: rows
        anchors.fill: parent
        // one extra row at the end for creating a new desktop
        model: KWinComponents.Workspace.desktops.length + 1
        spacing: Kirigami.Units.gridUnit * 2
        interactive: overview.draggedWindow === null
        highlightRangeMode: ListView.StrictlyEnforceRange
        // the current row in the middle, the new desktop row is smaller than the others
        readonly property real currentRowHeight: currentItem !== null ? currentItem.height : overview.rowHeight
        preferredHighlightBegin: (height - currentRowHeight) / 2
        preferredHighlightEnd: preferredHighlightBegin + currentRowHeight
        highlightMoveDuration: effect.animationDuration
        // keep all rows around, so that a dragged window's row isn't destroyed when scrolled away and every desktop's row
        // can be found, there are only a few desktops
        cacheBuffer: (overview.rowHeight + spacing) * count

        // zoom from the viewport frame of the current desktop's row filling the screen
        readonly property real fullScale: 1 / overview.thumbScale
        transform: [
            Scale {
                xScale: Layout.zoomScale(rows.fullScale, overview.zoom)
                yScale: Layout.zoomScale(rows.fullScale, overview.zoom)
            },
            Translate {
                x: Layout.zoomOffset(rows.fullScale, overview.zoomOrigin.x, overview.zoom)
                y: Layout.zoomOffset(rows.fullScale, overview.zoomOrigin.y, overview.zoom)
            }
        ]

        // clicking between the rows closes the overview
        TapHandler {
            onTapped: eventPoint => {
                const position = eventPoint.position;
                if (rows.itemAt(position.x + rows.contentX, position.y + rows.contentY) === null) {
                    effect.deactivate();
                }
            }
        }

        delegate: DesktopRow {
            required property int index

            width: rows.width
            // the row for creating a new desktop has no windows to show, so it's smaller
            height: desktop !== null ? overview.rowHeight : Math.round(overview.rowHeight * 0.35)
            desktop: index < KWinComponents.Workspace.desktops.length ? KWinComponents.Workspace.desktops[index] : null
            overviewRoot: overview
            selected: ListView.isCurrentItem
        }
    }

    DragController {
        id: dragController
        anchors.fill: parent
        z: 1
        overviewRoot: overview
        onDropped: (window, position, centerX, targetWindow) => overview.dropWindow(window, position, centerX, targetWindow)
    }

    // shows where dropping a window between two rows creates a new desktop, styled like the column insertion hint
    Kirigami.ShadowedRectangle {
        readonly property Item rowBelow: rows.itemAtIndex(dragController.hoveredGap)
        readonly property bool shown: dragController.hoveredGap !== -1 && rowBelow !== null

        x: (overview.width - width) / 2
        y: {
            rows.contentY; // reposition while the rows move
            return rowBelow !== null ? rowBelow.mapToItem(overview, 0, 0).y - (rows.spacing + height) / 2 : 0;
        }
        z: 1
        width: overview.width * 0.5
        height: Kirigami.Units.smallSpacing * 1.5
        radius: height / 2
        color: Kirigami.Theme.highlightColor
        shadow.size: Kirigami.Units.gridUnit
        shadow.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.6)
        opacity: shown ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }
    }

    WheelNavigation {
        anchors.fill: parent
        z: 1
        enabled: searchOverlay.resultsView === null
        overviewRoot: overview
    }

    PanelsLayer {
        anchors.fill: parent
        z: 2
        screen: overview.targetScreen
        desktop: overview.activeDesktop
        zoom: overview.zoom
    }

    SearchOverlay {
        id: searchOverlay
        anchors.fill: parent
        z: 3
        searchText: overview.searchText
        showResults: rows.currentItem === null || rows.currentItem.windowCount === 0
        onResultActivated: effect.deactivate()
    }

    onSearchTextChanged: Qt.callLater(refreshSelection)

    // the selection follows focus changes from outside the overview, e.g. Karousel's key bindings
    Connections {
        target: KWinComponents.Workspace
        function onWindowRemoved(window) {
            if (window === overview.draggedWindow) {
                overview.cancelDrag();
            }
        }
        function onCurrentDesktopChanged() {
            overview.activeDesktop = overview.currentDesktop();
            const index = KWinComponents.Workspace.desktops.indexOf(overview.activeDesktop);
            if (index !== -1 && overview.draggedWindow === null) {
                rows.currentIndex = index;
            }
        }
        function onWindowActivated(window) {
            if (window === null || overview.draggedWindow !== null || window.desktops.length !== 1) {
                return;
            }
            const row = overview.rowForDesktop(window.desktops[0]);
            if (row === null || !row.hasWindow(window)) {
                return;
            }
            overview.selectedWindow = window;
            rows.currentIndex = row.index;
            row.ensureWindowVisible(window);
        }
    }

    Connections {
        target: effect
        function onActivatedChanged() {
            if (!effect.activated) {
                overview.captureZoomOrigin();
            }
        }
        function onGestureInProgressChanged() {
            if (effect.gestureInProgress) {
                overview.captureZoomOrigin();
            }
        }
    }

    Keys.forwardTo: searchOverlay.resultsView !== null ? [searchOverlay.resultsView] : []
    Keys.onPressed: event => handleKey(event)

    Component.onCompleted: {
        karouselCheck.call();
        selectedWindow = KWinComponents.Workspace.activeWindow;
        rows.currentIndex = Math.max(0, KWinComponents.Workspace.desktops.indexOf(currentDesktop()));
        rows.positionViewAtIndex(rows.currentIndex, ListView.Center);
        const row = rows.currentItem;
        if (row !== null && selectedWindow !== null && row.hasWindow(selectedWindow)) {
            row.centerOnWindow(selectedWindow);
        }
        captureZoomOrigin();
        organized = true;
    }
}
