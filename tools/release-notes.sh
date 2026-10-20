#!/bin/bash
# Prints the release notes for a version: its section of CHANGELOG.md and how to install it.
# Usage: tools/release-notes.sh <version>
set -e

version="$1"
notes="$(awk -v heading="## $version" '$0 == heading { found = 1; next } /^## / { found = 0 } found' "$(dirname "$0")/../CHANGELOG.md" | sed '/./,$!d')"
if [ -z "$notes" ]; then
    echo "No section for $version in CHANGELOG.md" >&2
    exit 1
fi
printf '%s\n\n' "$notes"
echo 'Install: extract into `~/.local/share/kwin/effects/` (or clone and run `make install`), enable "Karousel Overview" in System Settings → Desktop Effects, then log out and back in.'
