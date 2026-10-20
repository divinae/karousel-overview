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

    function toStripX(x) {
        return (x - stripMinX) * thumbScale + padding;
    }

    function updateBounds() {
        const entries = thumbItems().map(thumb => ({ window: thumb.window, geometry: thumb.window.frameGeometry }));
        const bounds = Layout.stripBounds(screenGeometry, entries.map(entry => entry.geometry));
        stripMinX = bounds.minX;
        stripMaxX = bounds.maxX;
        columns = Layout.computeColumns(entries);
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

    function hasWindow(window) {
        return thumbForWindow(window) !== null;
    }

    function viewportFramePosition(item) {
        return viewportFrame.mapToItem(item, 0, 0);
    }

    function reorderColumn(window, overviewX) {
        const source = columns.findIndex(column => column.windows.includes(window));
        if (source === -1) {
            return;
        }
        const dropX = flick.contentItem.mapFromItem(overviewRoot, overviewX, 0).x;
        const target = Layout.reorderTarget(columns.map(column => toStripX(column.x + column.width / 2)), source, dropX);
        if (target !== source) {
            overviewRoot.moveColumn(window, target - source);
        }
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
        interactive: row.overviewRoot.draggedWindow === null
        contentWidth: (row.stripMaxX - row.stripMinX) * row.thumbScale + 2 * row.padding
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
    }

    Text {
        anchors.centerIn: parent
        visible: row.desktop === null
        text: "+"
        color: row.style.foreground
        opacity: (row.selected ? 0.8 : 0.4) * row.overviewRoot.zoom
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 4
    }

    Text {
        // aligned with the viewport frame
        x: Math.max(row.padding, viewportFrame.x - flick.contentX)
        anchors.bottom: parent.top
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        text: row.desktop !== null ? row.desktop.name : "New desktop"
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
        font.bold: row.selected
        color: row.style.foreground
        opacity: (row.selected ? 1 : 0.6) * row.overviewRoot.zoom
    }

    Component.onCompleted: {
        updateBounds();
        centerOnViewport();
    }
}
