# Karousel Overview
A [Niri](https://github.com/YaLTeR/niri)-style overview effect for KWin, made for the [Karousel](https://github.com/peterfajdiga/karousel) scrollable tiling script.

It shows all virtual desktops stacked vertically, each one as a zoomed-out horizontal strip of its windows, including the columns scrolled off-screen.
The effect doesn't talk to Karousel directly: Karousel keeps off-screen columns at their real positions, so the strips are rebuilt from window geometry. It works without Karousel too, it just shows windows where they are.

## Usage
- Toggle with Meta+Ctrl+O, or bind it to a screen edge in System Settings → Screen Edges
- Click a window to focus it, or click an empty part of a desktop to switch to it
- Drag a window to another desktop to move it there
- Scroll or drag horizontally to pan a desktop's strip, scroll vertically to switch desktops
- Arrow keys select a window, Enter focuses it, Escape closes the overview

The height of the desktop rows can be changed in the effect's settings.

## Installation
Requires Plasma 6.

Clone the repo and run `make install`, then enable "Karousel Overview" in System Settings → Desktop Effects.
After updating, restart KWin (or log out and back in) to load the new version.

## Limitations
- Multiple screens aren't supported (neither does Karousel)
- Desktops other than the current one show their windows where Karousel last placed them
