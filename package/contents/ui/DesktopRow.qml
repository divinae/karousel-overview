import QtQuick
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
    property bool editingName: false
    // panning the current desktop's row scrolls Karousel's real view by whole columns, other rows pan their preview
    readonly property bool scrollsKarousel: overviewRoot.karouselAvailable && desktop !== null && desktop === overviewRoot.activeDesktop
    property real accumulatedPan: 0
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

    function updateBounds() {
        const entries = thumbItems().map(thumb => ({ window: thumb.window, geometry: thumb.window.frameGeometry }));
        const bounds = Layout.stripBounds(screenGeometry, entries.map(entry => entry.geometry));
        stripMinX = bounds.minX;
        stripMaxX = bounds.maxX;
        columns = Layout.computeColumns(entries);
        updateMinimized();
        // Karousel scrolling moves the windows, not the view, keep the view where it is
        if (scrollsKarousel && overviewRoot.draggedWindow === null) {
            centerOnViewport();
        }
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

    function thumbForWindow(window) {
        return thumbItems().find(thumb => thumb.window === window) ?? null;
    }

    function thumbAt(point) {
        for (const thumb of thumbItems()) {
            const position = thumb.mapFromItem(overviewRoot, point.x, point.y);
            if (thumb.contains(position)) {
                return thumb;
            }
        }
        return null;
    }

    function hasWindow(window) {
        return thumbForWindow(window) !== null;
    }

    function viewportFramePosition(item) {
        return viewportFrame.mapToItem(item, 0, 0);
    }

    // where the column of a window dropped at overviewX goes, or null if the window isn't in this row
    function columnDrop(window, overviewX) {
        const source = columns.findIndex(column => column.windows.includes(window));
        if (source === -1) {
            return null;
        }
        const dropX = flick.contentItem.mapFromItem(overviewRoot, overviewX, 0).x;
        const target = Layout.reorderTarget(columns.map(column => toStripX(column.x + column.width / 2)), source, dropX);
        return { source: source, target: target };
    }

    function reorderColumn(window, overviewX) {
        hideInsertHint();
        const drop = columnDrop(window, overviewX);
        if (drop !== null && drop.target !== drop.source) {
            overviewRoot.moveColumn(window, drop.target - drop.source);
        }
    }

    function showInsertHint(window, overviewX) {
        const drop = columnDrop(window, overviewX);
        if (drop === null || drop.target === drop.source) {
            hideInsertHint();
            return;
        }
        const otherColumns = columns.filter((column, i) => i !== drop.source)
            .map(column => ({ left: toStripX(column.x), right: toStripX(column.x + column.width) }));
        insertHintX = Layout.insertHintX(otherColumns, drop.target) ?? NaN;
    }

    function hideInsertHint() {
        insertHintX = NaN;
    }

    function maxContentX() {
        return Math.max(0, flick.contentWidth - flick.width);
    }

    function scrollTo(contentX) {
        snapAnimation.stop();
        if (flick.contentWidth <= flick.width) {
            flick.contentX = -flick.leftMargin;
        } else {
            flick.contentX = Layout.clamp(contentX, 0, maxContentX());
        }
    }

    // settles the row so that the column closest to its left edge lines up with it
    function snapToColumn() {
        if (flick.contentWidth <= flick.width || columns.length === 0 || panHandler.active || flick.moving) {
            return;
        }
        const target = Layout.snapTarget(columns.map(column => toStripX(column.x)), flick.contentX + padding, padding, maxContentX());
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

    // pans by delta pixels, positive moves the content to the right
    function panBy(delta) {
        if (!scrollsKarousel) {
            scrollBy(-delta);
            scheduleSnap();
            return;
        }
        // a step after half of an average column, in the preview
        const averageWidth = columns.length > 0 ? columns.reduce((sum, column) => sum + column.width, 0) / columns.length : screenGeometry.width / 2;
        const pan = Layout.columnScrollSteps(accumulatedPan, delta, averageWidth * thumbScale / 2);
        accumulatedPan = pan.accumulated;
        if (pan.steps !== 0) {
            overviewRoot.scrollKarousel(pan.steps);
        }
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

    function ensureVisible(item) {
        if (item.x - padding < flick.contentX) {
            scrollTo(item.x - padding);
        } else if (item.x + item.width + padding > flick.contentX + flick.width) {
            scrollTo(item.x + item.width + padding - flick.width);
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
        property real lastTranslation: 0

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
                lastTranslation = 0;
                row.accumulatedPan = 0;
            } else if (row.scrollsKarousel) {
                row.accumulatedPan = 0;
            } else if (Math.abs(lastVelocity) > 100) {
                flick.flick(lastVelocity, 0);
            } else {
                row.snapToColumn();
            }
        }
        onTranslationChanged: {
            if (!active) {
                return;
            }
            if (row.scrollsKarousel) {
                row.panBy(translation.x - lastTranslation);
                lastTranslation = translation.x;
            } else {
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
        color: row.style.foregroundAlpha(row.selected ? 0.08 : 0.03)
        radius: Kirigami.Units.cornerRadius
        opacity: row.overviewRoot.zoom
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        // the current desktop's row follows Karousel's view instead
        interactive: row.overviewRoot.draggedWindow === null && !row.scrollsKarousel
        contentWidth: Math.max((row.stripMaxX - row.stripMinX) * row.thumbScale + 2 * row.padding, row.minimizedEnd + row.padding)
        contentHeight: height
        // center strips that are narrower than the row
        leftMargin: Math.max(0, (width - contentWidth) / 2)

        onMovementEnded: row.snapToColumn()
        onFlickEnded: row.snapToColumn()

        Item {
            width: flick.contentWidth
            height: flick.contentHeight

            TapHandler {
                onTapped: row.overviewRoot.switchToDesktop(row.desktop)
            }
        }

        // the desktop's own wallpaper behind the part of the strip that is visible on screen, like Niri's workspaces
        Item {
            x: viewportFrame.x
            width: viewportFrame.width
            height: row.height
            clip: true
            visible: row.desktop !== null

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

        // the part of the strip that is visible on screen
        Rectangle {
            id: viewportFrame
            x: row.toStripX(row.screenGeometry.x)
            width: row.screenGeometry.width * row.thumbScale
            height: row.height
            color: "transparent"
            radius: Kirigami.Units.cornerRadius
            border.width: 2
            border.color: row.style.foregroundAlpha(row.selected ? 0.5 : 0.2)
            opacity: row.overviewRoot.zoom
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

        Rectangle {
            x: row.insertHintX - width / 2
            width: Kirigami.Units.smallSpacing
            height: row.height
            radius: width / 2
            color: Kirigami.Theme.highlightColor
            visible: !isNaN(row.insertHintX)
            z: 1
        }

        Repeater {
            id: thumbs
            model: row.desktop !== null ? windowFilterModel : null

            delegate: WindowThumb {
                strip: row
                overviewRoot: row.overviewRoot
            }

            onItemAdded: row.updateBounds()
            onItemRemoved: row.updateBounds()
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
        // aligned with the viewport frame
        x: Math.max(row.padding, viewportFrame.x - flick.contentX)
        anchors.bottom: parent.top
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        width: header.implicitWidth
        height: header.implicitHeight
        opacity: row.overviewRoot.zoom

        HoverHandler {
            id: headerHover
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

                TapHandler {
                    enabled: row.desktop !== null
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
