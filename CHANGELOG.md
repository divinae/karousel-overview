# Changelog

## 0.6
- Dropping a window onto another one: onto its middle stacks them in Karousel's stacked layout, onto its top or bottom puts it above or below in a column whose windows are one under another, onto its left or right quarter gives it a column of its own there; whatever Karousel's "Stack columns by default" is
- The part of the window it drops onto is highlighted, and the bars showing where it lands are thicker
- A button on a hovered window makes it float, or tiles it again
- Columns with several windows have a grip on top: dragging it moves the whole column, shown as it is, between columns, onto another window like a single window would go, or to the end of another desktop (Karousel's "Move column to desktop", for the first twelve desktops)
- A "Stack"/"Unstack" button in a column's corner switches between Karousel's stacked layout and the windows one under another
- A floating window dropped where it would be tiled gets tiled there
- A window from a shared column, stacked or not, dropped between columns or on free space gets a column of its own there
- Dragging a window to another desktop: holding it over that desktop makes it current, then it can be put at any place there like on its own desktop
- Columns are recognised also when stacked, whose windows are offset from each other, and with apps like terminals that round their size to their character cells
- Dragging something from an app, e.g. a file: open the overview with its screen corner or shortcut, hold it over a window to switch to that window and drop it there, or over a desktop on the minimap to show that desktop

## 0.5.1
- Small text in the window thumbnails, also the dragged one, stays whole instead of jagged, they are rendered twice as large and scaled down

## 0.5
- Desktop minimap along the right edge, or the top: it slides out when the pointer reaches that edge (or is always shown), click a desktop to go there, and while dragging a window it's always shown, drop it on any desktop, also one far away (can be turned off)
- Drag windows from the minimap too, e.g. from a desktop far away to the one shown
- The minimap marks the selected desktop, the card a dragged window would go to stands out, and its windows show their app's icon in the theme's colours
- Moving a window to another desktop keeps the overview on the current one, the window shows where Karousel will put it
- Scrolling quickly through the desktops no longer makes the overview jump back and forth between two of them
- The gaps between windows are right from the start, also with windows Karousel doesn't tile
- The settings are grouped, options that depend on another one are greyed out while it's off
- tools/nested-run.sh refuses to run without a nested session, instead of acting on the real one

## 0.4
- The "New desktop" row looks like an empty desktop, with the current desktop's wallpaper see-through
- Clicking a window centers it (can be turned off): the strip first glides to it, then the overview zooms in, without jumps
- Desktops other than the current one show their windows in Karousel's layout instead of piled up where KWin moved them
- Desktop labels as a pill on the wallpaper's corner, shadows that show which desktop and window float above the rest
- Removing a desktop keeps the overview near it instead of going back to the first one
- The "New desktop" row can be turned off; then a window dropped after the last desktop creates one
- Restoring a minimized window shows it in its desktop's strip right away
- The effect's settings open again, they couldn't be found
- Window titles show on hover by default, the touchpad gesture uses 3 fingers by default, 4 clash with Plasma's Overview
- Optionally remove the desktops created in the overview once they're empty, like GNOME's dynamic workspaces
- Lighter rounded corners, without a mask texture per window
- The gaps between windows are Karousel's own, in pixels, instead of a separate setting
- The wallpaper no longer shifts when the overview opens or closes while the current desktop's strip isn't centered

## 0.3
- Panning the current desktop scrolls Karousel's real view column by column
- Drop a window onto another window to put it into that window's column
- The overview follows desktop switches, e.g. from Karousel's key bindings, which work in the overview too
- Each desktop shows its own wallpaper
- Minimized windows at the end of their desktop, click to restore (can be turned off)
- App icons and window titles on windows (each can be turned off)
- Smooth panning: the preview moves smoothly and Karousel's view follows once the panning stops, without jumping
- Clicking a window glides the view to it while zooming in, instead of jumping
- Each desktop's wallpaper stays in the middle with rounded corners and a shadow, the windows move past it
- Translucent windows get the blurred wallpaper behind them
- Rounded corners on windows
- Desktop number and name in a pill on the wallpaper's corner
- Smaller "New desktop" card that looks like an empty desktop
- Glowing drop hints that slide between columns

## 0.2
First release.

- Niri-style overview of all virtual desktops, each as a zoomed-out strip of its windows, including Karousel's off-screen columns
- Zooms out from the current desktop at its real size, with a blurred wallpaper and fading panels
- Toggle with Meta+Ctrl+O, a screen edge, or an optional touchpad swipe that follows the fingers
- Click a window to focus it, click a desktop to switch to it, click between desktops to close
- Drag windows to other desktops, between desktops to create a new one, or sideways to reorder their column, with hints showing where they land
- While dragging, push against the edges to scroll, or hold over a desktop to switch to it
- Scroll vertically to jump between desktops, right-click and drag or scroll horizontally to pan a desktop, settling on a column
- Arrow keys move focus like in Niri's overview, the selection follows focus changes from Karousel's key bindings
- Type to search windows, with KRunner results when nothing matches
- Close windows with middle-click, a close button or Delete
- Rename desktops by double-clicking their name, remove empty ones
- Configurable row height, gap between windows and touchpad gesture
