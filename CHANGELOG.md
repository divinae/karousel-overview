# Changelog

## 0.10
- A stacked column spreads out in the overview while the pointer rests on it or on its grip, or a window in it is chosen with the arrow keys: its windows one under another, each with its title, so any of them can be picked; Karousel's layout stays as it is, and the column stacks back when the pointer leaves
- Color blindness correction in the overview: KWin's correction only applies to windows as KWin draws them, so the overview, which draws them itself, showed uncorrected colors; set the same mode and intensity in the overview's settings, it applies while KWin's correction is turned on

## 0.9
- A fullscreen or maximized window is shown in its column's place, which Karousel keeps for it, instead of over the whole strip and all the other windows: on a dark card like a screen, with a "Fullscreen" or "Maximized" label, and the place follows Karousel's scrolling

## 0.8.2
- A column's grip sits entirely above the column, no longer half over its top window, which could take the drag and move only itself
- A thin frame around a column's windows, from the middle of its grip, which sits on it like a tab, shows what the grip moves again; it fades in once the windows have moved, instead of jumping ahead of them, and hides while a window is dragged; the grip is a little see-through and floats on it with a shadow
- A floating window lying over a column's grip no longer takes a drag that started on the grip

## 0.8.1
- While searching, the desktop shown in the overview is the current one, so an app started from the results opens there instead of on the one the overview was opened on; a result that goes to a window elsewhere still goes there
- Clicking a window in a stacked column centers it, the column narrowed instead; clicking another window in a centered column keeps it centered
- A centered column with windows a little narrower than it, like terminals, is taken as centered
- Columns with several windows no longer have a frame around them, it jumped while Karousel moved them; their grip shows them
- As soon as a window is clicked or the overview closes, the windows' icons, titles and buttons and the columns' grips and Stack buttons hide, instead of lagging behind the zoom; not while a touchpad gesture opens the overview

## 0.8
- A search field at the top, "Type to search": typing still goes there right away, ✕ clears it, Ctrl+A selects the text, so that typing replaces it and Backspace or Delete clears it
- While searching, a card with KRunner's results, apps and more, shows right below the field, and the current desktop's matching windows below it; Up or Tab goes from the windows into the results, Down from the last one back, the other desktops fade
- The search field grows into a see-through, blurred panel with the results while searching
- Settings for the search: "Search field always shown", otherwise it shows once typing starts; "Search windows too", otherwise it only looks for apps and more, like KRunner; "Windows first, then apps", whether typing goes to the windows or to the apps first
- Hovering a window no longer starts the mode for things dragged from apps, which showed the minimap and closed the overview on that window
- A column is grabbed by the whole strip above it, not only by the pill in its middle, and the whole column lights up on hover, so that it's clear what moves; a window grabbed by its title bar right below no longer takes the drag from the grip
- A floating window over a column is no longer taken for one of its windows, which also kept it from being dragged

## 0.7
- Translations: the overview and its settings can be translated, Polish is the first, see "Translating" in the README
- Dragging is lighter: what's under a dragged window is worked out once, and not at all while the pointer holds still
- A window moved back from another desktop and dropped beside a window gets its own column, it was taken for a floating one
- Activities: the overview takes only the current activity's windows into account everywhere, keeps Karousel's layout for each activity, and follows a switch to another activity while it's open
- Drop zones and placement rules are covered by tests, the big QML files are split into smaller ones

## 0.6.1
- The minimap's card for a new desktop shows that desktop's row, instead of going back to the one shown before
- Letting go of the current desktop's row after panning it scrolls Karousel by its own columns, floating windows and the search don't throw it off
- A desktop's remove button only shows when it has no windows in any activity
- Two drops right after each other both get the column layout they asked for, and Karousel gets more time to place a window before it's moved on
- A window or column moved from a desktop that isn't current shows on the other one where Karousel had it

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
