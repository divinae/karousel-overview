import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

Item {
    id: row

    // null for the row that creates a new desktop
    required property QtObject desktop
    required property Item overviewRoot
    property bool selected: false

    readonly property rect screenGeometry: overviewRoot.screenGeometry
    readonly property real thumbScale: overviewRoot.thumbScale
    readonly property real padding: Kirigami.Units.gridUnit

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
        let minX = screenGeometry.x;
        let maxX = screenGeometry.x + screenGeometry.width;
        const columnMap = new Map();
        for (const thumb of thumbItems()) {
            const geometry = thumb.window.frameGeometry;
            minX = Math.min(minX, geometry.x);
            maxX = Math.max(maxX, geometry.x + geometry.width);

            // windows in the same Karousel column share x and width
            const key = Math.round(geometry.x) + ":" + Math.round(geometry.width);
            const column = columnMap.get(key);
            if (column === undefined) {
                columnMap.set(key, { x: geometry.x, y: geometry.y, width: geometry.width, bottom: geometry.y + geometry.height, windows: [thumb.window] });
            } else {
                column.y = Math.min(column.y, geometry.y);
                column.bottom = Math.max(column.bottom, geometry.y + geometry.height);
                column.windows.push(thumb.window);
            }
        }
        stripMinX = minX;
        stripMaxX = maxX;
        columns = Array.from(columnMap.values()).sort((a, b) => a.x - b.x);
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
        let target = 0;
        columns.forEach((column, i) => {
            if (i !== source && toStripX(column.x + column.width / 2) < dropX) {
                target++;
            }
        });
        if (target !== source) {
            overviewRoot.moveColumn(window, target - source);
        }
    }

    function scrollTo(contentX) {
        if (flick.contentWidth <= flick.width) {
            flick.contentX = -flick.leftMargin;
        } else {
            flick.contentX = Math.max(0, Math.min(contentX, flick.contentWidth - flick.width));
        }
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

    function select(item) {
        overviewRoot.selectedWindow = item.window;
        ensureVisible(item);
    }

    function selectNeighbour(delta) {
        const items = thumbItems();
        if (items.length === 0) {
            return;
        }
        const index = items.findIndex(thumb => thumb.window === overviewRoot.selectedWindow);
        if (index === -1) {
            select(items[delta > 0 ? 0 : items.length - 1]);
        } else {
            select(items[Math.max(0, Math.min(items.length - 1, index + delta))]);
        }
    }

    function selectClosestToViewport() {
        const center = flick.contentX + flick.width / 2;
        let closest = null;
        for (const thumb of thumbItems()) {
            if (closest === null || Math.abs(thumb.x + thumb.width / 2 - center) < Math.abs(closest.x + closest.width / 2 - center)) {
                closest = thumb;
            }
        }
        if (closest !== null) {
            select(closest);
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
        color: Qt.rgba(1, 1, 1, row.selected ? 0.08 : 0.03)
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
            border.color: Qt.rgba(1, 1, 1, row.selected ? 0.5 : 0.2)
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
                color: Qt.rgba(1, 1, 1, 0.05)
                radius: Kirigami.Units.cornerRadius
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.3)
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
        color: "white"
        opacity: (row.selected ? 0.8 : 0.4) * row.overviewRoot.zoom
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 4
    }

    Text {
        anchors.left: parent.left
        anchors.bottom: parent.top
        anchors.leftMargin: row.padding
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        text: row.desktop !== null ? row.desktop.name : "New desktop"
        color: "white"
        opacity: (row.selected ? 1 : 0.6) * row.overviewRoot.zoom
    }

    Component.onCompleted: {
        updateBounds();
        centerOnViewport();
    }
}
