pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import "i18n.js" as I18n

// a pill on the wallpaper's top-left corner with the desktop's number and name, double-click to rename,
// and a button to remove the desktop when it's empty; on the wallpaper, so in the wallpaper's colours
Rectangle {
    id: pill

    required property DesktopRow strip
    property bool editingName: false

    function startRenaming() {
        editingName = true;
        nameInput.text = pill.strip.desktop.name;
        nameInput.forceActiveFocus();
        nameInput.selectAll();
    }

    function finishRenaming(apply) {
        if (!editingName) {
            return;
        }
        editingName = false;
        const name = nameInput.text.trim();
        if (apply && name !== "") {
            pill.strip.desktop.name = name;
        }
        pill.strip.overviewRoot.forceActiveFocus();
    }

    // the default name, a word and the number in any language, only repeats the number
    readonly property bool showName: pill.strip.desktop === null || pill.editingName || !new RegExp("^\\S+\\s" + pill.strip.number + "$").test(pill.strip.desktop.name)

    // across the wallpaper's top edge, so that it covers little of the windows
    x: pill.strip.cardLeft + Kirigami.Units.smallSpacing
    y: -height / 2
    width: header.implicitWidth + 2 * (showName ? Kirigami.Units.largeSpacing : Kirigami.Units.smallSpacing)
    height: header.implicitHeight + 2 * Kirigami.Units.smallSpacing
    radius: height / 2
    color: Qt.rgba(0, 0, 0, pill.strip.selected ? 0.75 : 0.55)
    border.width: pill.strip.selected ? 1 : 0
    border.color: Kirigami.Theme.highlightColor
    opacity: pill.strip.overviewRoot.zoom

    HoverHandler {
        id: headerHover
    }

    // takes the clicks for itself, so that clicking the pill doesn't switch desktops or close the overview
    TapHandler {
        gesturePolicy: TapHandler.WithinBounds
        onDoubleTapped: {
            if (pill.strip.desktop !== null) {
                pill.startRenaming();
            }
        }
    }

    Row {
        id: header
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(Kirigami.Units.iconSizes.small, numberLabel.implicitWidth + Kirigami.Units.smallSpacing)
            height: Kirigami.Units.iconSizes.small
            radius: height / 2
            color: pill.strip.selected ? Kirigami.Theme.highlightColor : Qt.rgba(1, 1, 1, 0.25)

            Text {
                id: numberLabel
                anchors.centerIn: parent
                text: pill.strip.desktop !== null ? pill.strip.number : "+"
                color: "white"
                font.bold: true
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        Text {
            id: nameLabel
            anchors.verticalCenter: parent.verticalCenter
            visible: !pill.editingName && pill.showName
            text: pill.strip.desktop !== null ? pill.strip.desktop.name : I18n.tr("New desktop")
            font: Kirigami.Theme.defaultFont
            color: "white"
            opacity: pill.strip.selected ? 1 : 0.8
        }

        TextInput {
            id: nameInput
            anchors.verticalCenter: parent.verticalCenter
            visible: pill.editingName
            font: nameLabel.font
            color: "white"
            selectByMouse: true
            selectionColor: Kirigami.Theme.highlightColor
            onAccepted: pill.finishRenaming(true)
            onActiveFocusChanged: {
                if (!activeFocus) {
                    pill.finishRenaming(true);
                }
            }
            Keys.onEscapePressed: pill.finishRenaming(false)
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Kirigami.Units.iconSizes.small
            height: width
            radius: width / 2
            color: removeHover.hovered ? "#da4453" : Qt.rgba(1, 1, 1, 0.2)
            // the window count is filtered by the search, so don't offer removing while searching
            // windowCount only to be checked again as windows come and go
            visible: headerHover.hovered && !pill.editingName && pill.strip.desktop !== null && pill.strip.windowCount >= 0 && pill.strip.isEmpty()
                     && pill.strip.overviewRoot.searchText === "" && KWinComponents.Workspace.desktops.length > 1

            Text {
                anchors.centerIn: parent
                text: "✕"
                color: "white"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }

            HoverHandler {
                id: removeHover
            }

            TapHandler {
                gesturePolicy: TapHandler.WithinBounds
                onTapped: KWinComponents.Workspace.removeDesktop(pill.strip.desktop)
            }
        }
    }
}
