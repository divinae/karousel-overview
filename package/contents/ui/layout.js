.pragma library

// Pure layout logic of the overview, kept out of QML so that it can be tested with node (see tests/).
// Rectangles are plain {x, y, width, height} objects in workspace coordinates.

// Karousel's key bindings, the only way to control it from outside
const KarouselShortcuts = {
    columnMoveLeft: "karousel-column-move-left",
    columnMoveRight: "karousel-column-move-right",
    // a window alone in its column joins the neighbouring column, otherwise it leaves its column to that side
    windowMoveLeft: "karousel-window-move-left",
    windowMoveRight: "karousel-window-move-right",
    // within its column
    windowMoveUp: "karousel-window-move-up",
    windowMoveDown: "karousel-window-move-down",
    // between the windows of the focused column one under another and only one expanded at a time
    columnToggleStacked: "karousel-column-toggle-stacked",
    // the active window between tiled by Karousel and floating
    windowToggleFloating: "karousel-window-toggle-floating",
    // the focused column, kept together, to the end of desktop N, from 1 to 12, followed by the number
    columnMoveToDesktop: "karousel-column-move-to-desktop-",
    // moves the view by one column, without changing focus
    scrollLeftColumn: "karousel-grid-scroll-left-column",
    scrollRightColumn: "karousel-grid-scroll-right-column",
    // scrolls so that the focused window is in the middle of the screen
    scrollFocused: "karousel-grid-scroll-focused",
};

function repeat(name, count) {
    return Array(Math.max(0, count)).fill(name);
}

function clamp(value, min, max) {
    return Math.max(min, Math.min(value, max));
}

// horizontal extent of a strip: the screen plus all of its windows,
// Karousel keeps off-screen columns at their real positions
function stripBounds(screen, geometries) {
    let minX = screen.x;
    let maxX = screen.x + screen.width;
    for (const geometry of geometries) {
        minX = Math.min(minX, geometry.x);
        maxX = Math.max(maxX, geometry.x + geometry.width);
    }
    return { minX: minX, maxX: maxX };
}

// groups windows into Karousel columns, sorted from left to right: windows lined up the way Karousel lines them up,
// tiled ones one under another at the same x, stacked ones each offset a little from the one before, of about the same
// width, apps like terminals round their size to their character cells; a floating window over a column isn't in it;
// entries are {window, geometry}, columns are {x, y, width, bottom, windows}, each one's windows from top to bottom
function computeColumns(entries) {
    const columns = [];
    for (const entry of entries.slice().sort((a, b) => a.geometry.y - b.geometry.y)) {
        const geometry = entry.geometry;
        const right = geometry.x + geometry.width;
        const column = columns.find(column => {
            const last = column.last;
            const tolerance = Math.max(4, 0.04 * geometry.width);
            if (Math.abs(geometry.x - last.x) > tolerance || Math.abs(geometry.width - last.width) > Math.max(16, 0.04 * geometry.width)) {
                return false;
            }
            // below the one before, or over it only by the little a stacked column offsets its windows
            return geometry.y >= last.y + last.height - 2 || geometry.y - last.y <= 0.1 * last.height;
        });
        if (column === undefined) {
            columns.push({
                x: geometry.x,
                y: geometry.y,
                width: geometry.width,
                bottom: geometry.y + geometry.height,
                windows: [entry.window],
                last: geometry,
            });
        } else {
            const columnRight = Math.max(column.x + column.width, right);
            column.x = Math.min(column.x, geometry.x);
            column.width = columnRight - column.x;
            column.y = Math.min(column.y, geometry.y);
            column.bottom = Math.max(column.bottom, geometry.y + geometry.height);
            column.windows.push(entry.window);
            column.last = geometry;
        }
    }
    for (const column of columns) {
        delete column.last;
    }
    return columns.sort((a, b) => a.x - b.x);
}

// the position in the column order where a column dropped at dropX lands,
// columnCenters are sorted and in the same coordinates as dropX
function reorderTarget(columnCenters, source, dropX) {
    let target = 0;
    columnCenters.forEach((center, i) => {
        if (i !== source && center < dropX) {
            target++;
        }
    });
    return target;
}

// where to show the insertion hint for a column moved to target, between the other columns;
// columnEdges are the {left, right} of the other columns, sorted, or null if there are none
function insertHintX(columnEdges, target) {
    if (columnEdges.length === 0) {
        return null;
    }
    if (target <= 0) {
        return columnEdges[0].left;
    }
    if (target >= columnEdges.length) {
        return columnEdges[columnEdges.length - 1].right;
    }
    return (columnEdges[target - 1].right + columnEdges[target].left) / 2;
}

