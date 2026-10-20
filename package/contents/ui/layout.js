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
    // moves the view by one column, without changing focus
    scrollLeftColumn: "karousel-grid-scroll-left-column",
    scrollRightColumn: "karousel-grid-scroll-right-column",
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

// groups windows into Karousel columns, which share x and width, sorted from left to right;
// entries are {window, geometry}, columns are {x, y, width, bottom, windows}
function computeColumns(entries) {
    const columnMap = new Map();
    for (const entry of entries) {
        const geometry = entry.geometry;
        const key = Math.round(geometry.x) + ":" + Math.round(geometry.width);
        const column = columnMap.get(key);
        if (column === undefined) {
            columnMap.set(key, {
                x: geometry.x,
                y: geometry.y,
                width: geometry.width,
                bottom: geometry.y + geometry.height,
                windows: [entry.window],
            });
        } else {
            column.y = Math.min(column.y, geometry.y);
            column.bottom = Math.max(column.bottom, geometry.y + geometry.height);
            column.windows.push(entry.window);
        }
    }
    return Array.from(columnMap.values()).sort((a, b) => a.x - b.x);
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
