import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

Item {
    id: overview
    focus: true

    readonly property QtObject targetScreen: KWinComponents.SceneView.screen
    readonly property rect screenGeometry: targetScreen.geometry
    readonly property real rowHeight: Math.round(height * effect.configuration.RowHeight / 100)
    readonly property real thumbScale: rowHeight / screenGeometry.height

    property QtObject selectedWindow: null
    property QtObject draggedWindow: null
    property point dragPosition
    property point dragOffset

    function currentDesktop() {
        return KWinComponents.Workspace.currentDesktopForScreen(targetScreen);
    }

    function switchToDesktop(desktop) {
        if (desktop !== currentDesktop()) {
            KWinComponents.Workspace.setCurrentDesktopForScreen(desktop, targetScreen);
        }
        effect.deactivate();
    }

    function activateWindow(window) {
        if (window.desktops.length === 1 && window.desktops[0] !== currentDesktop()) {
            KWinComponents.Workspace.setCurrentDesktopForScreen(window.desktops[0], targetScreen);
        }
        KWinComponents.Workspace.activeWindow = window;
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

    function selectRow(delta) {
        const index = Math.max(0, Math.min(rows.count - 1, rows.currentIndex + delta));
        if (index === rows.currentIndex) {
            return;
        }
        rows.currentIndex = index;
        rows.currentItem.selectClosestToViewport();
    }

    function startDrag(window, item, scenePosition) {
        const itemPosition = item.mapToItem(overview, 0, 0);
        dragPosition = overview.mapFromItem(null, scenePosition.x, scenePosition.y);
        dragOffset = Qt.point(dragPosition.x - itemPosition.x, dragPosition.y - itemPosition.y);
        draggedWindow = window;
    }

    function moveDrag(scenePosition) {
        dragPosition = overview.mapFromItem(null, scenePosition.x, scenePosition.y);
    }

    function endDrag() {
        const window = draggedWindow;
        draggedWindow = null;
        if (window === null) {
            return;
        }
        const position = rows.mapFromItem(overview, dragPosition.x, dragPosition.y);
        const row = rows.itemAt(position.x + rows.contentX, position.y + rows.contentY);
        if (row === null || row.hasWindow(window)) {
            return;
        }
        // Karousel picks this up and moves the window to the target desktop's grid
        window.desktops = [row.desktop];
        selectedWindow = window;
        rows.currentIndex = row.index;
    }

    KWinComponents.DesktopBackground {
        anchors.fill: parent
        activity: KWinComponents.Workspace.currentActivity
        desktop: overview.currentDesktop()
        outputName: overview.targetScreen.name
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: effect.activated ? 0.6 : 0
        Behavior on opacity {
            NumberAnimation { duration: effect.animationDuration; easing.type: Easing.OutCubic }
        }
    }

    ListView {
        id: rows
        anchors.fill: parent
        model: KWinComponents.Workspace.desktops
        spacing: Kirigami.Units.gridUnit * 2
        interactive: overview.draggedWindow === null
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (height - overview.rowHeight) / 2
        preferredHighlightEnd: preferredHighlightBegin + overview.rowHeight
        highlightMoveDuration: effect.animationDuration

        opacity: effect.activated ? 1 : 0
        scale: effect.activated ? 1 : 1.15
        Behavior on opacity {
            NumberAnimation { duration: effect.animationDuration; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: effect.animationDuration; easing.type: Easing.OutCubic }
        }

        delegate: DesktopRow {
            required property int index
            required property QtObject modelData

            width: rows.width
            height: overview.rowHeight
            desktop: modelData
            overviewRoot: overview
            selected: ListView.isCurrentItem
        }
    }

    Loader {
        active: overview.draggedWindow !== null
        z: 1
        x: overview.dragPosition.x - overview.dragOffset.x
        y: overview.dragPosition.y - overview.dragOffset.y
        sourceComponent: KWinComponents.WindowThumbnail {
            wId: overview.draggedWindow.internalId
            width: overview.draggedWindow.frameGeometry.width * overview.thumbScale
            height: overview.draggedWindow.frameGeometry.height * overview.thumbScale
            opacity: 0.8
        }
    }

    Keys.onEscapePressed: effect.deactivate()
    Keys.onUpPressed: selectRow(-1)
    Keys.onDownPressed: selectRow(1)
    Keys.onLeftPressed: rows.currentItem?.selectNeighbour(-1)
    Keys.onRightPressed: rows.currentItem?.selectNeighbour(1)
    Keys.onReturnPressed: activateSelected()
    Keys.onEnterPressed: activateSelected()
    Keys.onSpacePressed: activateSelected()

    Component.onCompleted: {
        selectedWindow = KWinComponents.Workspace.activeWindow;
        const index = KWinComponents.Workspace.desktops.indexOf(currentDesktop());
        rows.currentIndex = Math.max(0, index);
        rows.positionViewAtIndex(rows.currentIndex, ListView.Center);
    }
}