// Karousel shortcuts that move the focused window from the column at index source into the column at index target;
// columnSizes are the numbers of windows in the columns, from left to right
function stackMoves(columnSizes, source, target) {
    if (source === target) {
        return [];
    }
    const moves = [];
    let position = source;
    let targetPosition = target;
    if (columnSizes[source] > 1) {
        // take the window out of its column first, into a new column on its right
        moves.push(KarouselShortcuts.windowMoveRight);
        position = source + 1;
        if (target > source) {
            targetPosition = target + 1;
        }
    }
    if (targetPosition < position) {
        // right next to the target column on its right, then join it
        moves.push(...repeat(KarouselShortcuts.columnMoveLeft, position - targetPosition - 1));
        moves.push(KarouselShortcuts.windowMoveLeft);
    } else {
        // right next to the target column on its left, then join it
        moves.push(...repeat(KarouselShortcuts.columnMoveRight, targetPosition - position - 1));
        moves.push(KarouselShortcuts.windowMoveRight);
    }
    return moves;
}

// the index of the column with the window in it, -1 when none has it
function columnIndex(columns, window) {
    return columns.findIndex(column => column.windows.includes(window));
}

// whether Karousel tiles a column, which then starts at the top of the desktop's area and reaches its bottom, or at
// least more than half of its height for windows that can't be as tall; Karousel limits windows to half of that height
// when they start floating
function isTiledColumn(column, area, tolerance) {
    return column.y <= area.y + tolerance
        && (column.bottom >= area.y + area.height - tolerance || column.bottom - column.y > area.height * 0.55);
}

// where a window dropped onto another one goes, from the pointer's offset from that window's middle in fractions of
// its size: its left or right quarter gives it a column of its own beside it ("tile"), of the rest the top and bottom
// fifths put it above or below it in its column ("beside"), the middle stacks them ("stack") when canStack, otherwise
// it's the top or bottom half; side is -1 for left or above, 1 for right or below
function dropZone(dx, dy, canStack) {
    if (Math.abs(dx) > 0.25) {
        return { kind: "tile", side: dx < 0 ? -1 : 1 };
    }
    if (Math.abs(dy) > 0.3 || !canStack) {
        return { kind: "beside", side: dy < 0 ? -1 : 1 };
    }
    return { kind: "stack", side: 1 };
}

// how many columns Karousel's view has to scroll so that the column closest to targetX is where the one closest to
// viewX is now, positive to the left; columnLefts in the same coordinates
function scrollSteps(columnLefts, viewX, targetX) {
    const closest = x => columnLefts.reduce((best, left, i) => Math.abs(left - x) < Math.abs(columnLefts[best] - x) ? i : best, 0);
    return closest(targetX) - closest(viewX);
}

// where a column width wide goes at the end of a desktop's strip, as Karousel puts it, its others the rects of the
// windows there: after the last one, and as tall as they are, or in the middle of an empty desktop's area
function placeAtEnd(others, area, width, gap) {
    if (others.length === 0) {
        return { x: area.x + (area.width - width) / 2, y: area.y, height: area.height };
    }
    const top = Math.min(...others.map(other => other.y));
    return {
        x: Math.max(...others.map(other => other.x + other.width)) + gap,
        y: top,
        height: Math.max(...others.map(other => other.y + other.height)) - top,
    };
}

// whether a column's windows, given from top to bottom, are in Karousel's stacked layout, where they overlap
function isStacked(geometries) {
    for (let i = 1; i < geometries.length; i++) {
        if (geometries[i].y < geometries[i - 1].y + geometries[i - 1].height - 1) {
            return true;
        }
    }
    return false;
}

// Karousel shortcuts that move the focused window into the column of the target window, right above it for side -1 or
// below it for side 1; source and target are the indexes of their columns, index and targetIndex their positions in them
function stackBesideMoves(columnSizes, source, index, target, targetIndex, side) {
    const moves = stackMoves(columnSizes, source, target);
    // Karousel adds a window joining a column at its bottom
    const position = source === target ? index : columnSizes[target];
    const otherTarget = targetIndex > position ? targetIndex - 1 : targetIndex;
    const final = side < 0 ? otherTarget : otherTarget + 1;
    moves.push(...repeat(final < position ? KarouselShortcuts.windowMoveUp : KarouselShortcuts.windowMoveDown, Math.abs(final - position)));
    return moves;
}

// Karousel shortcuts that take the focused window out of its shared column at index source into a column of its own,
// which ends up where index target is among all the columns, its old one too
function expelMoves(source, target) {
    // a new column on its right first
    const position = source + 1;
    return [KarouselShortcuts.windowMoveRight,
        ...repeat(target < position ? KarouselShortcuts.columnMoveLeft : KarouselShortcuts.columnMoveRight, Math.abs(target - position))];
}

