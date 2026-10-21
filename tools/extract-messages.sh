#!/bin/bash
# Collects the translatable strings into po/karousel_overview.pot and updates the translations in po/ with them:
# the effect's, through i18n.js, and the settings dialog's, from config.ui.
set -e
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 tools/extract-ui.py package/contents/ui/config.ui > "$tmp/config.ui.js"
# QML is close enough to JavaScript for xgettext
xgettext --from-code=UTF-8 --language=JavaScript --add-comments=i18n: --sort-by-file \
    --keyword= --keyword=tr:1 --keyword=trc:1c,2 --keyword=i18n:1 \
    --package-name=karousel_overview --msgid-bugs-address=https://github.com/divinae/karousel-overview/issues \
    --output="$tmp/messages.pot" package/contents/ui/*.qml "$tmp/config.ui.js"
# the date changes on every run, and the check in CI compares the files
sed -e '/^"POT-Creation-Date:/d' -e "s|$tmp/||" "$tmp/messages.pot" > po/karousel_overview.pot
shopt -s nullglob
for po in po/*.po; do
    msgmerge --quiet --update --backup=none --no-fuzzy-matching "$po" po/karousel_overview.pot
done
