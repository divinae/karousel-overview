import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

KWinComponents.SceneEffect {
    id: effect

    property bool activated: false
    property bool gestureInProgress: false
    property real partialActivationFactor: 0
    readonly property int animationDuration: Kirigami.Units.longDuration

    delegate: OverviewScreen {}

    Instantiator {
        model: effect.configuration.BorderActivate
        KWinComponents.ScreenEdgeHandler {
            mode: KWinComponents.ScreenEdgeHandler.Pointer
            edge: modelData
            onActivated: effect.toggle()
        }
    }

    Instantiator {
        model: effect.configuration.TouchBorderActivate
        KWinComponents.ScreenEdgeHandler {
            mode: KWinComponents.ScreenEdgeHandler.Touch
            edge: modelData
            onActivated: effect.toggle()
        }
    }

    KWinComponents.ShortcutHandler {
        name: "Karousel Overview"
        text: "Karousel: Toggle overview"
        sequence: "Meta+Ctrl+O"
        onActivated: effect.toggle()
    }

    // touchpad swipe up opens the overview, swipe down closes it, following the fingers
    Instantiator {
        model: effect.configuration.TouchpadGesture ? 1 : 0

        QtObject {
            readonly property QtObject openGesture: KWinComponents.SwipeGestureHandler {
                direction: KWinComponents.SwipeGestureHandler.Direction.Up
                fingerCount: effect.configuration.GestureFingerCount
                onProgressChanged: {
                    if (!effect.activated) {
                        effect.partialActivate(progress);
                    }
                }
                onActivated: effect.finishGesture(true)
                onCancelled: effect.finishGesture(effect.activated)
            }

            readonly property QtObject closeGesture: KWinComponents.SwipeGestureHandler {
                direction: KWinComponents.SwipeGestureHandler.Direction.Down
                fingerCount: effect.configuration.GestureFingerCount
                onProgressChanged: {
                    if (effect.activated) {
                        effect.partialActivate(1 - progress);
                    }
                }
                onActivated: effect.finishGesture(false)
                onCancelled: effect.finishGesture(effect.activated)
            }
        }
    }

    Timer {
        id: deactivateTimer
        interval: effect.animationDuration
        onTriggered: effect.visible = false
    }

    function toggle() {
        if (activated) {
            deactivate();
        } else {
            activate();
        }
    }

    function activate() {
        if (activated || deactivateTimer.running) {
            return;
        }
        visible = true;
        activated = true;
    }

    function deactivate() {
        if (!activated) {
            return;
        }
        activated = false;
        deactivateTimer.start();
    }

    function partialActivate(factor) {
        if (deactivateTimer.running) {
            return;
        }
        visible = true;
        gestureInProgress = true;
        partialActivationFactor = factor;
    }

    function finishGesture(open) {
        if (!gestureInProgress) {
            return;
        }
        gestureInProgress = false;
        activated = true;
        if (!open) {
            deactivate();
        }
    }
}