// Karousel shortcuts that move the focused window from the column at index source into a column of its own right next
// to the column at index target, on its left for side -1, on its right for side 1; columnSizes as for stackMoves
function tileMoves(columnSizes, source, target, side) {
    const moves = [];
    let position = source;
    let targetPosition = target;
    if (columnSizes[source] > 1) {
        // take the window out of its column first, into a new column on its right
        moves.push(KarouselShortcuts.windowMoveRight);
        position = source + 1;
        if (target > source) {
            targetPosition = target + 1;
        }
    }
    // where the window's column goes among the other columns
    const otherTarget = targetPosition > position ? targetPosition - 1 : targetPosition;
    const final = side < 0 ? otherTarget : otherTarget + 1;
    moves.push(...repeat(final < position ? KarouselShortcuts.columnMoveLeft : KarouselShortcuts.columnMoveRight, Math.abs(final - position)));
    return moves;
}

// positions of minimized windows, laid out one after another from startX; returns their x and where they end
function minimizedSlots(widths, startX, gap) {
    const xs = [];
    let x = startX;
    for (const width of widths) {
        xs.push(x);
        x += width + gap;
    }
    return { xs: xs, end: widths.length > 0 ? x - gap : startX };
}

// the scroll position that lines up the column edge closest to left with it, where left is offset from the scroll
// position, or null if there's nothing to snap to
function snapTarget(columnLefts, left, offset, minContentX, maxContentX) {
    let closest = null;
    for (const x of columnLefts) {
        if (closest === null || Math.abs(x - left) < Math.abs(closest - left)) {
            closest = x;
        }
    }
    return closest === null ? null : clamp(closest - offset, minContentX, maxContentX);
}

// scale of the rows while zooming, from fullScale (a row's viewport frame fills the screen) to 1
function zoomScale(fullScale, zoom) {
    return fullScale + (1 - fullScale) * zoom;
}

// offset of the rows while zooming, keeps the viewport frame at origin on the screen's corner at zoom 0
function zoomOffset(fullScale, origin, zoom) {
    return -fullScale * origin * (1 - zoom);
}

// accumulates vertical scrolling into steps of one desktop, one mouse wheel notch is 120;
// returns the new accumulated value and the step (-1, 0 or 1)
function wheelStep(accumulated, delta) {
    if (Math.sign(delta) !== Math.sign(accumulated)) {
        accumulated = 0;
    }
    accumulated += delta;
    if (Math.abs(accumulated) >= 120) {
        return { accumulated: 0, step: accumulated > 0 ? -1 : 1 };
    }
    return { accumulated: accumulated, step: 0 };
}

// how fast to scroll when dragging close to an edge, from -1 (left) to 1 (right)
function edgeScrollSpeed(position, size, zone) {
    if (position < zone) {
        return -(1 - Math.max(0, position) / zone);
    }
    if (position > size - zone) {
        return 1 - Math.max(0, size - position) / zone;
    }
    return 0;
}


// the desktops without windows, except the kept ones, and never all of them
function emptyDesktops(desktops, windowDesktops, kept) {
    const used = new Set();
    for (const windowDesktopList of windowDesktops) {
        for (const desktop of windowDesktopList) {
            used.add(desktop);
        }
    }
    const empty = desktops.filter(desktop => !used.has(desktop) && !kept.includes(desktop));
    return empty.length === desktops.length ? empty.slice(1) : empty;
}

// Karousel's gaps between columns and between the windows in a column, measured from where it put the windows
// of one desktop, since its settings can't be read from here; the most common one, Karousel's gaps are all the same,
// a window it doesn't tile can be anywhere; null where there's nothing to measure
function innerGaps(geometries) {
    const columns = computeColumns(geometries.map(geometry => ({ window: geometry, geometry: geometry })));
    const horizontal = [];
    for (let i = 1; i < columns.length; i++) {
        horizontal.push(columns[i].x - (columns[i - 1].x + columns[i - 1].width));
    }
    const vertical = [];
    for (const column of columns) {
        const windows = column.windows.slice().sort((a, b) => a.y - b.y);
        for (let i = 1; i < windows.length; i++) {
            vertical.push(windows[i].y - (windows[i - 1].y + windows[i - 1].height));
        }
    }
    return { horizontal: mostCommon(horizontal), vertical: mostCommon(vertical) };
}

// the most common of the non-negative values, rounded, the smallest of those when there's a tie; null when none
function mostCommon(values) {
    const counts = new Map();
    for (const value of values) {
        if (value >= 0) {
            const rounded = Math.round(value);
            counts.set(rounded, (counts.get(rounded) ?? 0) + 1);
        }
    }
    let best = null;
    for (const [value, count] of counts) {
        if (best === null || count > counts.get(best) || (count === counts.get(best) && value < best)) {
            best = value;
        }
    }
    return best;
}
