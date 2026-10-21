pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import "i18n.js" as I18n

// above a column with more than one window: a handle to drag the whole column by, and a button between Karousel's
// stacked layout and the windows one under another
Item {
    id: columnBar

    required property var modelData
    required property DesktopRow strip
    // the row goes away first when its desktop is removed
    readonly property bool alive: strip !== null
    readonly property bool dragged: alive && columnBar.strip.overviewRoot.draggedWindows.some(window => modelData.windows.includes(window))
    readonly property bool stacked: alive && columnBar.strip.isStackedColumn(modelData)
    // the whole strip above the column grabs it, the pill shows where; it sticks out below the strip, so it grabs too
    readonly property bool lit: stripHover.hovered || stripDrag.active || gripHover.hovered || gripDrag.active

    function dragChanged(handler) {
        const windows = modelData.windows;
        if (handler.active) {
            strip.overviewRoot.startDrag(windows[0], strip.thumbForWindow(windows[0]), handler.centroid.scenePressPosition, windows);
        } else {
            strip.overviewRoot.endDrag();
        }
    }

    function dragMoved(handler) {
        if (handler.active) {
            strip.overviewRoot.moveDrag(handler.centroid.scenePosition);
        }
    }

    // where to grab it, shown while the pointer is there
    Rectangle {
        anchors.fill: parent
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: columnBar.alive ? columnBar.strip.style.highlightAlpha(0.2) : "transparent"
        opacity: columnBar.lit ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }
    }

    HoverHandler {
        id: stripHover
        cursorShape: Qt.SizeAllCursor
    }

    DragHandler {
        id: stripDrag
        target: null
        // don't let the Flickables or the window under it steal the drag, see WindowThumb
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onActiveChanged: columnBar.dragChanged(stripDrag)
        onCentroidChanged: columnBar.dragMoved(stripDrag)
    }

    x: alive ? columnBar.strip.toStripX(modelData.x) : 0
    // right above the column's frame
    y: alive ? (modelData.y - columnBar.strip.screenGeometry.y) * columnBar.strip.thumbScale - Kirigami.Units.smallSpacing - height : 0
    z: 100000
    width: alive ? modelData.width * columnBar.strip.thumbScale : 0
    height: Kirigami.Units.gridUnit * 1.5
    opacity: alive ? (columnBar.strip.overviewRoot.draggedWindow === null || dragged ? 1 : 0) * columnBar.strip.overviewRoot.zoom : 0
    visible: opacity > 0

    // Karousel rearranging recreates them, the drag would never end without the DragHandler that tracks it
    Component.onDestruction: {
        if ((gripDrag.active || stripDrag.active) && alive) {
            columnBar.strip.overviewRoot.cancelDrag();
        }
    }

    // a pill with two rows of three dots, the usual sign for something to drag, on the frame's top edge,
    // floating like the windows
    Kirigami.ShadowedRectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.bottom
        // roomy around the dots, the whole pill grabs
        width: Kirigami.Units.gridUnit * 3.5
        height: Kirigami.Units.gridUnit * 1.4
        radius: height / 2
        color: columnBar.lit ? Kirigami.Theme.highlightColor : Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: columnBar.lit || !columnBar.alive ? Kirigami.Theme.highlightColor : columnBar.strip.style.foregroundAlpha(0.2)
        shadow.size: Kirigami.Units.gridUnit * (columnBar.lit ? 1 : 0.6)
        shadow.yOffset: Kirigami.Units.smallSpacing / 2
        shadow.color: !columnBar.alive ? "transparent" : columnBar.lit ? columnBar.strip.style.highlightAlpha(0.6)
            : Qt.rgba(0, 0, 0, 0.3)

        Accessible.role: Accessible.Grip
        Accessible.name: I18n.tr("Move column")

        Behavior on color {
            ColorAnimation { duration: Kirigami.Units.shortDuration }
        }

        Grid {
            anchors.centerIn: parent
            rows: 2
            columns: 3
            spacing: Math.round(Kirigami.Units.smallSpacing * 0.75)

            Repeater {
                model: 6

                Rectangle {
                    width: Math.round(Kirigami.Units.smallSpacing * 0.9)
                    height: width
                    radius: width / 2
                    color: columnBar.lit ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                    opacity: columnBar.lit ? 1 : 0.55
                }
            }
        }

        HoverHandler {
            id: gripHover
            cursorShape: Qt.SizeAllCursor
        }

        DragHandler {
            id: gripDrag
            target: null
            // don't let the Flickables or the window under it steal the drag, see WindowThumb
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            onActiveChanged: columnBar.dragChanged(gripDrag)
            onCentroidChanged: columnBar.dragMoved(gripDrag)
        }
    }

    // stacked or one under another, with what clicking makes of it; in the column's top left corner,
    // the windows' own buttons are on the right
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.bottom
        anchors.margins: Kirigami.Units.smallSpacing * 2
        width: layoutLabel.implicitWidth + 2 * Kirigami.Units.largeSpacing
        height: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
        radius: height / 2
        color: layoutHover.hovered ? Kirigami.Theme.highlightColor : Qt.rgba(0, 0, 0, 0.7)
        visible: columnBar.alive && columnBar.strip.overviewRoot.draggedWindow === null

        Accessible.role: Accessible.Button
        Accessible.name: layoutText.text

        Row {
            id: layoutLabel
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: Kirigami.Units.iconSizes.small
                height: width
                source: columnBar.stacked ? "view-split-top-bottom" : "window-duplicate"
                color: "white"
                isMask: true
            }

            Text {
                id: layoutText
                anchors.verticalCenter: parent.verticalCenter
                text: columnBar.stacked ? I18n.trc("@action:button the windows of a column", "Unstack") : I18n.trc("@action:button the windows of a column", "Stack")
                color: "white"
            }
        }

        HoverHandler {
            id: layoutHover
        }

        TapHandler {
            gesturePolicy: TapHandler.WithinBounds
            onTapped: columnBar.strip.overviewRoot.karousel.toggleStacked(columnBar.modelData.windows[0])
        }
    }
}
