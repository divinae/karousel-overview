# Karousel Overview: notes for AI agents

A Niri-style overview **KWin effect** (declarative QML `SceneEffect`, not a KWin script) for
Plasma 6, made as a companion to Peter Fajdiga's [Karousel](https://github.com/peterfajdiga/karousel)
scrollable-tiling KWin script: all virtual desktops stacked vertically, each a zoomed-out strip
of its columns including off-screen ones, with drag-and-drop rearranging, search (KRunner),
minimap, gestures. It requires Karousel and drives it only through Karousel's global key
bindings (Karousel has no API). Package Id `karousel_overview`, `KPackageStructure:
KWin/Effect`, settings via `kcm_kwin4_genericscripted` + `config.ui`. Author Jakub Lipiński
(GitHub `divinae`), GPL-3.0-or-later. Code at https://github.com/divinae/karousel-overview,
KDE Store https://store.kde.org/p/2379855/, GitHub releases built by CI on tags. Push target:
`origin` (`git@github.com:divinae/karousel-overview.git`), branch `master`, committed directly.

## Layout

- `package/metadata.json`: Id, `Version` (two-part, e.g. `0.11`), translation domain.
- `package/contents/config/main.xml`: kcfg, ~20 entries (`RowHeight`, `ShowIcons`,
  `RemoveEmptyDesktops`, `TouchpadGesture`, `GestureFingerCount`, `BorderActivate`, ...).
- `package/contents/ui/config.ui`: Qt Designer settings dialog; widgets named `kcfg_<Key>`.
- `package/contents/ui/main.qml`: the `KWinComponents.SceneEffect` (activation, gesture,
  shortcut, per-window layout memory, temporary desktops). Per-screen UI in
  `OverviewScreen.qml`; rows in `DesktopRow.qml` (largest file); `WindowThumb`,
  `DragController`, `DropHints`, `ExternalDrag`, `WheelNavigation`, `SearchOverlay`,
  `DesktopMinimap`, `DesktopPill`, `ColumnBar`, `Attention*`, `Backdrop`, `PanelsLayer`,
  `RoundedCorners`, `ColorCorrection`.
- `KarouselDriver.qml`: invokes Karousel's shortcuts over kglobalaccel D-Bus.
- `layout.js`: pure layout logic (`.pragma library`), the only unit-tested part.
  `i18n.js`: `tr()` / `trc()` wrappers using the effect's own domain.
- `shaders/*.frag`: shader sources; compiled `*.frag.qsb` are committed in `package/contents/ui/`.
- `lint/org/kde/kwin/`: hand-written `qmldir` + `kwin.qmltypes` stub of the part of KWin's QML
  module the effect uses (the real module only exists inside KWin).
- `po/karousel_overview.pot`, `po/pl.po`: translations. `tests/layout.test.mjs`: node tests.
- `tools/`: `nested.sh`, `nested-run.sh` (nested KWin), `extract-messages.sh`,
  `extract-ui.py` (config.ui strings for xgettext), `release-notes.sh`.
- `.github/workflows/ci.yml` (Arch container: lint, test, po up to date, shaders compile) and
  `release.yml` (on `v*` tags). `docs/screenshot.png` (README).
- Untracked, not yours to touch: `docs/kde-store.md`, `karousel_overview_*.tar.gz` in the root
  (gitignored), `package/contents/locale/` (built by `make translations`, gitignored).

## Build, run, test

- `make lint`: `/usr/lib/qt6/bin/qmllint -I lint --max-warnings 0 package/contents/ui/*.qml`.
  Must pass with zero warnings (CI enforces).
- `make test`: `node --test tests/`.
- `make messages`: `tools/extract-messages.sh` regenerates the `.pot` and `msgmerge`s the
  `.po` files. CI runs `make messages translations` and fails on `git diff po/`, so run it
  after changing any user-visible string and commit `po/`.
- `make shaders`: rebuild `.qsb` with `/usr/lib/qt6/bin/qsb --qt6` after editing `shaders/`.
- `make translations`: `msgfmt` into `package/contents/locale/`.
- `make install`: runs `test` and `translations`, then `kpackagetool6 --type=KWin/Effect`
  install-or-upgrade into the user's real data dir and copies `.mo` files to
  `$XDG_DATA_HOME/locale`. `make uninstall`, `make package` (lint + test + translations, then
  `karousel_overview_<ver_with_underscores>.tar.gz`).
