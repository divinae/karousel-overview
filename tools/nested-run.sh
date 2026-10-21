#!/bin/bash
# Runs a command inside the nested session started by tools/nested.sh.
# Usage: tools/nested-run.sh <state dir> <command...>
set -e

state="$1"
shift
# without the nested session's bus, D-Bus would fall back to the real session's and the command would act on it
bus="$(cat "$state/bus" 2>/dev/null || true)"
if [ -z "$bus" ]; then
    echo "No nested session in $state, is tools/nested.sh running?" >&2
    exit 1
fi
export DBUS_SESSION_BUS_ADDRESS="$bus"
export WAYLAND_DISPLAY=wayland-karousel-overview
export XDG_CONFIG_HOME="$state/config"
export XDG_CACHE_HOME="$state/cache"
export XDG_STATE_HOME="$state/state"
export XDG_DATA_HOME="$state/data"
unset DISPLAY
exec "$@"
