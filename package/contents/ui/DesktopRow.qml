import QtQuick
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import "layout.js" as Layout

Item {
    id: row

    // null for the row that creates a new desktop
    required property QtObject desktop
    required property Item overviewRoot
    property bool selected: false

    readonly property rect screenGeometry: overviewRoot.screenGeometry
    readonly property real thumbScale: overviewRoot.thumbScale
    readonly property real padding: Kirigami.Units.gridUnit
    // the desktop's wallpaper stays in the middle of the row, the windows move past it when panning, like in Niri
    readonly property real viewportWidth: screenGeometry.width * thumbScale
    readonly property real viewportLeft: Math.max(0, (width - viewportWidth) / 2)
    // rounded once zoomed out, square when it fills the screen at the start of the zoom
    readonly property real wallpaperRadius: Kirigami.Units.largeSpacing * 1.5 * overviewRoot.zoom
    readonly property QtObject style: overviewRoot.style

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
    // Karousel's view is being moved to match the preview, the windows jump to where they already are in the preview
    property bool syncingScroll: false
    // a window and where it was in the row when the sync started, kept there while Karousel moves the windows
    property var syncAnchor: null
    readonly property bool showMinimized: effect.configuration.ShowMinimized && desktop !== null
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
        boundsTimer.restart();
    }

    function updateBounds() {
        const entries = thumbItems().map(thumb => ({ window: thumb.window, geometry: thumb.window.frameGeometry }));
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
        // Karousel scrolling moves the windows, not the view, keep the view where it is
        if (syncingScroll && syncAnchor !== null) {
            // keep the windows where they were in the preview, then glide to where Karousel actually put them,
            // which can be a bit off, e.g. because of the gaps or the ends of the strip
            const anchor = thumbForWindow(syncAnchor.window);
            if (anchor !== null) {
                flick.contentX = anchor.layoutX - syncAnchor.x;
            }
            snapAnimation.to = Layout.clamp(viewportFrame.x + viewportFrame.width / 2 - flick.width / 2, minContentX(), maxContentX());
            snapAnimation.restart();
        } else if (scrollsKarousel && overviewRoot.draggedWindow === null && !panning()) {
            centerOnViewport();
        } else if (overviewRoot.selectedWindow !== null) {
            ensureWindowVisible(overviewRoot.selectedWindow);
        }
    }

    // Karousel's columns on this desktop, from all of its windows, also those hidden by the search,
    // so that the indexes match Karousel's when driving it through its key bindings
    function karouselColumns() {
        const activity = KWinComponents.Workspace.currentActivity;
        const entries = KWinComponents.Workspace.windows
            .filter(window => window.normalWindow && !window.minimized
                && window.desktops.length === 1 && window.desktops[0] === desktop
                && (window.activities.length === 0 || window.activities.includes(activity)))
            .map(window => ({ window: window, geometry: window.frameGeometry }));
        return Layout.computeColumns(entries);
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
        items.sort((a, b) => a.window.frameGeometry.x - b.window.frameGeometry.x || a.window.frameGeometry.y - b.window.frameGeometry.y);
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
            syncKarouselScroll();
            return;
        }
        const target = Layout.snapTarget(columns.map(column => toStripX(column.x)), flick.contentX + viewportLeft, viewportLeft, minContentX(), maxContentX());
        if (target !== null) {
            snapAnimation.to = target;
            snapAnimation.restart();
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
            snapAnimation.to = Layout.clamp(viewportFrame.x - viewportLeft, minContentX(), maxContentX());
            snapAnimation.restart();
            return;
        }
        const anchor = thumbItems().reduce((best, thumb) => best === null
            || Math.abs(thumb.layoutX - flick.contentX - viewportLeft) < Math.abs(best.layoutX - flick.contentX - viewportLeft) ? thumb : best, null);
        syncAnchor = anchor === null ? null : { window: anchor.window, x: anchor.layoutX - flick.contentX };
        syncingScroll = true;
        syncTimer.restart();
        overviewRoot.scrollKarousel(steps);
    }

    function centerOnViewport() {
        scrollTo(viewportFrame.x + viewportFrame.width / 2 - flick.width / 2);
    }

    function centerOnWindow(window) {
        const thumb = thumbForWindow(window);
        if (thumb !== null) {
            scrollTo(thumb.x + thumb.width / 2 - flick.width / 2);
        }
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
            overviewRoot.focusWindow(item.window);
        }
        ensureVisible(item);
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
        duration: Kirigami.Units.longDuration
        easing.type: Easing.OutCubic
    }

    // Karousel moves the windows one by one after scrolling
    Timer {
        id: syncTimer
        interval: Kirigami.Units.longDuration * 2
        onTriggered: {
            row.syncingScroll = false;
            row.syncAnchor = null;
        }
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
        minimizedWindows: false
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

    Rectangle {
        anchors.fill: parent
        color: row.moveHint ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                            : row.style.foregroundAlpha(row.selected ? 0.08 : 0.03)
        border.width: row.moveHint ? 3 : 0
        border.color: Kirigami.Theme.highlightColor
        radius: Kirigami.Units.cornerRadius
        opacity: row.overviewRoot.zoom
    }

    // a shadow under the wallpaper instead of a frame around it
    Kirigami.ShadowedRectangle {
        x: row.viewportLeft
        width: row.viewportWidth
        height: row.height
        // behind the wallpaper, only seen while it loads
        color: Kirigami.Theme.backgroundColor
        radius: row.wallpaperRadius
        shadow.size: Kirigami.Units.gridUnit * 1.5
        shadow.color: Qt.rgba(0, 0, 0, row.selected ? 0.5 : 0.3)
        opacity: row.overviewRoot.zoom
        visible: row.desktop !== null
    }

    // the desktop's own wallpaper behind the part of the strip that is visible on screen, like Niri's workspaces
    Item {
        x: row.viewportLeft
        width: row.viewportWidth
        height: row.height
        clip: true
        visible: row.desktop !== null
        layer.enabled: row.wallpaperRadius > 0
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: row.viewportWidth
                height: row.height
                radius: row.wallpaperRadius
            }
        }

        KWinComponents.DesktopBackground {
            width: row.screenGeometry.width
            height: row.screenGeometry.height
            scale: row.thumbScale
            transformOrigin: Item.TopLeft
            activity: KWinComponents.Workspace.currentActivity
            desktop: row.desktop
            outputName: row.overviewRoot.targetScreen.name
        }
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

        Rectangle {
            x: row.insertHintX - width / 2
            width: Kirigami.Units.smallSpacing
            height: row.height
            radius: width / 2
            color: Kirigami.Theme.highlightColor
            visible: !isNaN(row.insertHintX)
            z: 100000
        }

        Repeater {
            id: thumbs
            model: row.desktop !== null ? windowFilterModel : null

            delegate: WindowThumb {
                strip: row
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

                required property QtObject window
                property real slotX: 0

                x: slotX
                y: (row.height - height) / 2
                width: window.frameGeometry.width * row.thumbScale * 0.6
                height: window.frameGeometry.height * row.thumbScale * 0.6
                visible: window.minimized && (!row.overviewRoot.multipleScreens || window.output === row.overviewRoot.targetScreen)
                opacity: (minimizedHover.hovered ? 0.9 : 0.5) * row.overviewRoot.zoom

                Accessible.role: Accessible.Button
                Accessible.name: window.caption

                onVisibleChanged: row.updateMinimized()
                onWidthChanged: row.updateMinimized()

                KWinComponents.WindowThumbnail {
                    anchors.fill: parent
                    wId: minimizedThumb.window.internalId
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

    Text {
        anchors.centerIn: parent
        visible: row.desktop === null
        text: "+"
        color: row.style.foreground
        opacity: (row.selected ? 0.8 : 0.4) * row.overviewRoot.zoom
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 4
    }

    // the desktop's name, double-click to rename, and a button to remove it when it's empty
    Item {
        // aligned with the wallpaper
        x: Math.max(row.padding, row.viewportLeft)
        anchors.bottom: parent.top
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        width: header.implicitWidth
        height: header.implicitHeight
        opacity: row.overviewRoot.zoom

        HoverHandler {
            id: headerHover
        }

        // the header is outside the row, between rows, where a click would close the overview
        TapHandler {
            gesturePolicy: TapHandler.WithinBounds
        }

        Row {
            id: header
            spacing: Kirigami.Units.smallSpacing

            Text {
                id: nameLabel
                visible: !row.editingName
                text: row.desktop !== null ? row.desktop.name : "New desktop"
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                font.bold: row.selected
                color: row.style.foreground
                opacity: row.selected ? 1 : 0.6

                // takes the clicks for itself, so that clicking the name doesn't close the overview
                TapHandler {
                    enabled: row.desktop !== null
                    gesturePolicy: TapHandler.WithinBounds
                    onDoubleTapped: row.startRenaming()
                }
            }

            TextInput {
                id: nameInput
                visible: row.editingName
                font: nameLabel.font
                color: row.style.foreground
                selectByMouse: true
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
                color: removeHover.hovered ? "#da4453" : row.style.foregroundAlpha(0.2)
                // the window count is filtered by the search, so don't offer removing while searching
                visible: headerHover.hovered && !row.editingName && row.desktop !== null && row.windowCount === 0
                         && row.overviewRoot.searchText === "" && KWinComponents.Workspace.desktops.length > 1

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: removeHover.hovered ? "white" : row.style.foreground
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
