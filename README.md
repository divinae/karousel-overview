# Karousel Overview
A [Niri](https://github.com/YaLTeR/niri)-style overview effect for KWin, made for the [Karousel](https://github.com/peterfajdiga/karousel) scrollable tiling script.

It shows all virtual desktops stacked vertically, each one as a zoomed-out horizontal strip of its windows, including the columns scrolled off-screen.
The effect doesn't talk to Karousel directly: Karousel keeps off-screen columns at their real positions, so the strips are rebuilt from window geometry. It works without Karousel too, it just shows windows where they are.

## Usage
- Toggle with Meta+Ctrl+O, a screen edge (System Settings → Screen Edges) or a touchpad swipe up (enable in the effect's settings)
- Click a window to focus it, or click an empty part of a desktop to switch to it
- Drag a window to another desktop to move it there, or to the "New desktop" row to create one
- Drag a window sideways within its desktop to reorder its column (uses Karousel's "Move column left/right" key bindings)
- Middle-click a window or use its close button to close it
- Type to filter windows by name; if nothing matches, KRunner results are shown
- Scroll vertically to jump between desktops, scroll horizontally (or Shift+scroll) to pan a desktop's strip
- Arrow keys move focus between windows and desktops (Karousel scrolls along), Enter closes the overview on the focused window, Delete closes it, Escape clears the search or closes the overview

The height of the desktop rows, the gap between windows and the touchpad gesture can be changed in the effect's settings.

## Installation
Requires Plasma 6.

Clone the repo and run `make install`, then enable "Karousel Overview" in System Settings → Desktop Effects.
After updating, restart KWin (or log out and back in) to load the new version.

## Limitations
- With multiple screens, each screen only shows the windows that are on it (Karousel itself doesn't support multiple screens)
- The 4-finger swipe clashes with Plasma's own Overview effect
- Desktops other than the current one show their windows where Karousel last placed them