- Seeing a change live: KWin caches QML per file path, so a new version only loads after a
  KWin restart, and restarting the real KWin also restarts Xwayland (kills X11 apps). Do not
  do that; use `make nested` instead (it first runs `make install`, which does update the
  user's installed copy, so ask before running it). It starts a headless KWin with its own
  D-Bus session/config in `/tmp/karousel-overview-nested` (`NESTED_STATE`), Karousel and the
  effect enabled, a few windows open. `WINDOWED=1 tools/nested.sh <state dir>` shows it in a
  window (toggle with the top-left corner or Ctrl+Alt+O). Drive it with
  `tools/nested-run.sh <state dir> <cmd...>`, e.g. the `qdbus6 ... invokeShortcut
  "Karousel Overview"` and `spectacle` examples in the README. `KAROUSEL_CONFIG=...` and
  `OVERVIEW_CONFIG=...` append settings for the nested run.

## Conventions

- QML: 4-space indent, semicolons, `const`/arrow functions, `pragma ComponentBehavior: Bound`
  where possible, `required property` inputs. Comments are lowercase, without a final period,
  explaining why, wrapped near 120 columns.
- Logic that can be tested goes into `layout.js`. `tests/layout.test.mjs` loads it via `vm`
  with an explicit export list in `Object.assign(exports, { ... })`: add new functions there.
- i18n: all effect strings via `I18n.tr()` / `I18n.trc()` from `i18n.js` (KWin's engine gives
  i18n with KWin's domain, so the effect passes `karousel_overview` itself). Settings strings
  come from `config.ui`. Never plain `i18n()`/`qsTr()` in QML.
- No SPDX headers; license in `LICENSE` and `metadata.json`.
- Versioning/release: CHANGELOG has `## Unreleased` on top, then `## 0.11` etc., each a list of
  one-sentence bullets (no dates). To release: set `Version` in `metadata.json`, rename
  "Unreleased" to the version, commit as `Release X.Y: <highlights>`, push tag `vX.Y`; the
  release workflow checks tag == version, runs `make package`, publishes a GitHub release
  with `tools/release-notes.sh` output. Tag pushes are the user's call.
- Commit subjects: capitalised summary of what changed, often several items joined by commas
  ("Ctrl+A in the search, whole column lit on grip hover, floating windows kept out of
  columns"); area prefixes like `po:` / `README:` for narrow changes; prose body;
  `Co-Authored-By:` trailer when AI-assisted.

## Gotchas

- A bug here crashes the compositor (whole session). Removing desktops while rows are being
  torn down crashed KWin, so empty desktops are removed only after each screen's overview is
  destroyed (`overviewDestroyed`, `Qt.callLater`).
- Karousel state cannot be read directly: columns are rebuilt from window geometry, and moves
  happen by focusing a window and invoking Karousel shortcuts (names in
  `Layout.KarouselShortcuts`). Non-current desktops show windows where Karousel last placed
  them (KWin pulls far off-screen windows back once a desktop is not current), kept in
  `effect.layouts` / `tiledLayouts`.
- KWin gives a window its fullscreen/maximized geometry before reporting it; `tiledGeometry`
  works around that.
- `tools/nested-run.sh` refuses to run without the nested bus, so commands never hit the real
  session; keep it that way. The nested session symlinks the real `~/.local/share/kwin` and
  `locale`, so it uses the installed effect and Karousel.
- Store installs only get settings translations; the effect's own `.mo` must be in
  `~/.local/share/locale`, which only `make install` does.
- Multi-screen: each screen shows only its windows; 4-finger swipe clashes with Plasma's
  Overview; temporary-desktop tracking is lost on KWin restart (README Limitations).
- KWin's colour-blindness correction does not reach the overview; it re-applies it itself
  (`ColorCorrection.qml`, shader).

## Related

- No code is shared with Glance, Fokus or Shift. Karousel itself is a third-party KWin script
  (installed locally under `~/.local/share/kwin/scripts/karousel`), not in this workspace.
- `.github/FUNDING.yml` (Ko-fi) is the same file used in the owner's other repos.
  `zephyr-theme`'s README lists this effect as part of the owner's setup.
