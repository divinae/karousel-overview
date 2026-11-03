pragma ComponentBehavior: Bound

import QtQuick
import "layout.js" as Layout

// vertical scrolling jumps one desktop at a time, horizontal scrolling pans the row under the pointer
Item {
    id: navigation

    required property OverviewScreen overviewRoot

    WheelHandler {
        property real accumulatedY: 0
        // the touchpad's swipe so far, see Layout.touchpadScroll
        property var swipe: null

        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            let deltaX = event.angleDelta.x;
            let deltaY = event.angleDelta.y;
            if (event.modifiers & Qt.ShiftModifier) {
                deltaX = deltaY;
                deltaY = 0;
            }

            let step = 0;
            // a touchpad sends a stream of small events for each swipe, a mouse wheel one per notch
            if (point.device.type === PointerDevice.TouchPad) {
                const scroll = Layout.touchpadScroll(swipe, deltaX, deltaY, Date.now());
                swipe = scroll.state;
                deltaX = scroll.pan;
                step = scroll.step;
            } else {
                const wheel = Layout.wheelStep(accumulatedY, deltaY);
                accumulatedY = wheel.accumulated;
                step = wheel.step;
            }

            if (deltaX !== 0) {
                const position = navigation.mapToItem(navigation.overviewRoot, point.position.x, point.position.y);
                const row = navigation.overviewRoot.rowAt(position) ?? navigation.overviewRoot.currentRow;
                row?.panBy(deltaX);
            }
            if (step !== 0) {
                navigation.overviewRoot.selectRow(step);
            }
            event.accepted = true;
        }
    }
}
