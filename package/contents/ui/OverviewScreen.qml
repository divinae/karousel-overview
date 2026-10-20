import QtQuick
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import org.kde.milou as Milou
import org.kde.plasma.extras as PlasmaExtras

Item {
    id: overview
    focus: true

    readonly property QtObject targetScreen: KWinComponents.SceneView.screen
    readonly property rect screenGeometry: targetScreen.geometry
    readonly property real rowHeight: Math.round(height * effect.configuration.RowHeight / 100)
    readonly property real thumbScale: screenGeometry.height > 0 ? rowHeight / screenGeometry.height : 1
    readonly property bool multipleScreens: KWinComponents.Workspace.screens.length > 1

    property QtObject selectedWindow: null
    property QtObject draggedWindow: null
    property point dragPosition
    property point dragOffset
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

    function currentDesktop() {
        return KWinComponents.Workspace.currentDesktopForScreen(targetScreen);
    }

    function rowForDesktop(desktop) {
        const index = KWinComponents.Workspace.desktops.indexOf(desktop);
        return index === -1 ? null : rows.itemAtIndex(index);
    }

    function captureZoomOrigin() {
        const row = rowForDesktop(currentDesktop());
        if (row !== null) {
            zoomOrigin = row.viewportFramePosition(rows);
        }
    }

    function createDesktop() {
        const position = KWinComponents.Workspace.desktops.length;
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

    // reorders columns using Karousel's own key bindings, Karousel doesn't expose any other API
    function moveColumn(window, delta) {
        focusWindow(window);
        invokeShortcut.arguments = [delta < 0 ? "karousel-column-move-left" : "karousel-column-move-right"];
        for (let i = 0; i < Math.abs(delta); i++) {
            invokeShortcut.call();
        }
        selectedWindow = window;
    }

    function selectRow(delta) {
        const index = Math.max(0, Math.min(rows.count - 1, rows.currentIndex + delta));
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
        if (row === null) {
            return;
        }
        if (row.hasWindow(window)) {
            const dropCenterX = dragPosition.x - dragOffset.x + window.frameGeometry.width * thumbScale / 2;
            row.reorderColumn(window, dropCenterX);
            return;
        }
        // Karousel picks this up and moves the window to the target desktop's grid
        window.desktops = [row.desktop ?? createDesktop()];
        selectedWindow = window;
        rows.currentIndex = row.index;
    }

    KWinComponents.DBusCall {
        id: invokeShortcut
        service: "org.kde.kglobalaccel"
        path: "/component/kwin"
        method: "invokeShortcut"
    }

    KWinComponents.DesktopBackground {
        id: background
        anchors.fill: parent
        activity: KWinComponents.Workspace.currentActivity
        desktop: overview.currentDesktop()
        outputName: overview.targetScreen.name
    }

    FastBlur {
        anchors.fill: parent
        source: background
        radius: 64
        opacity: overview.zoom
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
        opacity: 0.7 * overview.zoom
    }

    ListView {
        id: rows
        anchors.fill: parent
        // one extra row at the end for creating a new desktop
        model: KWinComponents.Workspace.desktops.length + 1
        spacing: Kirigami.Units.gridUnit * 2
        interactive: overview.draggedWindow === null
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (height - overview.rowHeight) / 2
        preferredHighlightEnd: preferredHighlightBegin + overview.rowHeight
        highlightMoveDuration: effect.animationDuration

        // zoom from the viewport frame of the current desktop's row filling the screen
        readonly property real fullScale: 1 / overview.thumbScale
        transform: [
            Scale {
                xScale: rows.fullScale + (1 - rows.fullScale) * overview.zoom
                yScale: rows.fullScale + (1 - rows.fullScale) * overview.zoom
            },
            Translate {
                x: -rows.fullScale * overview.zoomOrigin.x * (1 - overview.zoom)
                y: -rows.fullScale * overview.zoomOrigin.y * (1 - overview.zoom)
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
            height: overview.rowHeight
            desktop: index < KWinComponents.Workspace.desktops.length ? KWinComponents.Workspace.desktops[index] : null
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

    // vertical scrolling jumps one desktop at a time, horizontal scrolling pans the row under the pointer
    Item {
        anchors.fill: parent
        z: 1
        enabled: !searchResults.active

        WheelHandler {
            property real accumulatedY: 0

            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                let deltaX = event.angleDelta.x;
                let deltaY = event.angleDelta.y;
                if (event.modifiers & Qt.ShiftModifier) {
                    deltaX = deltaY;
                    deltaY = 0;
                }

                if (deltaX !== 0) {
                    const position = rows.mapFromItem(overview, point.position.x, point.position.y);
                    const row = rows.itemAt(position.x + rows.contentX, position.y + rows.contentY) ?? rows.currentItem;
                    row?.scrollBy(-deltaX);
                }

                if (Math.sign(deltaY) !== Math.sign(accumulatedY)) {
                    accumulatedY = 0;
                }
                accumulatedY += deltaY;
                // one mouse wheel notch is 120
                if (Math.abs(accumulatedY) >= 120) {
                    overview.selectRow(accumulatedY > 0 ? -1 : 1);
                    accumulatedY = 0;
                }
                event.accepted = true;
            }
        }
    }

    // panels stay where they are and fade out while zooming out
    Repeater {
        model: KWinComponents.WindowFilterModel {
            desktop: overview.currentDesktop()
            screenName: overview.targetScreen.name
            windowType: KWinComponents.WindowFilterModel.Dock
            windowModel: KWinComponents.WindowModel {}
        }

        KWinComponents.WindowThumbnail {
            required property QtObject window

            wId: window.internalId
            x: window.x - overview.screenGeometry.x
            y: window.y - overview.screenGeometry.y
            z: 2
            width: window.width
            height: window.height
            opacity: 1 - overview.zoom
            visible: !window.hidden && opacity > 0
        }
    }

    // when no window matches the search, search with KRunner instead
    Loader {
        id: searchResults
        active: overview.searchText !== "" && (rows.currentItem === null || rows.currentItem.windowCount === 0)
        anchors.fill: parent
        anchors.topMargin: Kirigami.Units.gridUnit * 4
        z: 3

        sourceComponent: Rectangle {
            readonly property alias resultsView: milouView

            color: Qt.rgba(0, 0, 0, 0.5)

            PlasmaExtras.PlaceholderMessage {
                id: placeholderMessage
                anchors.top: parent.top
                anchors.topMargin: Kirigami.Units.largeSpacing
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No matching windows"
            }

            Milou.ResultsView {
                id: milouView
                anchors.top: placeholderMessage.bottom
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: Kirigami.Units.largeSpacing
                width: parent.width / 2

                // only bind queryString after init is done, otherwise the model sets up its own runner manager first
                property bool initialized: false
                queryString: initialized ? overview.searchText : ""
                Component.onCompleted: initialized = true

                onActivated: effect.deactivate()
            }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Kirigami.Units.gridUnit
        z: 4
        width: searchLabel.implicitWidth + 2 * Kirigami.Units.largeSpacing
        height: searchLabel.implicitHeight + Kirigami.Units.largeSpacing
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.7)
        visible: overview.searchText !== ""

        Text {
            id: searchLabel
            anchors.centerIn: parent
            text: overview.searchText
            color: "white"
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.5
        }
    }

    onSearchTextChanged: Qt.callLater(refreshSelection)

    // the selection follows focus changes from outside the overview, e.g. Karousel's key bindings
    Connections {
        target: KWinComponents.Workspace
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

    Keys.forwardTo: searchResults.item !== null ? [searchResults.item.resultsView] : []
    Keys.onPressed: event => {
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

    Component.onCompleted: {
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
