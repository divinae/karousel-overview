pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import "layout.js" as Layout

Item {
    id: overview
    focus: true

    // main.qml's effect, passed down rather than reached by its id, so that qmllint can follow it
    required property var sceneEffect
    readonly property var config: sceneEffect.configuration
    // KWin's objects are typed var, qmllint doesn't know their types
    readonly property var targetScreen: KWinComponents.SceneView.screen
    readonly property rect screenGeometry: targetScreen.geometry
    readonly property real rowHeight: Math.round(height * overview.config.RowHeight / 100)
    readonly property real thumbScale: screenGeometry.height > 0 ? rowHeight / screenGeometry.height : 1
    // how much larger than shown the thumbnails are rendered, up to the window's real size, at most twice: shrinking
    // to half with linear filtering averages each 2x2 pixels, sharp and without taking too much memory
    readonly property real thumbSupersampling: Math.max(1, Math.min(2, 1 / thumbScale))
    // the texture of a window's layer when it's shown at the given size, the same while zooming, which would
    // otherwise allocate a new one every frame
    function thumbTextureSize(width, height) {
        const scale = thumbSupersampling * Screen.devicePixelRatio;
        return Qt.size(Math.ceil(width * scale), Math.ceil(height * scale));
    }
    readonly property bool multipleScreens: KWinComponents.Workspace.screens.length > 1
    readonly property DesktopRow currentRow: rows.currentItem as DesktopRow

    // Karousel's gaps between columns and between the windows in a column, in pixels, the overview keeps them
    // although the windows are smaller, see main.qml
    readonly property real horizontalGap: sceneEffect.horizontalGap
    readonly property real verticalGap: sceneEffect.verticalGap >= 0 ? sceneEffect.verticalGap : horizontalGap
    property var selectedWindow: null
    readonly property var draggedWindow: dragController.window
    // what moves the rows or the minimap under a still pointer, see DragController.dragState
    readonly property real rowsPosition: rows.contentY
    readonly property bool minimapShown: minimap.item !== null && (minimap.item as DesktopMinimap).shown
    // the dragged window, or all of its column's when the column is dragged by its handle
    readonly property var draggedWindows: draggedWindow === null ? [] : dragController.wholeColumn ? dragController.columnWindows : [draggedWindow]
    // the window that a dragged window would join the column of
    readonly property var dropTargetWindow: dropZoneWindow ?? externalDragItem.window
    // the window a dragged one would join or tile beside, and where: "center", "top", "bottom", "left" or "right"
    readonly property var dropZoneWindow: dragController.dropAction === "" ? null : dragController.targetWindow ?? dragController.tileWindow
    readonly property string dropZone: dropZoneWindow === null ? ""
        : dragController.targetWindow !== null ? (dragController.stacked ? "center" : dragController.side < 0 ? "top" : "bottom")
        : dragController.side < 0 ? "left" : "right"
    // driving Karousel, desktops and drops, and drags from apps, see those files
    readonly property KarouselDriver karousel: karouselDriver
    readonly property DesktopActions desktopActions: actions
    readonly property ExternalDrag externalDrag: externalDragItem
    // the overview zooms into a clicked window once its strip has glided there
    readonly property bool activating: activationTimer.running
    // the current desktop of this screen, kept up to date
    property var activeDesktop: currentDesktop()
    property string searchText: ""

    // set once everything is laid out, so that the zoom always animates from 0
    property bool organized: false
    // 0 shows the current desktop at its real size, 1 is fully zoomed out
    property real zoom: !organized ? 0 : overview.sceneEffect.gestureInProgress ? overview.sceneEffect.partialActivationFactor : (overview.sceneEffect.activated ? 1 : 0)
    Behavior on zoom {
        enabled: !overview.sceneEffect.gestureInProgress
        NumberAnimation { duration: overview.sceneEffect.animationDuration; easing.type: Easing.OutCubic }
    }
    // rounded corners of the window thumbnails, square at the start of the zoom, where they are the real windows
    readonly property real windowRadius: Kirigami.Units.largeSpacing * zoom
    // position of the zoomed-into row's viewport frame, in rows' coordinates
    property point zoomOrigin

    readonly property var style: QtObject {
        // the underlay uses the theme's background color, so draw on top of it with its text color
        readonly property color foreground: Kirigami.Theme.textColor

        function foregroundAlpha(alpha) {
            return Qt.rgba(foreground.r, foreground.g, foreground.b, alpha);
        }

        function highlightAlpha(alpha) {
            return Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, alpha);
        }
    }

    // where a window is in Karousel's layout: on other desktops than the current one where it was while its desktop
    // was current, KWin has moved the windows far off screen since, see main.qml's layouts
    function geometryOf(window) {
        if (window.desktops.length === 1 && window.desktops[0] !== overview.activeDesktop) {
            const remembered = overview.sceneEffect.rememberedGeometry(window);
            if (remembered !== null) {
                return remembered;
            }
        }
        return window.frameGeometry;
    }

    function currentDesktop() {
        return KWinComponents.Workspace.currentDesktopForScreen(targetScreen);
    }

    function rowForDesktop(desktop) {
        const index = KWinComponents.Workspace.desktops.indexOf(desktop);
        return index === -1 ? null : rows.itemAtIndex(index) as DesktopRow;
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
        const row = index === -1 ? null : rows.itemAtIndex(index) as DesktopRow;
        if (row === null) {
            return;
        }
        rows.currentIndex = index;
        const frame = row.viewportFramePosition(row);
        zoomOrigin = Qt.point(frame.x, rows.preferredHighlightBegin + frame.y);
    }

    // shows a desktop's row, the one after the last desktop creates a new desktop, reusing the last one if it's empty
    function goToRow(index) {
        navigatedAt = Date.now();
        const desktops = KWinComponents.Workspace.desktops;
        const show = () => {
            rows.currentIndex = Layout.clamp(index, 0, rows.count - 1);
            overview.currentRow?.selectClosestToViewport(false);
        };
        if (index === desktops.length) {
            const last = desktops[desktops.length - 1];
            // its own windows, in the current activity, as its row shows them
            if (KWinComponents.Workspace.windows.some(window => desktopActions.belongsTo(window, last))) {
                desktopActions.createDesktop();
                // after the rows keep showing the row they showed when the count changed, see onCountChanged
                Qt.callLater(show);
                return;
            }
            index = desktops.length - 1;
        }
        show();
    }

    // the minimap's card at a point, the last one is for a new desktop, -1 when there's none
    function minimapIndexAt(point) {
        return minimap.item !== null ? (minimap.item as DesktopMinimap).indexAt(point) : -1;
    }

    function minimapContains(point) {
        return minimap.item !== null && (minimap.item as DesktopMinimap).containsPoint(point);
    }

    // where scrolling a row by dragging against the right edge starts, before the minimap when it's beside the point
    function scrollEdgeRight(point) {
        const item = minimap.item as DesktopMinimap;
        return item !== null && item.shown && !item.horizontal && point.y >= item.y && point.y < item.y + item.height ? item.x : width;
    }

    // a window on all desktops has none of its own
    function isOnDesktop(window, desktop) {
        return window.desktops.length === 0 || window.desktops.includes(desktop);
    }

    // where a new desktop would be inserted for a point in the gap between two rows, or -1
    function gapAt(point) {
        if (rowAt(point) !== null) {
            return -1;
        }
        const above = rowAt(Qt.point(point.x, point.y - rows.spacing));
        const below = rowAt(Qt.point(point.x, point.y + rows.spacing));
        // after the last desktop when there's no "New desktop" row there to drop onto
        if (below === null && above !== null && above.desktop !== null && !overview.config.ShowNewDesktopRow
                && above.index === KWinComponents.Workspace.desktops.length - 1) {
            return above.index + 1;
        }
        if (below === null || below.desktop === null || (above === null && below.index !== 0)) {
            return -1;
        }
        return below.index;
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

    // the row that zooms in once its strip has glided to the clicked window, see activateWindow
    property DesktopRow activationRow: null

    property real activationStart: 0

    function activateWindow(window) {
        const row = window.desktops.length === 1 ? rowForDesktop(window.desktops[0]) : null;
        if (row === null || !row.scrollsKarousel) {
            // switching to its desktop first, the zoom goes into that desktop's row
            focusWindow(window);
            overview.sceneEffect.deactivate();
            return;
        }
        // like niri's, the strip first glides to the window in the middle of the screen, then the overview zooms
        // into it; both at once move the strip a long way at the start of the zoom, when the window is far away
        row.focusWindow(window, true, overview.config.CenterOnClick);
        activationRow = row;
        activationStart = Date.now();
        activationTimer.start();
    }

    Timer {
        id: activationTimer
        interval: 16
        repeat: true
        onTriggered: {
            const row = overview.activationRow;
            if (row !== null && !row.readyToZoom() && Date.now() - overview.activationStart < 1000) {
                return;
            }
            stop();
            overview.activationRow = null;
            // the windows are where they really are, so the sync can end, before the zoom starts from the view
            if (row !== null && row.syncingScroll) {
                row.finishKarouselSync(true);
            }
            overview.sceneEffect.deactivate();
        }
    }

    function activateSelected() {
        const row = overview.currentRow;
        if (row === null) {
            overview.sceneEffect.deactivate();
        } else if (selectedWindow !== null && row.hasWindow(selectedWindow)) {
            activateWindow(selectedWindow);
        } else {
            desktopActions.switchToDesktop(row.desktop);
        }
    }

    // when the user last moved to another row, KWin's answers to the focus changes on the way come later, see
    // followsKWin
    property real navigatedAt: 0

    // whether to follow KWin's desktop switches and focus changes to another row; not right after moving to another row,
    // they can come from a row passed on the way, e.g. when scrolling quickly, and would pull the overview back to it
    function followsKWin() {
        return Date.now() - navigatedAt > 400;
    }

    // moves to another row without changing focus
    function showRow(delta) {
        navigatedAt = Date.now();
        rows.currentIndex = Layout.clamp(rows.currentIndex + delta, 0, rows.count - 1);
    }

    // moves to another row and focuses the window closest to the middle of the view
    function selectRow(delta) {
        const index = Layout.clamp(rows.currentIndex + delta, 0, rows.count - 1);
        if (index === rows.currentIndex) {
            return;
        }
        navigatedAt = Date.now();
        rows.currentIndex = index;
        overview.currentRow.selectClosestToViewport(true);
    }

    function refreshSelection() {
        const row = overview.currentRow;
        if (row !== null && (selectedWindow === null || !row.hasWindow(selectedWindow))) {
            row.selectClosestToViewport(false);
        }
    }

    // with columnWindows, the windows of the window's column, the whole column moves, dragged by its handle, see DesktopRow
    function startDrag(window, item, scenePosition, columnWindows = []) {
        dragController.start(window, item, scenePosition, columnWindows);
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

    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_Escape:
            if (searchText !== "") {
                searchText = "";
            } else {
                overview.sceneEffect.deactivate();
            }
            break;
        case Qt.Key_Up:
            selectRow(-1);
            break;
        case Qt.Key_Down:
            selectRow(1);
            break;
        case Qt.Key_Left:
            overview.currentRow?.selectNeighbour(-1);
            break;
        case Qt.Key_Right:
            overview.currentRow?.selectNeighbour(1);
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

    KarouselDriver {
        id: karouselDriver
        overviewRoot: overview // qmllint disable incompatible-type
    }

    DesktopActions {
        id: actions
        overviewRoot: overview // qmllint disable incompatible-type
    }

    ExternalDrag {
        id: externalDragItem
        anchors.fill: parent
        overviewRoot: overview // qmllint disable incompatible-type
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
        model: KWinComponents.Workspace.desktops.length + (overview.config.ShowNewDesktopRow ? 1 : 0)

        // the model is a number, so a desktop added or removed resets the view to the first row; the desktop shown
        // before is shown again, or when it's the one removed, the one before it
        property var shownDesktop: null
        property int shownIndex: 0
        property int knownCount: 0
        onCurrentIndexChanged: {
            if (count === knownCount) {
                shownIndex = currentIndex;
                shownDesktop = currentIndex < KWinComponents.Workspace.desktops.length ? KWinComponents.Workspace.desktops[currentIndex] : null;
            }
        }
        onCountChanged: {
            // also emitted again by the reset, with the same count
            if (count === knownCount) {
                return;
            }
            const removed = count < knownCount;
            knownCount = count;
            if (!overview.organized) {
                return;
            }
            const index = rows.shownDesktop !== null ? KWinComponents.Workspace.desktops.indexOf(rows.shownDesktop) : -1;
            const target = Layout.clamp(index !== -1 ? index : rows.shownIndex - (removed ? 1 : 0), 0, count - 1);
            // the reset can come after this
            Qt.callLater(() => {
                rows.currentIndex = target;
                rows.positionViewAtIndex(target, ListView.Center);
            });
        }
        spacing: Kirigami.Units.gridUnit * 2
        interactive: overview.draggedWindow === null
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (height - overview.rowHeight) / 2
        preferredHighlightEnd: preferredHighlightBegin + overview.rowHeight
        highlightMoveDuration: overview.sceneEffect.animationDuration
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
                    overview.sceneEffect.deactivate();
                }
            }
        }

        delegate: DesktopRow {
            required property int index

            width: rows.width
            height: overview.rowHeight
            desktop: index < KWinComponents.Workspace.desktops.length ? KWinComponents.Workspace.desktops[index] : null
            number: index + 1
            // the linter doesn't match a component's own type inside its file
            overviewRoot: overview // qmllint disable incompatible-type
            selected: ListView.isCurrentItem
        }
    }

    // only made when turned on; at the overview's origin, the minimap places itself
    Loader {
        id: minimap
        z: 1
        active: overview.config.ShowDropMinimap
        sourceComponent: DesktopMinimap {
            overviewRoot: overview // qmllint disable incompatible-type
            drag: dragController
            revealed: minimapEdgeHover.hovered
            selectedIndex: rows.currentIndex
        }
    }

    // reaching the edge the minimap sits at slides it out
    Item {
        z: 1
        visible: minimap.active
        x: overview.config.DropMinimapAtTop ? 0 : overview.width - width
        width: overview.config.DropMinimapAtTop ? overview.width : Kirigami.Units.gridUnit
        height: overview.config.DropMinimapAtTop ? Kirigami.Units.gridUnit : overview.height

        HoverHandler {
            id: minimapEdgeHover
        }
    }

    DragController {
        id: dragController
        anchors.fill: parent
        z: 1
        overviewRoot: overview // qmllint disable incompatible-type
        onDropped: (window, position, dropX, targetWindow, tileWindow, side, stacked, wholeColumn, minimapIndex) => actions.dropWindow(
            window, position, dropX, targetWindow, tileWindow, side, stacked, wholeColumn ? dragController.lastColumnWindows : [], minimapIndex)
    }

    // shows where dropping a window between two rows creates a new desktop, styled like the column insertion hint
    Kirigami.ShadowedRectangle {
        readonly property DesktopRow rowBelow: rows.itemAtIndex(dragController.hoveredGap) as DesktopRow
        // after the last desktop, without a "New desktop" row below
        readonly property DesktopRow rowAbove: rows.itemAtIndex(dragController.hoveredGap - 1) as DesktopRow
        readonly property bool shown: dragController.hoveredGap !== -1 && (rowBelow !== null || rowAbove !== null)

        x: (overview.width - width) / 2
        // depends on contentY, to reposition while the rows move
        y: isNaN(rows.contentY) ? 0
            : rowBelow !== null ? rowBelow.mapToItem(overview, 0, 0).y - (rows.spacing + height) / 2
            : rowAbove !== null ? rowAbove.mapToItem(overview, 0, rowAbove.height).y + (rows.spacing - height) / 2 : 0
        z: 1
        width: overview.width * 0.5
        height: Kirigami.Units.smallSpacing * 1.5
        radius: height / 2
        color: Kirigami.Theme.highlightColor
        shadow.size: Kirigami.Units.gridUnit
        shadow.color: overview.style.highlightAlpha(0.6)
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
        overviewRoot: overview // qmllint disable incompatible-type
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
        showResults: overview.currentRow === null || overview.currentRow.windowCount === 0
        onResultActivated: overview.sceneEffect.deactivate()
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
        // the rows show the windows of the current activity, laid out by Karousel for it
        function onCurrentActivityChanged() {
            for (const desktop of KWinComponents.Workspace.desktops) {
                overview.rowForDesktop(desktop)?.scheduleUpdateBounds();
            }
            Qt.callLater(overview.refreshSelection);
        }
        function onCurrentDesktopChanged() {
            overview.activeDesktop = overview.currentDesktop();
            const index = KWinComponents.Workspace.desktops.indexOf(overview.activeDesktop);
            if (index !== -1 && overview.draggedWindow === null && overview.followsKWin()) {
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
            if (overview.followsKWin()) {
                rows.currentIndex = row.index;
            }
            // the row's sync glides to where Karousel scrolled
            if (!row.syncingScroll) {
                row.ensureWindowVisible(window);
            }
        }
    }

    Connections {
        target: overview.sceneEffect
        function onActivatedChanged() {
            if (!overview.sceneEffect.activated) {
                // closed some other way while gliding to a clicked window, the zoom isn't waiting for it any more
                if (activationTimer.running) {
                    activationTimer.stop();
                    const row = overview.activationRow;
                    overview.activationRow = null;
                    if (row !== null && row.syncingScroll) {
                        row.finishKarouselSync();
                    }
                }
                overview.captureZoomOrigin();
            }
        }
        function onGestureInProgressChanged() {
            if (overview.sceneEffect.gestureInProgress) {
                overview.captureZoomOrigin();
            }
        }
    }

    Keys.forwardTo: searchOverlay.resultsView !== null ? [searchOverlay.resultsView] : []
    Keys.onPressed: event => handleKey(event)

    Component.onDestruction: overview.sceneEffect.overviewDestroyed()

    Component.onCompleted: {
        karousel.check();
        selectedWindow = KWinComponents.Workspace.activeWindow;
        rows.currentIndex = Math.max(0, KWinComponents.Workspace.desktops.indexOf(currentDesktop()));
        rows.positionViewAtIndex(rows.currentIndex, ListView.Center);
        // the current row stays centered on what's on screen, which is where the zoom starts from
        captureZoomOrigin();
        organized = true;
    }
}
