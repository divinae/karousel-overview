pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.milou as Milou
import org.kde.plasma.extras as PlasmaExtras

// the search text, and KRunner results when no window matches it
Item {
    id: overlay

    required property string searchText
    // true when no window matches the search
    required property bool showResults
    // receives the keys while results are shown
    // set by the results while they're loaded
    property Item resultsView: null

    signal resultActivated()

    Loader {
        id: results
        active: overlay.searchText !== "" && overlay.showResults
        anchors.fill: parent
        anchors.topMargin: Kirigami.Units.gridUnit * 4

        sourceComponent: Rectangle {
            Component.onCompleted: overlay.resultsView = milouView
            Component.onDestruction: overlay.resultsView = null

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
                queryString: initialized ? overlay.searchText : ""
                Component.onCompleted: initialized = true

                onActivated: overlay.resultActivated()
            }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Kirigami.Units.gridUnit
        width: searchLabel.implicitWidth + 2 * Kirigami.Units.largeSpacing
        height: searchLabel.implicitHeight + Kirigami.Units.largeSpacing
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.7)
        visible: overlay.searchText !== ""

        Text {
            id: searchLabel
            anchors.centerIn: parent
            text: overlay.searchText
            color: "white"
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.5
        }
    }
}
