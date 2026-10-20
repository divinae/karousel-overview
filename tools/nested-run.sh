#!/bin/bash
# Runs a command inside the nested session started by tools/nested.sh.
# Usage: tools/nested-run.sh <state dir> <command...>
set -e

state="$1"
shift
export DBUS_SESSION_BUS_ADDRESS="$(cat "$state/bus")"
export WAYLAND_DISPLAY=wayland-karousel-overview
export XDG_CONFIG_HOME="$state/config"
export XDG_CACHE_HOME="$state/cache"
export XDG_STATE_HOME="$state/state"
export XDG_DATA_HOME="$state/data"
unset DISPLAY
exec "$@"
