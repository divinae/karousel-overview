pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import "layout.js" as Layout

Item {
    id: row

    // null for the row that creates a new desktop
    required property var desktop
    required property OverviewScreen overviewRoot
    property bool selected: false
    // the desktop's number, counted from 1
    property int number: 0

    readonly property rect screenGeometry: overviewRoot.screenGeometry
    readonly property real thumbScale: overviewRoot.thumbScale
    readonly property real padding: Kirigami.Units.gridUnit
    // the desktop's wallpaper stays in the middle of the row, the windows move past it when panning, like in Niri
    readonly property real viewportWidth: screenGeometry.width * thumbScale
    readonly property real viewportLeft: Math.max(0, (width - viewportWidth) / 2)
    // the wallpaper card, the desktop's view or the new desktop card
    // in the middle once zoomed out, for the current desktop where the zoom goes to or comes from when zoomed in,
    // so that the wallpaper is where the real one is even when the strip isn't centered; that point stays put during
    // the zoom, unlike the part of the strip on screen, which jumps when Karousel's view is synced while zooming
    readonly property real cardLeft: viewportLeft + (selected ? overviewRoot.zoomOrigin.x - viewportLeft : 0) * (1 - overviewRoot.zoom)
    readonly property real cardWidth: viewportWidth
    // rounded once zoomed out, square when it fills the screen at the start of the zoom
    readonly property real wallpaperRadius: Kirigami.Units.largeSpacing * 1.5 * overviewRoot.zoom
    readonly property var style: overviewRoot.style

    // horizontal extent of the strip in workspace coordinates,
    // Karousel keeps off-screen columns at their real positions
    property real stripMinX: screenGeometry.x
    property real stripMaxX: screenGeometry.x + screenGeometry.width
    // windows grouped by column, sorted from left to right
    property var columns: []
    readonly property int windowCount: thumbs.count
    // where a dragged column would land, in the strip's coordinates, NaN when not dragging one
    property real insertHintX: NaN
    // the column a dragged window would join, {x, y, width, height} in the strip's coordinates, or null
    property var stackHint: null
    // a dragged window would move to this desktop
    property bool moveHint: false
    property bool editingName: false
    // panning the current desktop's row scrolls Karousel's real view by whole columns, other rows pan their preview
    readonly property bool scrollsKarousel: overviewRoot.karouselAvailable && desktop !== null && desktop === overviewRoot.activeDesktop
    // Karousel's view is being moved to match the preview, the thumbnails stay where they are until it's done
    property bool syncingScroll: false
    // the thumbnails don't animate their movement, stays on a bit after the sync so that they don't animate its end
    property bool holdThumbs: false
    // for the blur behind translucent windows
    readonly property Item wallpaperBackground: wallpaperItem
    readonly property real contentX: flick.contentX
    // the window whose shift shows how far Karousel moved the windows, null when not syncing
    property var syncAnchor: null
    // where the anchor window was in the strip when last taken in, see rebaseHeld
    property real syncAnchorX: NaN
    // the panning didn't stop while syncing, so the view has to be synced again once it's done
    property bool resyncAfterSync: false
    // how long the sync waits for Karousel to move the next window
    property int syncSettleInterval: 0
    // after clicking a window, the sync lasts until the strip has glided to it, taking in Karousel's moves as they come,
    // see rebaseHeld
    property bool syncWhileClosing: false
    // when Karousel last moved the windows during that sync, see readyToZoom
    property real lastKarouselMove: 0
    // how far the held thumbnails have glided to where their windows are while the strip glides to a clicked window,
    // from 0 to 1, see WindowThumb's x; it's what moves the windows that Karousel doesn't move with the others,
    // like ones it doesn't tile
    property real glideFrom: NaN
    property real glideTarget: NaN
    readonly property real settleBlend: isNaN(glideFrom) || Math.abs(glideTarget - glideFrom) < 0.5 ? 0
        : Layout.clamp((flick.contentX - glideFrom) / (glideTarget - glideFrom), 0, 1)
    readonly property bool showMinimized: overviewRoot.config.ShowMinimized && desktop !== null
    // where the minimized windows after the strip end, in the strip's coordinates, 0 when there are none
    property real minimizedEnd: 0

    Accessible.role: Accessible.List
    Accessible.name: desktop !== null ? desktop.name : "New desktop"

    function startRenaming() {
        editingName = true;
        nameInput.text = desktop.name;
        nameInput.forceActiveFocus();
        nameInput.selectAll();
    }

    function finishRenaming(apply) {
        if (!editingName) {
            return;
        }
        editingName = false;
        const name = nameInput.text.trim();
        if (apply && name !== "") {
            desktop.name = name;
        }
        overviewRoot.forceActiveFocus();
    }

    function toStripX(x) {
        return (x - stripMinX) * thumbScale + padding;
    }

    // windows move one by one when Karousel rearranges, so update once for all of them
    function scheduleUpdateBounds() {
        if (syncingScroll && syncWhileClosing) {
            rebaseHeld();
        } else if (syncingScroll) {
            // Karousel is still moving the windows
            syncTimer.interval = syncSettleInterval;
            syncTimer.restart();
        } else {
            boundsTimer.restart();
        }
    }

    function refreshBounds() {
        const entries = thumbItems().map(thumb => ({ window: thumb.window, geometry: thumb.geometry }));
        const bounds = Layout.stripBounds(screenGeometry, entries.map(entry => entry.geometry));
        stripMinX = bounds.minX;
        stripMaxX = bounds.maxX;
        const newColumns = Layout.computeColumns(entries);
        // reassigning rebuilds the column frames, only do it when they changed
        const signature = column => [column.x, column.y, column.width, column.bottom, column.windows.length].join(":");
        if (newColumns.map(signature).join("|") !== columns.map(signature).join("|")) {
            columns = newColumns;
        }
        updateMinimized();
        // from the current desktop, laid out by Karousel right now, also the windows hidden by the search,
        // which leave bigger gaps; right away, not only once Karousel's key bindings have been found
        if (desktop === null || desktop !== overviewRoot.activeDesktop) {
            return;
        }
        const gaps = Layout.innerGaps(karouselWindows().map(window => window.frameGeometry));
        if (gaps.horizontal !== null) {
            overviewRoot.sceneEffect.horizontalGap = gaps.horizontal;
        }
        if (gaps.vertical !== null) {
            overviewRoot.sceneEffect.verticalGap = gaps.vertical;
        }
    }

    function updateBounds() {
        refreshBounds();
        // Karousel scrolling moves the windows, not the view, keep the view where it is
        if (scrollsKarousel && overviewRoot.draggedWindow === null && !panning()) {
            centerOnViewport();
        } else if (overviewRoot.selectedWindow !== null) {
            ensureWindowVisible(overviewRoot.selectedWindow);
        }
    }

    // Karousel's columns on this desktop, from all of its windows, also those hidden by the search,
    // so that the indexes match Karousel's when driving it through its key bindings
    function karouselColumns() {
        return Layout.computeColumns(karouselWindows().map(window => ({ window: window, geometry: overviewRoot.geometryOf(window) })));
    }

    function karouselWindows() {
        const activity = KWinComponents.Workspace.currentActivity;
        return KWinComponents.Workspace.windows
            .filter(window => window.normalWindow && !window.minimized
                && window.desktops.length === 1 && window.desktops[0] === desktop
                && (window.activities.length === 0 || window.activities.includes(activity))
                && (!overviewRoot.multipleScreens || window.output === overviewRoot.targetScreen));
    }

    // lays out minimized windows one after another after the strip
    function updateMinimized() {
        const items = [];
        for (let i = 0; i < minimizedThumbs.count; i++) {
            const item = minimizedThumbs.itemAt(i);
            if (item !== null && item.visible) {
                items.push(item);
            }
        }
        if (items.length === 0) {
            minimizedEnd = 0;
            return;
        }
        const slots = Layout.minimizedSlots(items.map(item => item.width), toStripX(stripMaxX) + padding, Kirigami.Units.largeSpacing);
        items.forEach((item, i) => item.slotX = slots.xs[i]);
        minimizedEnd = slots.end;
    }

    function thumbItems() {
        const items = [];
        for (let i = 0; i < thumbs.count; i++) {
            const item = thumbs.itemAt(i);
            if (item !== null && item.visible) {
                items.push(item);
            }
        }
        items.sort((a, b) => a.geometry.x - b.geometry.x || a.geometry.y - b.geometry.y);
        return items;
    }

    // the visible thumbnails in no particular order, cheaper than thumbItems() when the order doesn't matter
    function forEachThumb(f) {
        for (let i = 0; i < thumbs.count; i++) {
            const item = thumbs.itemAt(i);
            if (item !== null && item.visible && f(item)) {
                return item;
            }
        }
        return null;
    }

    function thumbForWindow(window) {
        return forEachThumb(thumb => thumb.window === window);
    }

    function thumbAt(point) {
        return forEachThumb(thumb => thumb.contains(thumb.mapFromItem(overviewRoot, point.x, point.y)));
    }

    function hasWindow(window) {
        return thumbForWindow(window) !== null;
    }

    function viewportFramePosition(item) {
        return viewportFrame.mapToItem(item, 0, 0);
    }

    // where the column of a window dropped at overviewX goes, among Karousel's columns,
    // or null if the window isn't in this row
    function columnDrop(window, overviewX) {
        const allColumns = karouselColumns();
        const source = allColumns.findIndex(column => column.windows.includes(window));
        if (source === -1) {
            return null;
        }
        const dropX = flick.contentItem.mapFromItem(overviewRoot, overviewX, 0).x;
        const target = Layout.reorderTarget(allColumns.map(column => toStripX(column.x + column.width / 2)), source, dropX);
        return { columns: allColumns, source: source, target: target };
    }

    function reorderColumn(window, overviewX) {
        hideInsertHint();
        const drop = columnDrop(window, overviewX);
        if (drop !== null && drop.target !== drop.source) {
            overviewRoot.moveColumn(window, drop.target - drop.source);
        }
    }

    function showInsertHint(window, overviewX) {
        stackHint = null;
        moveHint = false;
        const drop = columnDrop(window, overviewX);
        if (drop === null || drop.target === drop.source) {
            hideInsertHint();
            return;
        }
        const otherColumns = drop.columns.filter((column, i) => i !== drop.source)
            .map(column => ({ left: toStripX(column.x), right: toStripX(column.x + column.width) }));
        insertHintX = Layout.insertHintX(otherColumns, drop.target) ?? NaN;
    }

    function hideInsertHint() {
        insertHintX = NaN;
    }

    function showStackHint(window) {
        hideInsertHint();
        moveHint = false;
        const column = karouselColumns().find(column => column.windows.includes(window));
        stackHint = column === undefined ? null : {
            x: toStripX(column.x),
            y: (column.y - screenGeometry.y) * thumbScale,
            width: column.width * thumbScale,
            height: (column.bottom - column.y) * thumbScale,
        };
    }

    function showMoveHint() {
        hideInsertHint();
        stackHint = null;
        moveHint = true;
    }

    function hideHints() {
        hideInsertHint();
        stackHint = null;
        moveHint = false;
    }

    // the margins let any part of the strip, also its ends, be panned to the wallpaper in the middle
    function minContentX() {
        return -flick.leftMargin;
    }

    function maxContentX() {
        return Math.max(minContentX(), flick.contentWidth - flick.width + flick.rightMargin);
    }

    function scrollTo(contentX) {
        snapAnimation.stop();
        flick.contentX = Layout.clamp(contentX, minContentX(), maxContentX());
    }

    // settles the row so that the column closest to the wallpaper's left edge lines up with it
    function snapToColumn() {
        if (columns.length === 0 || panHandler.active || flick.moving) {
            return;
        }
        if (scrollsKarousel && overviewRoot.draggedWindow === null) {
            if (syncingScroll) {
                resyncAfterSync = true;
            } else {
                syncKarouselScroll();
            }
            return;
        }
        const target = Layout.snapTarget(columns.map(column => toStripX(column.x)), flick.contentX + viewportLeft, viewportLeft, minContentX(), maxContentX());
        if (target !== null) {
            glideTo(target);
        }
    }

    function scheduleSnap() {
        snapTimer.restart();
    }

    function scrollBy(delta) {
        scrollTo(flick.contentX + delta);
    }

    // pans the preview smoothly by delta pixels, positive moves the content to the right,
    // the current desktop's real view follows when the panning stops, see snapToColumn
    function panBy(delta) {
        scrollBy(-delta);
        scheduleSnap();
    }

    function panning() {
        return panHandler.active || flick.moving || snapTimer.running;
    }

    // scrolls Karousel's real view by whole columns, so that the column at the wallpaper's left edge in the preview
    // is at the screen's left edge, then puts the view back on the wallpaper, where the windows now are
    function syncKarouselScroll() {
        const lefts = columns.map(column => toStripX(column.x));
        const closest = x => lefts.reduce((best, left, i) => Math.abs(left - x) < Math.abs(lefts[best] - x) ? i : best, 0);
        const steps = closest(viewportFrame.x) - closest(flick.contentX + viewportLeft);
        if (steps === 0) {
            glideToViewport();
            return;
        }
        // Karousel's shortcuts go through D-Bus and it moves the windows one by one
        startKarouselSync(Kirigami.Units.longDuration * 2, Kirigami.Units.longDuration * 2);
        overviewRoot.scrollKarousel(steps);
    }

    // keeps the thumbnails where they are while Karousel moves the windows, until no window has moved for settleInterval,
    // or none did for firstInterval, see finishKarouselSync
    function startKarouselSync(firstInterval, settleInterval) {
        if (syncingScroll) {
            // e.g. focusing a window while the view is synced, wait for the slower of the two
            syncSettleInterval = Math.max(syncSettleInterval, settleInterval);
            syncTimer.interval = Math.max(syncTimer.interval, firstInterval);
            syncTimer.restart();
            return;
        }
        syncSettleInterval = settleInterval;
        syncTimer.interval = firstInterval;
        syncTimer.restart();
        snapAnimation.stop();
        const anchor = thumbItems().reduce((best, thumb) => best === null
            || Math.abs(thumb.layoutX - flick.contentX - viewportLeft) < Math.abs(best.layoutX - flick.contentX - viewportLeft) ? thumb : best, null);
        syncAnchor = anchor === null ? null : anchor.window;
        syncAnchorX = anchor === null ? NaN : toStripX(anchor.window.frameGeometry.x);
        holdThumbs = true;
        forEachThumb(thumb => { thumb.heldX = thumb.x - thumb.insetX; });
        syncingScroll = true;
    }

    // Karousel scrolls its view to the focused window, the preview glides after it instead of jumping,
    // also while the overview zooms into it
    // with center, Karousel then also scrolls it to the middle of the screen
    // activating it means the overview zooms into it after this, see OverviewScreen's activateWindow
    function focusWindow(window, activating = false, center = false) {
        const syncs = scrollsKarousel && overviewRoot.draggedWindow === null && hasWindow(window);
        if (syncs) {
            // Karousel moves the windows right away when the focus changes; when activating, also centering, which comes
            // later through D-Bus, the moves are taken in as they come until the overview zooms in, see rebaseHeld and
            // readyToZoom
            startKarouselSync(activating ? 5000 : Kirigami.Units.shortDuration, 0);
            syncWhileClosing = activating;
            lastKarouselMove = Date.now();
        }
        // Karousel's centering toggles, from the middle it scrolls the window back to the side
        const centered = !center || isCentered(window);
        overviewRoot.focusWindow(window);
        if (syncs && !centered) {
            overviewRoot.invokeKarousel([Layout.KarouselShortcuts.scrollFocused]);
        }
    }

    // whether the window's column is in the middle of the area Karousel tiles in, give or take its rounding
    function isCentered(window) {
        const area = KWinComponents.Workspace.clientArea(KWinComponents.Workspace.MaximizeArea, overviewRoot.targetScreen, desktop);
        const column = karouselColumns().find(column => column.windows.includes(window));
        return column !== undefined && Math.abs(column.x + column.width / 2 - (area.x + area.width / 2)) <= 1;
    }

    // Karousel is done moving the windows, they go where they really are, and the view moves by as much in the same frame,
    // so nothing moves on screen, then it glides to the wallpaper, Karousel's view can be a bit off from the preview,
    // e.g. because of the gaps or the ends of the strip
    // while zooming into a clicked window, Karousel's moves are taken in as they come, so it doesn't matter how late
    // they are: the held thumbnails and the view move by as much, so nothing moves on screen, and the glide to the
    // wallpaper starts over for what's left of the zoom
    function rebaseHeld() {
        if (syncAnchor === null || isNaN(syncAnchorX)) {
            return;
        }
        // from the window itself, this runs from the change handlers, before the thumbnails' bindings have caught up,
        // and Karousel can move a window back and forth within one rearrangement
        const x = toStripX(syncAnchor.frameGeometry.x);
        const delta = x - syncAnchorX;
        if (Math.abs(delta) < 0.01) {
            return;
        }
        syncAnchorX = x;
        lastKarouselMove = Date.now();
        // from where they are on screen, also those already gliding to their windows, see settleBlend, before the view
        // moves, which would move the glide along
        bakeHeld(delta);
        glideFrom = NaN;
        flick.contentX += delta;
        glideToViewport();
    }

    // the held thumbnails stay where they are on screen, shifted by delta with the view, from here on
    function bakeHeld(delta = 0) {
        forEachThumb(thumb => {
            if (!isNaN(thumb.heldX)) {
                thumb.heldX = thumb.x - thumb.insetX + delta;
            }
        });
    }

    // after clicking a window, the strip has glided so that the part of it on screen is under the wallpaper, so the
    // view is put exactly there, where the windows are on the screen, see OverviewScreen's activateWindow
    function finishKarouselSync(atViewport = false) {
        syncWhileClosing = false;
        glideFrom = NaN;
        const anchor = syncAnchor !== null ? thumbForWindow(syncAnchor) : null;
        const heldX = anchor !== null ? anchor.heldX : NaN;
        syncAnchor = null;
        syncingScroll = false;
        refreshBounds();
        if (atViewport) {
            flick.contentX = viewportFrame.x - viewportLeft;
        } else if (!isNaN(heldX)) {
            flick.contentX = Layout.clamp(flick.contentX + anchor.layoutX - anchor.insetX - heldX, minContentX(), maxContentX());
        }
        forEachThumb(thumb => { thumb.heldX = NaN; });
        // the thumbnails' bindings have already moved them, only then can they animate again,
        // unless syncing again already, see below
        Qt.callLater(() => {
            if (!row.syncingScroll) {
                row.holdThumbs = false;
            }
        });
        // when still panning, snapToColumn syncs again once it stops
        const resync = resyncAfterSync;
        resyncAfterSync = false;
        if (!panning() && !atViewport) {
            if (resync) {
                snapToColumn();
            } else {
                glideToViewport();
            }
        }
    }

    function glideToViewport() {
        if (syncWhileClosing) {
            // the clicked window on its way to where Karousel put it, starting and ending gently, it can be far;
            // all the way, the strip's ends aren't up to date while the thumbnails are held, so they don't limit it
            const target = viewportFrame.x - viewportLeft;
            bakeHeld();
            glideFrom = flick.contentX;
            glideTarget = target;
            glideTo(target, Kirigami.Units.longDuration * 1.5, Easing.InOutCubic);
        } else {
            glideTo(Layout.clamp(viewportFrame.x - viewportLeft, minContentX(), maxContentX()));
        }
    }

    // after clicking a window: Karousel is done moving the windows and the strip has glided to them,
    // the overview can zoom in
    function readyToZoom() {
        return !snapAnimation.running && Date.now() - lastKarouselMove > 40;
    }

    function glideTo(contentX, duration = Kirigami.Units.longDuration, easing = Easing.OutCubic) {
        snapAnimation.stop();
        snapAnimation.duration = duration;
        snapAnimation.easing.type = easing;
        snapAnimation.to = contentX;
        snapAnimation.start();
    }

    function centerOnViewport() {
        scrollTo(viewportFrame.x + viewportFrame.width / 2 - flick.width / 2);
    }

    // keeps the item within the wallpaper, uses where the thumbnail goes, not where its animation currently is
    function ensureVisible(item) {
        const x = item.layoutX ?? item.x;
        const width = item.layoutWidth ?? item.width;
        const left = flick.contentX + viewportLeft;
        if (x < left) {
            scrollTo(x - viewportLeft);
        } else if (x + width > left + viewportWidth) {
            scrollTo(x + width - viewportWidth - viewportLeft);
        }
    }

    // focusing the window makes Karousel scroll to it, like moving focus in Niri's overview
    function ensureWindowVisible(window) {
        const thumb = thumbForWindow(window);
        if (thumb !== null) {
            ensureVisible(thumb);
        }
    }

    function select(item, focus) {
        overviewRoot.selectedWindow = item.window;
        if (focus) {
            focusWindow(item.window);
        }
        // focusing it started a sync, which glides to where Karousel scrolled
        if (!focus || !syncingScroll) {
            ensureVisible(item);
        }
    }

    function selectNeighbour(delta) {
        const items = thumbItems();
        if (items.length === 0) {
            return;
        }
        const index = items.findIndex(thumb => thumb.window === overviewRoot.selectedWindow);
        if (index === -1) {
            select(items[delta > 0 ? 0 : items.length - 1], true);
        } else {
            select(items[Math.max(0, Math.min(items.length - 1, index + delta))], true);
        }
    }

    function selectClosestToViewport(focus) {
        const center = flick.contentX + flick.width / 2;
        let closest = null;
        for (const thumb of thumbItems()) {
            if (closest === null || Math.abs(thumb.x + thumb.width / 2 - center) < Math.abs(closest.x + closest.width / 2 - center)) {
                closest = thumb;
            }
        }
        if (closest !== null) {
            select(closest, focus);
        }
    }

    NumberAnimation {
        id: snapAnimation
        target: flick
        property: "contentX"
        easing.type: Easing.OutCubic
    }

    // Karousel moves the windows one by one after scrolling, the sync is done once they stop moving
    Timer {
        id: syncTimer
        onTriggered: row.finishKarouselSync()
    }

    Timer {
        id: boundsTimer
        interval: 0
        onTriggered: row.updateBounds()
    }

    // waits for a series of scroll events to end
    Timer {
        id: snapTimer
        interval: 200
        onTriggered: row.snapToColumn()
    }

    // right-click and drag pans the row, also over windows, and keeps going after release like a flick
    DragHandler {
        id: panHandler

        property real startContentX: 0
        property real lastVelocity: 0

        target: null
        acceptedButtons: Qt.RightButton
        yAxis.enabled: false
        grabPermissions: PointerHandler.CanTakeOverFromAnything

        onActiveChanged: {
            if (active) {
                snapAnimation.stop();
                flick.cancelFlick();
                startContentX = flick.contentX;
                lastVelocity = 0;
            } else if (Math.abs(lastVelocity) > 100) {
                flick.flick(lastVelocity, 0);
            } else {
                row.snapToColumn();
            }
        }
        onTranslationChanged: {
            if (active) {
                row.scrollTo(startContentX - translation.x);
            }
        }
        onCentroidChanged: {
            if (active) {
                lastVelocity = centroid.velocity.x;
            }
        }
    }

    KWinComponents.WindowFilterModel {
        id: windowFilterModel
        activity: KWinComponents.Workspace.currentActivity
        desktop: row.desktop
        filter: row.overviewRoot.searchText
        // with the minimized ones, hidden in the strip, the model doesn't take a window back in when it's restored
        minimizedWindows: true
        windowType: ~KWinComponents.WindowFilterModel.Dock &
                    ~KWinComponents.WindowFilterModel.Desktop &
                    ~KWinComponents.WindowFilterModel.Notification &
                    ~KWinComponents.WindowFilterModel.CriticalNotification
        windowModel: KWinComponents.WindowModel {}
    }

    KWinComponents.WindowFilterModel {
        id: minimizedFilterModel
        activity: KWinComponents.Workspace.currentActivity
        desktop: row.desktop
        filter: row.overviewRoot.searchText
        minimizedWindows: true
        windowType: KWinComponents.WindowFilterModel.Normal | KWinComponents.WindowFilterModel.Dialog
        windowModel: KWinComponents.WindowModel {}
    }

    // the whole row lights up when a dragged window would move to this desktop, otherwise there's only the wallpaper
    Rectangle {
        width: row.width
        height: row.height
        visible: row.desktop !== null && row.moveHint
        color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
        border.width: 3
        border.color: Kirigami.Theme.highlightColor
        radius: Kirigami.Units.cornerRadius
        opacity: row.overviewRoot.zoom
    }

    // how far the wallpaper card seems to float above the overview, the selected desktop higher, the new desktop card lower
    property real elevation: desktop === null ? 0.5 : selected ? 2 : 1
    Behavior on elevation {
        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
    }

    // a shadow under the wallpaper instead of a frame around it, like Material's elevation: a tight ambient shadow
    // all around, and a soft one cast downwards that grows with the elevation
    Kirigami.ShadowedRectangle {
        x: row.cardLeft
        width: row.cardWidth
        height: row.height
        color: "transparent"
        radius: row.wallpaperRadius
        shadow.size: Kirigami.Units.gridUnit * 0.5
        shadow.color: Qt.rgba(0, 0, 0, 0.2)
        opacity: row.overviewRoot.zoom
    }

    Kirigami.ShadowedRectangle {
        x: row.cardLeft
        width: row.cardWidth
        height: row.height
        // only the shadow, a filling would show at the wallpaper's antialiased edges
        color: "transparent"
        radius: row.wallpaperRadius
        // lower than the windows on it, see WindowThumb
        shadow.size: Kirigami.Units.gridUnit * (0.5 + 0.75 * row.elevation)
        shadow.yOffset: Kirigami.Units.gridUnit * 0.25 * row.elevation
        shadow.color: Qt.rgba(0, 0, 0, 0.12 + 0.1 * row.elevation)
        opacity: row.overviewRoot.zoom
    }

    // the desktop's own wallpaper behind the part of the strip that is visible on screen, like Niri's workspaces,
    // the new desktop card shows the current desktop's, see-through, an empty desktop that isn't there yet
    Item {
        x: row.cardLeft
        width: row.cardWidth
        height: row.height
        clip: true
        opacity: row.desktop !== null ? 1 : (row.selected ? 0.6 : 0.35)
        layer.enabled: row.wallpaperRadius > 0
        layer.effect: RoundedCorners {
            radius: row.wallpaperRadius
        }

        KWinComponents.DesktopBackground {
            id: wallpaperItem
            width: row.screenGeometry.width
            height: row.screenGeometry.height
            scale: row.cardWidth / Math.max(1, row.screenGeometry.width)
            transformOrigin: Item.TopLeft
            activity: KWinComponents.Workspace.currentActivity
            desktop: row.desktop ?? KWinComponents.Workspace.currentDesktop
            outputName: row.overviewRoot.targetScreen.name
        }
    }

    // highlights the new desktop card when a dragged window would go to a new desktop
    Rectangle {
        x: row.cardLeft
        width: row.cardWidth
        height: row.height
        visible: row.desktop === null && row.moveHint
        color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
        border.width: 3
        border.color: Kirigami.Theme.highlightColor
        radius: row.wallpaperRadius
    }

    Flickable {
        id: flick
        anchors.fill: parent
        // not clipped, so that the wallpaper's shadow shows above and below the row
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: row.overviewRoot.draggedWindow === null
        contentWidth: Math.max((row.stripMaxX - row.stripMinX) * row.thumbScale + 2 * row.padding, row.minimizedEnd + row.padding)
        contentHeight: height
        leftMargin: row.viewportLeft
        rightMargin: row.viewportLeft

        onMovementEnded: row.snapToColumn()
        onFlickEnded: row.snapToColumn()

        Item {
            width: flick.contentWidth
            height: flick.contentHeight

            TapHandler {
                onTapped: row.overviewRoot.switchToDesktop(row.desktop)
            }
        }

        // the part of the strip that is visible on screen, where the wallpaper and its shadow go, not drawn itself
        Item {
            id: viewportFrame
            x: row.toStripX(row.screenGeometry.x)
            width: row.screenGeometry.width * row.thumbScale
            height: row.height
        }

        // frames around columns with more than one window
        Repeater {
            model: row.columns.filter(column => column.windows.length > 1)

            Rectangle {
                required property var modelData

                x: row.toStripX(modelData.x) - Kirigami.Units.smallSpacing
                y: (modelData.y - row.screenGeometry.y) * row.thumbScale - Kirigami.Units.smallSpacing
                width: modelData.width * row.thumbScale + 2 * Kirigami.Units.smallSpacing
                height: (modelData.bottom - modelData.y) * row.thumbScale + 2 * Kirigami.Units.smallSpacing
                color: row.style.foregroundAlpha(0.05)
                radius: Kirigami.Units.cornerRadius
                border.width: 1
                border.color: row.style.foregroundAlpha(0.3)
                opacity: row.overviewRoot.zoom
            }
        }

        // the column a dragged window would join
        Rectangle {
            x: row.stackHint !== null ? row.stackHint.x : 0
            y: row.stackHint !== null ? row.stackHint.y : 0
            width: row.stackHint !== null ? row.stackHint.width : 0
            height: row.stackHint !== null ? row.stackHint.height : 0
            z: 100000
            radius: Kirigami.Units.cornerRadius
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.3)
            border.width: 3
            border.color: Kirigami.Theme.highlightColor
            visible: row.stackHint !== null
        }

        // where a dragged column goes: a glowing pill that slides between the columns and fades in and out
        Kirigami.ShadowedRectangle {
            id: insertHint

            readonly property bool shown: !isNaN(row.insertHintX)
            // stays where it was while fading out
            property real hintX: 0

            x: hintX - width / 2
            y: row.height * 0.1
            z: 100000
            width: Kirigami.Units.smallSpacing * 1.5
            height: row.height * 0.8
            radius: width / 2
            color: Kirigami.Theme.highlightColor
            shadow.size: Kirigami.Units.gridUnit
            shadow.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.6)
            opacity: shown ? 1 : 0
            visible: opacity > 0

            Connections {
                target: row
                function onInsertHintXChanged() {
                    if (!isNaN(row.insertHintX)) {
                        insertHint.hintX = row.insertHintX;
                    }
                }
            }

            Behavior on opacity {
                NumberAnimation { duration: Kirigami.Units.shortDuration }
            }
            Behavior on hintX {
                enabled: insertHint.shown
                NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
            }
        }

        Repeater {
            id: thumbs
            model: row.desktop !== null ? windowFilterModel : null

            delegate: WindowThumb {
                // the linter doesn't match a component's own type inside its file
                strip: row // qmllint disable incompatible-type
                overviewRoot: row.overviewRoot
            }

            onItemAdded: row.scheduleUpdateBounds()
            onItemRemoved: row.scheduleUpdateBounds()
        }

        // minimized windows, smaller and dimmed after the strip, click one to restore it
        Repeater {
            id: minimizedThumbs
            model: row.showMinimized ? minimizedFilterModel : null

            delegate: Item {
                id: minimizedThumb

                required property var window
                property real slotX: 0

                x: slotX
                y: (row.height - height) / 2
                width: window.frameGeometry.width * row.thumbScale * 0.6
                height: window.frameGeometry.height * row.thumbScale * 0.6
                visible: window.minimized && (!row.overviewRoot.multipleScreens || window.output === row.overviewRoot.targetScreen)
                opacity: (minimizedHover.hovered && row.overviewRoot.draggedWindow === null ? 0.9 : 0.5) * row.overviewRoot.zoom

                Accessible.role: Accessible.Button
                Accessible.name: window.caption

                onVisibleChanged: row.updateMinimized()
                onWidthChanged: row.updateMinimized()

                KWinComponents.WindowThumbnail {
                    anchors.fill: parent
                    wId: minimizedThumb.window.internalId
                    layer.enabled: row.overviewRoot.windowRadius > 0
                    layer.effect: RoundedCorners {
                        radius: row.overviewRoot.windowRadius * 0.6
                    }
                }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.medium
                    height: width
                    source: "window-minimize"
                }

                HoverHandler {
                    id: minimizedHover
                }

                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: {
                        minimizedThumb.window.minimized = false;
                        row.overviewRoot.focusWindow(minimizedThumb.window);
                    }
                }
            }

            onItemAdded: row.updateMinimized()
            onItemRemoved: row.updateMinimized()
        }
    }

    // on the wallpaper, so in the wallpaper's colours rather than the overview's
    Rectangle {
        anchors.centerIn: parent
        width: Kirigami.Units.iconSizes.large
        height: width
        radius: width / 2
        color: Qt.rgba(0, 0, 0, row.selected ? 0.6 : 0.4)
        opacity: row.overviewRoot.zoom
        visible: row.desktop === null

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.smallMedium
            height: width
            source: "list-add"
            color: "white"
            isMask: true
        }
    }

    // a pill on the wallpaper's top-left corner with the desktop's number and name, double-click to rename,
    // and a button to remove the desktop when it's empty; on the wallpaper, so in the wallpaper's colours
    Rectangle {
        id: pill

        // the default name, a word and the number in any language, only repeats the number
        readonly property bool showName: row.desktop === null || row.editingName || !new RegExp("^\\S+\\s" + row.number + "$").test(row.desktop.name)

        // across the wallpaper's top edge, so that it covers little of the windows
        x: row.cardLeft + Kirigami.Units.smallSpacing
        y: -height / 2
        width: header.implicitWidth + 2 * (showName ? Kirigami.Units.largeSpacing : Kirigami.Units.smallSpacing)
        height: header.implicitHeight + 2 * Kirigami.Units.smallSpacing
        radius: height / 2
        color: Qt.rgba(0, 0, 0, row.selected ? 0.75 : 0.55)
        border.width: row.selected ? 1 : 0
        border.color: Kirigami.Theme.highlightColor
        opacity: row.overviewRoot.zoom

        HoverHandler {
            id: headerHover
        }

        // takes the clicks for itself, so that clicking the pill doesn't switch desktops or close the overview
        TapHandler {
            gesturePolicy: TapHandler.WithinBounds
            onDoubleTapped: {
                if (row.desktop !== null) {
                    row.startRenaming();
                }
            }
        }

        Row {
            id: header
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(Kirigami.Units.iconSizes.small, numberLabel.implicitWidth + Kirigami.Units.smallSpacing)
                height: Kirigami.Units.iconSizes.small
                radius: height / 2
                color: row.selected ? Kirigami.Theme.highlightColor : Qt.rgba(1, 1, 1, 0.25)

                Text {
                    id: numberLabel
                    anchors.centerIn: parent
                    text: row.desktop !== null ? row.number : "+"
                    color: "white"
                    font.bold: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }

            Text {
                id: nameLabel
                anchors.verticalCenter: parent.verticalCenter
                visible: !row.editingName && pill.showName
                text: row.desktop !== null ? row.desktop.name : "New desktop"
                font: Kirigami.Theme.defaultFont
                color: "white"
                opacity: row.selected ? 1 : 0.8
            }

            TextInput {
                id: nameInput
                anchors.verticalCenter: parent.verticalCenter
                visible: row.editingName
                font: nameLabel.font
                color: "white"
                selectByMouse: true
                selectionColor: Kirigami.Theme.highlightColor
                onAccepted: row.finishRenaming(true)
                onActiveFocusChanged: {
                    if (!activeFocus) {
                        row.finishRenaming(true);
                    }
                }
                Keys.onEscapePressed: row.finishRenaming(false)
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Kirigami.Units.iconSizes.small
                height: width
                radius: width / 2
                color: removeHover.hovered ? "#da4453" : Qt.rgba(1, 1, 1, 0.2)
                // the window count is filtered by the search, so don't offer removing while searching
                visible: headerHover.hovered && !row.editingName && row.desktop !== null && row.windowCount === 0
                         && row.overviewRoot.searchText === "" && KWinComponents.Workspace.desktops.length > 1

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "white"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                HoverHandler {
                    id: removeHover
                }

                TapHandler {
                    gesturePolicy: TapHandler.WithinBounds
                    onTapped: KWinComponents.Workspace.removeDesktop(row.desktop)
                }
            }
        }
    }

    Component.onCompleted: {
        updateBounds();
        centerOnViewport();
    }
}
