import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

Item {
    id: row

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

    function toStripX(x) {
        return (x - stripMinX) * thumbScale + padding;
    }

    function updateBounds() {
        let minX = screenGeometry.x;
        let maxX = screenGeometry.x + screenGeometry.width;
        for (const thumb of thumbItems()) {
            const geometry = thumb.window.frameGeometry;
            minX = Math.min(minX, geometry.x);
            maxX = Math.max(maxX, geometry.x + geometry.width);
        }
        stripMinX = minX;
        stripMaxX = maxX;
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

    function hasWindow(window) {
        return thumbItems().some(thumb => thumb.window === window);
    }

    function scrollTo(contentX) {
        if (flick.contentWidth <= flick.width) {
            flick.contentX = -flick.leftMargin;
        } else {
            flick.contentX = Math.max(0, Math.min(contentX, flick.contentWidth - flick.width));
        }
    }

    function centerOnViewport() {
        scrollTo(viewportFrame.x + viewportFrame.width / 2 - flick.width / 2);
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

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(1, 1, 1, row.selected ? 0.08 : 0.03)
        radius: Kirigami.Units.cornerRadius
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
        }

        Repeater {
            id: thumbs
            model: KWinComponents.WindowFilterModel {
                activity: KWinComponents.Workspace.currentActivity
                desktop: row.desktop
                minimizedWindows: false
                windowType: ~KWinComponents.WindowFilterModel.Dock &
                            ~KWinComponents.WindowFilterModel.Desktop &
                            ~KWinComponents.WindowFilterModel.Notification &
                            ~KWinComponents.WindowFilterModel.CriticalNotification
                windowModel: KWinComponents.WindowModel {}
            }

            delegate: WindowThumb {
                strip: row
                overviewRoot: row.overviewRoot
            }

            onItemAdded: row.updateBounds()
            onItemRemoved: row.updateBounds()
        }
    }

    Text {
        anchors.left: parent.left
        anchors.bottom: parent.top
        anchors.leftMargin: row.padding
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        text: row.desktop.name
        color: "white"
        opacity: row.selected ? 1 : 0.6
    }

    Component.onCompleted: {
        updateBounds();
        centerOnViewport();
    }
}
