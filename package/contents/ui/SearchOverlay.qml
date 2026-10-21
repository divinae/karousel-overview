pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.milou as Milou
import org.kde.plasma.extras as PlasmaExtras
import QtQuick.Templates as T
import "i18n.js" as I18n

// the search field at the top, which grows into a panel with KRunner's results below it, apps and more, while
// searching; the windows that match go below that, see OverviewScreen.rowsTop
Item {
    id: overlay

    required property string searchText
    // also before typing starts, otherwise it shows with the search
    required property bool fieldAlwaysShown
    // how tall the results may get, the matching windows are below that
    required property real resultsHeight
    // the keys go to the results instead of the windows, see OverviewScreen.handleKey
    required property bool resultsFocused
    // the items behind the panel, in the overlay's coordinates, which it shows blurred through its background
    required property list<Item> blurSources
    // the results' view while there is a search, null otherwise
    property Item resultsView: null
    readonly property real fieldHeight: Kirigami.Units.gridUnit * 2.2
    // below the field, where the results start
    readonly property real fieldBottom: panel.y + fieldHeight

    readonly property bool expanded: searchText !== ""
    // the results' height in the panel, as tall as they are, 0 without any
    readonly property real shownResultsHeight: resultsView === null || (resultsView as ListView).count === 0 ? 0
        : Math.min(resultsHeight, (resultsView as ListView).contentHeight + 2 * Kirigami.Units.largeSpacing)

    function textAlpha(alpha) {
        return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, alpha);
    }

    signal resultActivated()
    signal clearRequested()

    // a pill like a text field, the overview takes the keys itself, so that the arrows and Enter also work on the
    // windows; while searching it grows wider and down into a panel with the results
    Kirigami.ShadowedRectangle {
        id: panel

        readonly property real collapsedWidth: Math.min(overlay.width - 2 * Kirigami.Units.gridUnit,
            Math.max(Kirigami.Units.gridUnit * 18, fieldText.implicitWidth + fieldText.extra))
        readonly property real expandedWidth: Math.min(overlay.width - 2 * Kirigami.Units.gridUnit, Kirigami.Units.gridUnit * 40)

        anchors.horizontalCenter: parent.horizontalCenter
        y: Kirigami.Units.gridUnit
        width: overlay.expanded ? Math.max(collapsedWidth, expandedWidth) : collapsedWidth
        height: overlay.fieldHeight + overlay.shownResultsHeight
        // well rounded, collapsed and expanded alike
        radius: Kirigami.Units.gridUnit
        // see-through, over a blur of what's behind it
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.75)
        border.width: overlay.resultsFocused ? 2 : 1
        border.color: overlay.expanded ? Kirigami.Theme.highlightColor : overlay.textAlpha(0.2)
        shadow.size: Kirigami.Units.gridUnit * (overlay.expanded ? 1.5 : 1)
        shadow.yOffset: Kirigami.Units.smallSpacing / 2
        shadow.color: Qt.rgba(0, 0, 0, overlay.expanded ? 0.35 : 0.3)

        opacity: overlay.fieldAlwaysShown || overlay.expanded ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }
        Behavior on width {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }

        Accessible.role: Accessible.EditableText
        Accessible.name: I18n.tr("Search")
        Accessible.description: overlay.searchText

        // takes the clicks for itself, so that clicking the panel doesn't close the overview
        TapHandler {
            gesturePolicy: TapHandler.WithinBounds
        }

        // what's behind the panel, blurred, under its background; rounded like it
        Item {
            anchors.fill: parent
            z: -1
            layer.enabled: true
            layer.effect: RoundedCorners {
                radius: panel.radius
            }

            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1
                    blurMax: 48
                }

                Repeater {
                    model: overlay.blurSources

                    ShaderEffectSource {
                        required property Item modelData
                        anchors.fill: parent
                        sourceItem: modelData
                        sourceRect: Qt.rect(panel.x, panel.y, panel.width, panel.height)
                    }
                }
            }
        }

        // what's inside stays within the panel while it grows and shrinks
        Item {
            anchors.fill: parent
            clip: true

            Item {
                width: parent.width
                height: overlay.fieldHeight

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Kirigami.Units.iconSizes.small
                        height: width
                        source: "search"
                        color: Kirigami.Theme.textColor
                        isMask: true
                        opacity: 0.6
                    }

                    Text {
                        id: fieldText
                        // what the field needs besides the text: its margins, the icon, the clear button
                        readonly property real extra: 2 * Kirigami.Units.largeSpacing + Kirigami.Units.iconSizes.small
                            + Kirigami.Units.iconSizes.smallMedium + 3 * Kirigami.Units.smallSpacing
                        anchors.verticalCenter: parent.verticalCenter
                        // a long search shows its end, what's being typed, left of the clear button
                        width: Math.min(implicitWidth, panel.width - extra)
                        elide: Text.ElideLeft
                        text: overlay.searchText !== "" ? overlay.searchText : I18n.tr("Type to search")
                        color: Kirigami.Theme.textColor
                        opacity: overlay.searchText !== "" ? 1 : 0.5
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    }

                    // a caret, so that it reads as the place where typing goes; blinking by a timer, an animation would
                    // have KWin redraw the whole overview every frame
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: Kirigami.Units.gridUnit
                        color: Kirigami.Theme.textColor
                        visible: overlay.searchText !== "" && blink.shown

                        Timer {
                            id: blink
                            property bool shown: true
                            interval: 500
                            repeat: true
                            running: overlay.searchText !== ""
                            onTriggered: shown = !shown
                            onRunningChanged: shown = true
                        }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: Kirigami.Units.smallSpacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: Kirigami.Units.iconSizes.smallMedium
                    height: width
                    radius: width / 2
                    color: clearHover.hovered ? Kirigami.Theme.highlightColor : overlay.textAlpha(0.15)
                    visible: overlay.searchText !== ""

                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.trc("@action:button the search", "Clear")

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.small
                        height: width
                        source: "edit-clear"
                        color: clearHover.hovered ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                        isMask: true
                    }

                    HoverHandler {
                        id: clearHover
                    }

                    TapHandler {
                        gesturePolicy: TapHandler.WithinBounds
                        onTapped: overlay.clearRequested()
                    }
                }
            }

            // between the field and the results
            Rectangle {
                x: Kirigami.Units.largeSpacing
                y: overlay.fieldHeight
                width: parent.width - 2 * Kirigami.Units.largeSpacing
                height: 1
                color: overlay.textAlpha(0.15)
                visible: overlay.shownResultsHeight > 0
            }

            Loader {
                active: overlay.searchText !== ""
                y: overlay.fieldHeight
                width: parent.width
                // the whole space, the panel shows as much of it as the results take
                height: overlay.resultsHeight

                sourceComponent: Item {
                    Component.onCompleted: overlay.resultsView = milouView
                    Component.onDestruction: overlay.resultsView = null

                    Milou.ResultsView {
                        id: milouView
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        clip: true
                        // the overview moves through the results, see OverviewScreen.handleResultsKey
                        keyNavigationWraps: false
                        // the selected result only shows while the keys go to the results
                        highlight: overlay.resultsFocused ? resultHighlight : null

                        // only bind queryString after init is done, otherwise the model sets up its own runner manager first
                        property bool initialized: false
                        queryString: initialized ? overlay.searchText : ""
                        Component.onCompleted: initialized = true

                        onActivated: overlay.resultActivated()
                    }

                    Component {
                        id: resultHighlight
                        PlasmaExtras.Highlight {
                            pressed: (milouView.currentItem as T.AbstractButton)?.down ?? false
                        }
                    }
                }
            }
        }
    }
}
