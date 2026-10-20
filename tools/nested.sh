#!/bin/bash
# Runs a headless KWin with its own D-Bus session, config and cache, with the
# overview effect and Karousel enabled. Restarting the real KWin to load a new
# version of the effect also restarts Xwayland, which kills X11 apps.
#
# Usage: tools/nested.sh <state dir> [applications...]
# The nested session's D-Bus address is written to <state dir>/bus, use it with
# tools/nested-run.sh.
set -e

state="$(realpath -m "$1")"
shift
mkdir -p "$state/config" "$state/cache"
cat > "$state/config/kwinrc" <<CONFIG
[Plugins]
karouselEnabled=true
karousel_overviewEnabled=true
CONFIG

apps=("$@")
if [ ${#apps[@]} -eq 0 ]; then
    apps=(konsole konsole kwrite)
fi

# runs inside the nested session, before the applications
cat > "$state/session.sh" <<SESSION
#!/bin/bash
# D-Bus activated services, like kactivitymanagerd which Karousel needs for tiling, need the Wayland display
dbus-update-activation-environment WAYLAND_DISPLAY XDG_CONFIG_HOME XDG_CACHE_HOME
qdbus6 org.kde.ActivityManager /ActivityManager/Activities org.kde.ActivityManager.Activities.CurrentActivity > /dev/null
echo "\$DBUS_SESSION_BUS_ADDRESS" > "$state/bus"
sleep 1
for app in ${apps[*]}; do
    \$app &
    sleep 0.5
done
wait
SESSION
chmod +x "$state/session.sh"

export XDG_CONFIG_HOME="$state/config"
export XDG_CACHE_HOME="$state/cache"
unset WAYLAND_DISPLAY DISPLAY

exec dbus-run-session -- kwin_wayland --virtual --width 1920 --height 1080 --no-lockscreen \
    --socket wayland-karousel-overview "$state/session.sh"
