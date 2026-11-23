import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import "layout.js" as Layout
import "i18n.js" as I18n

KWinComponents.SceneEffect {
    id: effect

    property bool activated: false
    property bool gestureInProgress: false
    property real partialActivationFactor: 0
    readonly property int animationDuration: Kirigami.Units.longDuration
    // ids of the desktops created in the overview, only these are removed when empty, the user's own desktops stay
    property var temporaryDesktops: []
    // where each window was while its desktop was the current one, which is where Karousel lays it out; once its
    // desktop isn't current any more, KWin pulls the windows that are far off screen back onto it, on top of each other;
    // by layoutKey, changed in place, nothing binds to it
    property var layouts: ({})

    // where Karousel last tiled each window, the last three geometries while it wasn't fullscreen or maximized, by
    // layoutKey, changed in place, see tiledGeometry
    property var tiledLayouts: ({})

    // over the whole screen, which Karousel leaves alone, while its column keeps its place among the others; not
    // maximized in one direction only
    function fillsScreen(window) {
        return window.fullScreen || window.maximizeMode === 3;
    }

    // where a fullscreen or maximized window was last tiled on the desktop it's on, null when not known
    function tiledGeometry(window) {
        if (window.desktops.length !== 1) {
            return null;
        }
        const layouts = (tiledLayouts[layoutKey(window)] ?? []).filter(layout => layout.desktop === window.desktops[0].id);
        return layouts.length > 0 ? onOutput(layouts[layouts.length - 1], window) : null;
    }

    // a remembered layout's geometry on the screen the window is on now: when a monitor is plugged in or out, KWin
    // moves the windows to another screen, or the screens move, also those on desktops that aren't current, which
    // keep their remembered layout until their desktop is current again; moved by as much as the screen's corner is
    function onOutput(layout, window) {
        const now = window.output.geometry;
        const geometry = layout.geometry;
        return Qt.rect(geometry.x - layout.origin.x + now.x, geometry.y - layout.origin.y + now.y, geometry.width, geometry.height);
    }

    // Karousel has a layout for each desktop in each activity, a window in several activities has one in each
    function layoutKey(window) {
        return window.internalId.toString() + "/" + KWinComponents.Workspace.currentActivity;
    }
    // Karousel's gaps in pixels, measured by the overview from its layout and kept for the next time it opens, see
    // DesktopRow's refreshBounds; -1 for the vertical one until there's a column with more than one window to measure
    property real horizontalGap: 0
    property real verticalGap: -1

    function rememberGeometry(window) {
        const desktop = window.desktops.length === 1 ? window.desktops[0] : null;
        if (desktop !== null && desktop === KWinComponents.Workspace.currentDesktopForScreen(window.output)) {
            const geometry = window.frameGeometry;
            const layout = {
                geometry: Qt.rect(geometry.x, geometry.y, geometry.width, geometry.height),
                desktop: desktop.id,
                // the corner of the screen it was on, see onOutput
                origin: Qt.point(window.output.geometry.x, window.output.geometry.y),
            };
            layouts[layoutKey(window)] = layout;
            // the last few, see tiledGeometry; told by the geometry, not by whether it's fullscreen or maximized: KWin
            // changes the geometry before it says so, and when it's no longer maximized, after Karousel has tiled it
            const area = KWinComponents.Workspace.clientArea(KWinComponents.Workspace.MaximizeArea, window.output, desktop);
            // not again when nothing changed, see rememberCurrentDesktops, it would push out the ones before
            const tiled = tiledLayouts[layoutKey(window)] ?? [];
            const last = tiled[tiled.length - 1];
            const same = last !== undefined && last.desktop === layout.desktop
                && [last.geometry.x, last.geometry.y, last.geometry.width, last.geometry.height, last.origin.x, last.origin.y].join()
                    === [geometry.x, geometry.y, geometry.width, geometry.height, layout.origin.x, layout.origin.y].join();
            if (!Layout.coversArea(geometry, area) && !same) {
                tiledLayouts[layoutKey(window)] = tiled.slice(-2).concat([layout]);
            }
        }
    }

    // null when not known for the desktop the window is on now, e.g. after it was moved to another one
    function rememberedGeometry(window) {
        const layout = layouts[layoutKey(window)];
        return layout !== undefined && window.desktops.length === 1 && layout.desktop === window.desktops[0].id ? onOutput(layout, window) : null;
    }

    // the effect's id from a delegate, like below
    // qmllint disable unqualified
    Instantiator {
        model: KWinComponents.WindowModel {}
        delegate: Connections {
            id: tracker
            required property var window
            // the window may be gone when its tracker is destroyed
            readonly property string windowId: window.internalId.toString()
            target: tracker.window
            function onFrameGeometryChanged() {
                effect.rememberGeometry(tracker.window);
            }
            // on another screen without being moved, e.g. its screen was plugged in or out while its desktop was current
            function onOutputChanged() {
                effect.rememberGeometry(tracker.window);
            }
            Component.onCompleted: effect.rememberGeometry(tracker.window)
            Component.onDestruction: {
                for (const store of [effect.layouts, effect.tiledLayouts]) {
                    for (const key of Object.keys(store).filter(key => key.startsWith(tracker.windowId + "/"))) {
                        delete store[key];
                    }
                }
            }
        }
    }
    // qmllint enable unqualified

    // a desktop's windows where they are once it's current again, also those that don't move then: after a monitor was
    // plugged in or out, KWin moved them while their desktop wasn't current, and where Karousel has them now may be
    // where KWin put them, so the layout remembered before, for the other screen, would stay
    Connections {
        target: KWinComponents.Workspace
        function onCurrentDesktopChanged() {
            Qt.callLater(effect.rememberCurrentDesktops);
        }
    }

    function rememberCurrentDesktops() {
        for (const window of KWinComponents.Workspace.windows) {
            rememberGeometry(window);
        }
    }

    // KWin creates the delegate outside this file's context, so the components here can't be bound to it
    // (pragma ComponentBehavior: Bound), and the linter can't tell that the effect's id is reachable from them
    // qmllint disable unqualified
    delegate: OverviewScreen {
        sceneEffect: effect
    }

    Instantiator {
        model: effect.configuration.BorderActivate
        KWinComponents.ScreenEdgeHandler {
            required property int modelData
            mode: KWinComponents.ScreenEdgeHandler.Pointer
            edge: modelData
            onActivated: effect.toggle()
        }
    }

    Instantiator {
        model: effect.configuration.TouchBorderActivate
        KWinComponents.ScreenEdgeHandler {
            required property int modelData
            mode: KWinComponents.ScreenEdgeHandler.Touch
            edge: modelData
            onActivated: effect.toggle()
        }
    }

    KWinComponents.ShortcutHandler {
        name: "Karousel Overview"
        text: I18n.tr("Karousel: Toggle overview")
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
                onCancelled: effect.finishGesture(effect.partialActivationFactor >= 0.5)
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
                onCancelled: effect.finishGesture(effect.partialActivationFactor >= 0.5)
            }
        }
    }

    // qmllint enable unqualified

    // the screens' overviews that are there now, see OverviewScreen; KWin doesn't start the effect while another
    // fullscreen effect runs, e.g. the slide of a desktop switch with three fingers, and doesn't say so: the effect is
    // shown with nothing on screen, so it asks again until the overview is there, showing it again when it runs does
    // nothing; reset after a while, so that it doesn't stay open with nothing on screen and ignore the gesture
    property int liveScreens: 0

    Timer {
        id: startTimer
        property int attempts: 0
        interval: 100
        repeat: true
        onTriggered: {
            if (!effect.visible || effect.liveScreens > 0) {
                stop();
            } else if (++attempts > 30) {
                stop();
                console.warn("Karousel Overview: KWin didn't show the overview, it's reset");
                deactivateTimer.stop();
                effect.gestureInProgress = false;
                effect.activated = false;
                effect.partialActivationFactor = 0;
                effect.visible = false;
            } else {
                effect.show();
            }
        }
    }

    // see liveScreens
    function show() {
        if (liveScreens === 0) {
            visible = false;
        }
        visible = true;
        if (liveScreens === 0 && !startTimer.running) {
            startTimer.attempts = 0;
            startTimer.start();
        }
    }

    Timer {
        id: deactivateTimer
        interval: effect.animationDuration
        onTriggered: effect.visible = false
    }

    // called by each screen's overview as it's destroyed after closing, see liveScreens; removing desktops while its
    // rows are torn down crashes KWin, so only after that
    function overviewDestroyed() {
        liveScreens = Math.max(0, liveScreens - 1);
        if (!visible && configuration.RemoveEmptyDesktops) {
            Qt.callLater(removeEmptyDesktops);
        }
    }

    // like GNOME's dynamic workspaces, but only for the desktops created in the overview,
    // keeps the desktops shown on the screens
    function removeEmptyDesktops() {
        if (visible) {
            return;
        }
        const workspace = KWinComponents.Workspace;
        const kept = workspace.screens.map(screen => workspace.currentDesktopForScreen(screen))
            .concat(workspace.desktops.filter(desktop => !temporaryDesktops.includes(desktop.id)));
        // windows on all desktops have no desktops of their own
        const empty = Layout.emptyDesktops(workspace.desktops, Array.from(workspace.windows, window => Array.from(window.desktops)), kept);
        for (const desktop of empty) {
            workspace.removeDesktop(desktop);
        }
        const ids = workspace.desktops.map(desktop => desktop.id);
        temporaryDesktops = temporaryDesktops.filter(id => ids.includes(id));
    }

    // whether KWin's color blindness correction is on, see OverviewScreen's layer; asked again each time the overview
    // opens, it can be turned on and off meanwhile
    property bool colorCorrectionLoaded: false
    property KWinComponents.DBusCall colorCorrectionCheck: KWinComponents.DBusCall {
        service: "org.kde.KWin"
        path: "/Effects"
        dbusInterface: "org.kde.kwin.Effects"
        method: "isEffectLoaded"
        arguments: ["colorblindnesscorrection"]
        onFinished: returnValue => effect.colorCorrectionLoaded = returnValue[0] === true
    }
    Component.onCompleted: colorCorrectionCheck.call()

    function toggle() {
        if (activated) {
            deactivate();
        } else {
            activate();
        }
    }

    // also reopens while closing, the zoom then turns around from where it is
    function activate() {
        if (activated) {
            return;
        }
        deactivateTimer.stop();
        colorCorrectionCheck.call();
        show();
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
        if (!visible) {
            colorCorrectionCheck.call();
        }
        deactivateTimer.stop();
        show();
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
