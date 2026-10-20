import QtQuick
import "layout.js" as Layout

// vertical scrolling jumps one desktop at a time, horizontal scrolling pans the row under the pointer
Item {
    id: navigation

    required property Item overviewRoot

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
                const position = navigation.mapToItem(navigation.overviewRoot, point.position.x, point.position.y);
                const row = navigation.overviewRoot.rowAt(position) ?? navigation.overviewRoot.currentRow;
                row?.panBy(deltaX);
            }

            const wheel = Layout.wheelStep(accumulatedY, deltaY);
            accumulatedY = wheel.accumulated;
            if (wheel.step !== 0) {
                navigation.overviewRoot.selectRow(wheel.step);
            }
            event.accepted = true;
        }
    }
}
