pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

// small desktops along the right edge, or the top, like GNOME's workspace strip and Mission Control's spaces bar:
// hidden until the pointer reaches that edge, click a desktop to go to it; always shown while a window is dragged,
// to drop it on a desktop far away without scrolling to it; the last card is for a new desktop
Item {
    id: minimap

    required property OverviewScreen overviewRoot
    required property DragController drag
    // the row selected in the overview
    property int selectedIndex: -1

    // hidden until the dragged window comes close to where it would be
    // the pointer is at the edge it slides out from, see OverviewScreen
    property bool revealed: false
    readonly property bool wanted: overviewRoot.config.MinimapAlwaysShown || drag.window !== null || revealed || panelHover.hovered
    // stays a moment after the pointer leaves it, so that it doesn't hide while moving back to it
    property bool shown: false
    onWantedChanged: {
        if (wanted) {
            hideTimer.stop();
            shown = true;
        } else {
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: 600
        onTriggered: minimap.shown = false
    }

    HoverHandler {
        id: panelHover
    }
    // a row along the top instead of a column along the right edge
    readonly property bool horizontal: overviewRoot.config.DropMinimapAtTop
    readonly property rect screenGeometry: overviewRoot.screenGeometry
    // room for the frames around the cards
    readonly property real margin: Kirigami.Units.largeSpacing * 2
    readonly property real cardSpacing: Kirigami.Units.largeSpacing * 1.5
    // between a card and its frame, so that the frame doesn't run into the windows on it
    readonly property real frameGap: 3
    readonly property real frameWidth: 3
    // the white inner edge of the frames, only in a light theme, in a dark one it's too bright
    readonly property bool darkTheme: Kirigami.Theme.backgroundColor.hslLightness < 0.5
    readonly property color contrastColor: "white"
    // one more for a new desktop
    readonly property int count: KWinComponents.Workspace.desktops.length + 1
    readonly property real aspect: screenGeometry.width / Math.max(1, screenGeometry.height)
    // smaller with many desktops, so that all of them fit on the screen
    readonly property real cardHeight: horizontal
        ? Math.min(Kirigami.Units.gridUnit * 6, (overviewRoot.width - 4 * margin - (count - 1) * cardSpacing) / count / aspect)
        : Math.min(Kirigami.Units.gridUnit * 7, (overviewRoot.height - 4 * margin - (count - 1) * cardSpacing) / count)
    readonly property real cardWidth: cardHeight * aspect
    readonly property real cardRadius: Kirigami.Units.smallSpacing * 1.5
    // where the dragged window would go
    readonly property int dropIndex: drag.overMinimap && drag.dropAction !== "" ? drag.minimapIndex : -1
    // all windows, which each card filters for its desktop
    readonly property QtObject windowModel: KWinComponents.WindowModel {}

    // slides in from the edge while dragging
    x: horizontal ? (overviewRoot.width - width) / 2 : overviewRoot.width - width - margin + (1 - appearance) * (width + margin)
    y: horizontal ? margin - (1 - appearance) * (height + margin) : (overviewRoot.height - height) / 2
    width: cards.implicitWidth + 2 * margin
    height: cards.implicitHeight + 2 * margin
    visible: appearance > 0
    opacity: appearance

    property real appearance: shown ? 1 : 0
    Behavior on appearance {
        NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
    }

    // in the overview's coordinates, only while it's shown
    function containsPoint(point) {
        if (!shown) {
            return false;
        }
        const local = minimap.mapFromItem(overviewRoot, point.x, point.y);
        return local.x >= 0 && local.y >= 0 && local.x < width && local.y < height;
    }

    // the card at a point in the overview's coordinates, -1 when there's none
    function indexAt(point) {
        if (!containsPoint(point)) {
            return -1;
        }
        // the spacing between the cards counts as the closest card's, so that there's no gap to miss them in
        const local = cards.mapFromItem(overviewRoot, point.x, point.y);
        for (let i = 0; i < cardRepeater.count; i++) {
            const card = cardRepeater.itemAt(i);
            if (card !== null && (horizontal ? local.x < card.x + card.width + cardSpacing / 2 : local.y < card.y + card.height + cardSpacing / 2)) {
                return i;
            }
        }
        return cardRepeater.count - 1;
    }

    Rectangle {
        anchors.fill: parent
        radius: minimap.cardRadius + minimap.margin
        color: Qt.rgba(0, 0, 0, 0.35)
    }

    Grid {
        id: cards
        x: minimap.margin
        y: minimap.margin
        rows: minimap.horizontal ? 1 : minimap.count
        columns: minimap.horizontal ? minimap.count : 1
        spacing: minimap.cardSpacing

        Repeater {
            id: cardRepeater
            model: minimap.count

            delegate: Item {
                id: card

                required property int index
                readonly property var desktop: index < KWinComponents.Workspace.desktops.length ? KWinComponents.Workspace.desktops[index] : null
                readonly property real windowScale: width / Math.max(1, minimap.screenGeometry.width)
                readonly property bool target: index === minimap.dropIndex || (minimap.drag.window === null && cardHover.hovered)
                readonly property bool selected: index === minimap.selectedIndex

                width: minimap.cardWidth
                height: minimap.cardHeight
                z: target ? 1 : 0
                // while one card is the target, the others step back, so that it stands out
                opacity: minimap.dropIndex !== -1 && !target ? 0.55 : 1

                Behavior on opacity {
                    NumberAnimation { duration: Kirigami.Units.shortDuration }
                }

                HoverHandler {
                    id: cardHover
                }

                // goes to the desktop, the last card creates one
                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: minimap.overviewRoot.goToRow(card.index)
                }

                // the desktop's wallpaper with its windows' outlines, the part that is on screen
                Item {
                    anchors.fill: parent
                    visible: card.desktop !== null
                    clip: true
                    layer.enabled: true
                    layer.effect: RoundedCorners {
                        radius: minimap.cardRadius
                    }

                    // behind the wallpaper, only seen while it loads
                    Rectangle {
                        anchors.fill: parent
                        color: Kirigami.Theme.backgroundColor
                    }

                    KWinComponents.DesktopBackground {
                        width: minimap.screenGeometry.width
                        height: minimap.screenGeometry.height
                        scale: card.windowScale
                        transformOrigin: Item.TopLeft
                        activity: KWinComponents.Workspace.currentActivity
                        desktop: card.desktop
                        outputName: minimap.overviewRoot.targetScreen.name
                    }

                    Repeater {
                        model: KWinComponents.WindowFilterModel {
                            activity: KWinComponents.Workspace.currentActivity
                            desktop: card.desktop
                            minimizedWindows: false
                            windowType: KWinComponents.WindowFilterModel.Normal | KWinComponents.WindowFilterModel.Dialog
                            windowModel: minimap.windowModel
                        }

                        // each window as a card in the theme's colours with its app's icon, easier to recognise than a tiny thumbnail
                        delegate: Rectangle {
                            id: miniWindow

                            required property var window

                            // where Karousel lays it out, also on desktops that aren't current
                            readonly property rect geometry: minimap.overviewRoot.geometryOf(window)

                            x: (geometry.x - minimap.screenGeometry.x) * card.windowScale
                            y: (geometry.y - minimap.screenGeometry.y) * card.windowScale
                            width: geometry.width * card.windowScale
                            height: geometry.height * card.windowScale
                            visible: !minimap.overviewRoot.multipleScreens || window.output === minimap.overviewRoot.targetScreen
                            radius: 3
                            // in the theme's colours, like the windows themselves
                            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.9)
                            border.width: 1
                            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)

                            // dimmed while it's dragged, like in the rows
                            opacity: minimap.drag.window === window ? 0.3 : 1

                            // the same size for every window, smaller only when a window is too narrow for it
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: Math.min(minimap.cardHeight * 0.35, Math.min(parent.width, parent.height) * 0.8)
                                height: width
                                source: miniWindow.window.icon
                            }

                            // dragged from here like from the rows, e.g. from a desktop far away to the one shown
                            DragHandler {
                                target: null
                                grabPermissions: PointerHandler.CanTakeOverFromAnything
                                onActiveChanged: {
                                    if (active) {
                                        minimap.overviewRoot.startDrag(miniWindow.window, miniWindow, centroid.scenePressPosition);
                                    } else {
                                        minimap.overviewRoot.endDrag();
                                    }
                                }
                                onCentroidChanged: {
                                    if (active) {
                                        minimap.overviewRoot.moveDrag(centroid.scenePosition);
                                    }
                                }
                            }
                        }
                    }
                }

                // the card for a new desktop
                Rectangle {
                    anchors.fill: parent
                    visible: card.desktop === null
                    radius: minimap.cardRadius
                    color: Qt.rgba(1, 1, 1, 0.12)

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.smallMedium
                        height: width
                        source: "list-add"
                        color: "white"
                        isMask: true
                    }
                }

                // where the dragged window would go, or the hovered card: a thick frame in the highlight colour with a white
                // inner edge and a glow, which stands out on any wallpaper, fades in
                Kirigami.ShadowedRectangle {
                    anchors.fill: parent
                    anchors.margins: -(minimap.frameGap + minimap.frameWidth + 1)
                    radius: minimap.cardRadius + minimap.frameGap + minimap.frameWidth + 1
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.35)
                    border.width: minimap.frameWidth + 1
                    border.color: Kirigami.Theme.highlightColor
                    shadow.size: Kirigami.Units.gridUnit
                    shadow.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.8)
                    opacity: card.target ? 1 : 0
                    visible: opacity > 0

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: minimap.frameWidth + 1
                        radius: minimap.cardRadius + minimap.frameGap
                        color: "transparent"
                        border.width: 1
                        border.color: minimap.contrastColor
                        visible: !minimap.darkTheme
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: Kirigami.Units.shortDuration }
                    }
                }

                // the desktop selected in the overview: a frame with a white inner edge; where a window would go has a fill and
                // a glow besides, so they don't mix up
                // a light tint over it, which shows also on a desktop full of white windows
                Rectangle {
                    anchors.fill: parent
                    radius: minimap.cardRadius
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.2)
                    visible: card.selected && !card.target
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -(minimap.frameGap + minimap.frameWidth)
                    radius: minimap.cardRadius + minimap.frameGap + minimap.frameWidth
                    color: "transparent"
                    border.width: minimap.frameWidth
                    border.color: Kirigami.Theme.highlightColor
                    visible: card.selected && !card.target

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: minimap.frameWidth
                        radius: minimap.cardRadius + minimap.frameGap
                        color: "transparent"
                        border.width: 1
                        border.color: minimap.contrastColor
                        visible: !minimap.darkTheme
                    }
                }


                // the desktop's number, and its name too while the dragged window is over it
                Rectangle {
                    x: Kirigami.Units.smallSpacing
                    y: Kirigami.Units.smallSpacing
                    width: Math.max(height, label.implicitWidth + Kirigami.Units.smallSpacing * (card.target ? 3 : 1))
                    height: label.implicitHeight
                    radius: height / 2
                    color: card.target || card.selected ? Kirigami.Theme.highlightColor : Qt.rgba(0, 0, 0, 0.6)
                    visible: card.desktop !== null

                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: card.target && card.desktop !== null ? (card.index + 1) + "  " + card.desktop.name : card.index + 1
                        color: "white"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.bold: card.target
                    }
                }
            }
        }
    }
}
