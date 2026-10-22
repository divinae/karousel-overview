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
    // the whole strip above the column grabs it, the pill in it shows where
    readonly property bool lit: stripHover.hovered || stripDrag.active
    // between the strip and the column
    readonly property real gap: Kirigami.Units.smallSpacing

    Accessible.role: Accessible.Grip
    Accessible.name: I18n.tr("Move column")

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

    // what grabbing it moves: a frame around the whole column, from the middle of the pill, which sits on its top edge
    // like a tab, which lights up while the pointer is on the strip; not while Karousel moves the windows and their
    // thumbnails are held in place, nor while a window is dragged, it wouldn't be around them meanwhile
    Item {
        id: frame

        // around the windows' thumbnails, which are inset within the column, see WindowThumb, and within half of the gap
        // between columns, so that the frames of neighbours don't cross
        readonly property real inset: columnBar.alive
            ? Math.min(columnBar.strip.overviewRoot.horizontalGap * (1 - columnBar.strip.thumbScale) / 2, columnBar.modelData.width * columnBar.strip.thumbScale / 4) : 0
        readonly property real padding: columnBar.alive
            ? Math.max(1, Math.min(Kirigami.Units.smallSpacing, columnBar.strip.overviewRoot.horizontalGap / 2 - 1)) : 0
        // the piece of the frame under the pill, left out
        readonly property real cutLeft: (width - pill.width) / 2
        readonly property real cutRight: (width + pill.width) / 2

        x: inset - padding
        y: parent.height / 2
        width: parent.width - 2 * inset + 2 * padding
        height: columnBar.alive ? parent.height / 2 + columnBar.gap + (columnBar.modelData.bottom - columnBar.modelData.y) * columnBar.strip.thumbScale + padding : 0
        opacity: columnBar.alive && (columnBar.strip.holdThumbs || columnBar.strip.overviewRoot.draggedWindow !== null) ? 0 : columnBar.appeared
        visible: opacity > 0

        Behavior on opacity {
            enabled: !fadeIn.running
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }

        // in three pieces, left of the pill, right of it and below it, so that its top edge doesn't show through the
        // see-through pill
        component Piece: Item {
            clip: true

            Rectangle {
                x: -parent.x
                y: -parent.y
                width: frame.width
                height: frame.height
                radius: Kirigami.Units.cornerRadius * 2
                color: columnBar.alive && columnBar.lit ? columnBar.strip.style.highlightAlpha(0.12) : "transparent"
                border.width: columnBar.lit ? 2 : 1.5
                border.color: columnBar.lit || !columnBar.alive ? Kirigami.Theme.highlightColor : columnBar.strip.style.foregroundAlpha(0.35)
            }
        }

        Piece {
            width: frame.cutLeft
            height: frame.height
        }

        Piece {
            x: frame.cutRight
            width: frame.width - frame.cutRight
            height: frame.height
        }

        Piece {
            x: frame.cutLeft
            y: pill.height / 2
            width: pill.width
            height: frame.height - pill.height / 2
        }
    }

    HoverHandler {
        id: stripHover
        cursorShape: Qt.SizeAllCursor
    }

    DragHandler {
        id: stripDrag
        target: null
        // don't let the Flickables steal the drag
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onActiveChanged: columnBar.dragChanged(stripDrag)
        onCentroidChanged: columnBar.dragMoved(stripDrag)
    }

    // made anew whenever the row's columns change; when this column has moved, its windows' thumbnails are still on
    // their way there, see WindowThumb, so the frame and the pill fade in about as long as they take, mostly towards the
    // end; the strip can be grabbed meanwhile
    property real appeared: 1
    NumberAnimation {
        id: fadeIn
        target: columnBar
        property: "appeared"
        from: 0
        to: 1
        duration: Kirigami.Units.longDuration
        easing.type: Easing.InQuad
    }
    Component.onCompleted: {
        if (!alive) {
            return;
        }
        const key = modelData.windows[0].internalId.toString();
        const layout = JSON.stringify([modelData.x, modelData.y, modelData.width, modelData.bottom, modelData.windows.length]);
        const known = strip.columnBarLayouts[key];
        strip.columnBarLayouts[key] = layout;
        if (known !== undefined && known !== layout) {
            fadeIn.start();
        }
    }

    x: alive ? columnBar.strip.toStripX(modelData.x) : 0
    // right above the column
    y: alive ? (modelData.y - columnBar.strip.screenGeometry.y) * columnBar.strip.thumbScale - gap - height : 0
    z: 100000
    width: alive ? modelData.width * columnBar.strip.thumbScale : 0
    height: Kirigami.Units.gridUnit * 1.5
    // gone right away when a window is clicked or the overview closes, see OverviewScreen.closing
    readonly property bool hidden: !alive || strip.overviewRoot.closing
    opacity: hidden ? 0 : (columnBar.strip.overviewRoot.draggedWindow === null || dragged ? 1 : 0) * columnBar.strip.overviewRoot.zoom
    visible: opacity > 0

    // Karousel rearranging recreates them, the drag would never end without the DragHandler that tracks it
    Component.onDestruction: {
        if (stripDrag.active && alive) {
            columnBar.strip.overviewRoot.cancelDrag();
        }
    }

    // a pill with two rows of three dots, the usual sign for something to drag, in the strip above the column, which
    // grabs; not over the top window, which would take a drag that starts there
    Kirigami.ShadowedRectangle {
        id: pill
        opacity: columnBar.appeared
        // narrower on a narrow column, not over the next one, a plain bar where the dots don't fit
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(Kirigami.Units.gridUnit * 3.5, columnBar.width - 2 * Kirigami.Units.smallSpacing))
        height: Kirigami.Units.gridUnit * 1.1
        radius: Math.min(width, height) / 2
        // a little see-through until grabbed
        color: columnBar.lit ? Kirigami.Theme.highlightColor
            : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.7)
        border.width: 1
        border.color: columnBar.lit || !columnBar.alive ? Kirigami.Theme.highlightColor : columnBar.strip.style.foregroundAlpha(0.2)
        // floating over the frame like the windows over their desktop, higher while grabbed
        shadow.size: Kirigami.Units.gridUnit * (columnBar.lit ? 0.8 : 0.5)
        shadow.yOffset: Kirigami.Units.smallSpacing / 2
        shadow.color: !columnBar.alive ? "transparent" : columnBar.lit ? columnBar.strip.style.highlightAlpha(0.5) : Qt.rgba(0, 0, 0, 0.35)

        Behavior on color {
            ColorAnimation { duration: Kirigami.Units.shortDuration }
        }

        Grid {
            anchors.centerIn: parent
            visible: implicitWidth + 2 * Kirigami.Units.largeSpacing <= parent.width
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
