pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

// where a dragged window would go in a row's strip, see DesktopRow's stackHint and insertHintX
Item {
    id: hints

    required property DesktopRow strip

    z: 100000

    // the column a dragged window would join
    Rectangle {
        x: hints.strip.stackHint !== null ? hints.strip.stackHint.x : 0
        y: hints.strip.stackHint !== null ? hints.strip.stackHint.y : 0
        width: hints.strip.stackHint !== null ? hints.strip.stackHint.width : 0
        height: hints.strip.stackHint !== null ? hints.strip.stackHint.height : 0
        z: 100000
        radius: Kirigami.Units.cornerRadius
        color: hints.strip.style.highlightAlpha(0.3)
        border.width: 3
        border.color: Kirigami.Theme.highlightColor
        visible: hints.strip.stackHint !== null
    }

    // where in that column, a glowing pill like the one between columns
    Kirigami.ShadowedRectangle {
        x: hints.strip.stackHint !== null ? hints.strip.stackHint.x + hints.strip.stackHint.width * 0.1 : 0
        y: hints.strip.stackHint !== null && !isNaN(hints.strip.stackHint.lineY) ? hints.strip.stackHint.lineY - height / 2 : 0
        z: 100000
        width: hints.strip.stackHint !== null ? hints.strip.stackHint.width * 0.8 : 0
        height: Kirigami.Units.smallSpacing * 2.5
        radius: height / 2
        color: Kirigami.Theme.highlightColor
        shadow.size: Kirigami.Units.gridUnit * 1.5
        shadow.color: hints.strip.style.highlightAlpha(0.9)
        visible: hints.strip.stackHint !== null && !isNaN(hints.strip.stackHint.lineY)
    }

    // where a dragged column goes: a glowing pill that slides between the columns and fades in and out
    Kirigami.ShadowedRectangle {
        id: insertHint

        readonly property bool shown: !isNaN(hints.strip.insertHintX)
        // stays where it was while fading out
        property real hintX: 0

        x: hintX - width / 2
        y: hints.strip.height * 0.1
        z: 100000
        width: Kirigami.Units.smallSpacing * 2.5
        height: hints.strip.height * 0.8
        radius: width / 2
        color: Kirigami.Theme.highlightColor
        shadow.size: Kirigami.Units.gridUnit * 1.5
        shadow.color: hints.strip.style.highlightAlpha(0.9)
        opacity: shown ? 1 : 0
        visible: opacity > 0

        Connections {
            target: hints.strip
            function onInsertHintXChanged() {
                if (!isNaN(hints.strip.insertHintX)) {
                    insertHint.hintX = hints.strip.insertHintX;
                }
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }
        Behavior on hintX {
            enabled: insertHint.shown
            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
        }
    }
}
