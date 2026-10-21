import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

// layout.js is a QML JavaScript library, load it without the .pragma line
const source = readFileSync(new URL("../package/contents/ui/layout.js", import.meta.url), "utf8")
    .replace(/^\.pragma library$/m, "");
const Layout = {};
vm.runInNewContext(source + "\nObject.assign(exports, { KarouselShortcuts, clamp, stripBounds, computeColumns, reorderTarget, insertHintX, stackMoves, stackBesideMoves, isStacked, expelMoves, columnIndex, isTiledColumn, dropZone, scrollSteps, placeAtEnd, tileMoves, minimizedSlots, snapTarget, zoomScale, zoomOffset, wheelStep, edgeScrollSpeed, emptyDesktops, innerGaps });", { exports: Layout });

const rect = (x, y, width, height) => ({ x, y, width, height });
// objects from the vm context have that context's prototypes, which deepEqual tells apart
const plain = value => JSON.parse(JSON.stringify(value));

test("stripBounds covers the screen when there are no windows", () => {
    assert.deepEqual(plain(Layout.stripBounds(rect(0, 0, 1920, 1080), [])), { minX: 0, maxX: 1920 });
});

test("stripBounds includes off-screen columns", () => {
    const bounds = Layout.stripBounds(rect(0, 0, 1920, 1080), [rect(-800, 0, 700, 1000), rect(1500, 0, 900, 1000)]);
    assert.deepEqual(plain(bounds), { minX: -800, maxX: 2400 });
});

test("computeColumns groups windows sharing x and width, sorted from left to right", () => {
    const columns = Layout.computeColumns([
        { window: "c", geometry: rect(1000, 0, 500, 1000) },
        { window: "a1", geometry: rect(0, 0, 800, 490) },
        { window: "a2", geometry: rect(0.4, 510, 800, 490) },
        { window: "b", geometry: rect(810, 0, 180, 1000) },
    ]);
    assert.deepEqual(plain(columns.map(column => column.windows)), [["a1", "a2"], ["b"], ["c"]]);
    assert.equal(columns[0].y, 0);
    assert.equal(columns[0].bottom, 1000);
});

test("computeColumns groups a stacked column, whose windows are offset from each other", () => {
    const columns = Layout.computeColumns([
        { window: "s2", geometry: rect(20, 30, 760, 970) },
        { window: "s1", geometry: rect(0, 0, 760, 970) },
        { window: "s3", geometry: rect(40, 60, 760, 970) },
        { window: "b", geometry: rect(810, 0, 760, 1000) },
    ]);
    assert.deepEqual(plain(columns.map(column => column.windows)), [["s1", "s2", "s3"], ["b"]]);
    assert.equal(columns[0].x, 0);
    assert.equal(columns[0].width, 800);
});

test("computeColumns groups windows whose size is rounded to their character cells", () => {
    const columns = Layout.computeColumns([
        { window: "k1", geometry: rect(417, 6, 850, 700) },
        { window: "k2", geometry: rect(417, 718, 843, 716) },
        { window: "k3", geometry: rect(1275, 6, 890, 1428) },
    ]);
    assert.deepEqual(plain(columns.map(column => column.windows)), [["k1", "k2"], ["k3"]]);
});

test("computeColumns keeps a narrower window over a column out of it", () => {
    const columns = Layout.computeColumns([
        { window: "tiled", geometry: rect(0, 0, 800, 1000) },
        { window: "dialog", geometry: rect(200, 300, 400, 300) },
    ]);
    assert.deepEqual(plain(columns.map(column => column.windows)), [["tiled"], ["dialog"]]);
});

test("computeColumns of an empty row is empty", () => {
    assert.deepEqual(plain(Layout.computeColumns([])), []);
});

test("reorderTarget counts the other columns left of the drop point", () => {
    const centers = [100, 300, 500, 700];
    assert.equal(Layout.reorderTarget(centers, 0, 600), 2);
    assert.equal(Layout.reorderTarget(centers, 3, 200), 1);
    assert.equal(Layout.reorderTarget(centers, 1, 0), 0);
    assert.equal(Layout.reorderTarget(centers, 1, 1000), 3);
    assert.equal(Layout.reorderTarget(centers, 2, 500), 2);
});

test("insertHintX is between the neighbouring columns", () => {
    const edges = [{ left: 0, right: 100 }, { left: 110, right: 300 }, { left: 310, right: 400 }];
    assert.equal(Layout.insertHintX(edges, 0), 0);
    assert.equal(Layout.insertHintX(edges, 1), 105);
    assert.equal(Layout.insertHintX(edges, 2), 305);
    assert.equal(Layout.insertHintX(edges, 3), 400);
});

test("insertHintX without other columns has nowhere to show", () => {
    assert.equal(Layout.insertHintX([], 0), null);
});

test("snapTarget lines up the closest column with the left edge", () => {
    assert.equal(Layout.snapTarget([10, 400, 900], 380, 10, 0, 2000), 390);
    assert.equal(Layout.snapTarget([10, 400, 900], 700, 10, 0, 2000), 890);
});

test("snapTarget stays within the scroll range", () => {
    assert.equal(Layout.snapTarget([10, 400, 900], 900, 10, 0, 500), 500);
    assert.equal(Layout.snapTarget([5], 0, 10, 0, 500), 0);
    assert.equal(Layout.snapTarget([5], 0, 300, -400, 500), -295);
});

test("snapTarget without columns has nothing to snap to", () => {
    assert.equal(Layout.snapTarget([], 100, 10, 0, 500), null);
});

test("zoom starts with the viewport frame filling the screen and ends at the overview", () => {
    const fullScale = 2;
    const origin = 300;
    // at zoom 0, the frame's corner lands on the screen's corner
    assert.equal(Layout.zoomScale(fullScale, 0) * origin + Layout.zoomOffset(fullScale, origin, 0), 0);
    assert.equal(Layout.zoomScale(fullScale, 1), 1);
    assert.equal(Layout.zoomOffset(fullScale, origin, 1), -0);
});

test("wheelStep moves one desktop per notch", () => {
    assert.deepEqual(plain(Layout.wheelStep(0, -120)), { accumulated: 0, step: 1 });
    assert.deepEqual(plain(Layout.wheelStep(0, 120)), { accumulated: 0, step: -1 });
});

test("wheelStep accumulates small touchpad deltas", () => {
    let state = { accumulated: 0, step: 0 };
    const steps = [];
    for (let i = 0; i < 10; i++) {
        state = Layout.wheelStep(state.accumulated, -30);
        steps.push(state.step);
    }
    assert.deepEqual(steps, [0, 0, 0, 1, 0, 0, 0, 1, 0, 0]);
});

test("wheelStep restarts when the direction changes", () => {
    assert.deepEqual(plain(Layout.wheelStep(100, -30)), { accumulated: -30, step: 0 });
});

test("edgeScrollSpeed is fastest at the edges and zero in the middle", () => {
    assert.equal(Layout.edgeScrollSpeed(0, 1000, 100), -1);
    assert.equal(Layout.edgeScrollSpeed(50, 1000, 100), -0.5);
    assert.equal(Layout.edgeScrollSpeed(500, 1000, 100), 0);
    assert.equal(Layout.edgeScrollSpeed(950, 1000, 100), 0.5);
    assert.equal(Layout.edgeScrollSpeed(1010, 1000, 100), 1);
});

test("stackMoves joins the neighbouring column directly", () => {
    const S = Layout.KarouselShortcuts;
    assert.deepEqual(plain(Layout.stackMoves([1, 1, 1], 1, 0)), [S.windowMoveLeft]);
    assert.deepEqual(plain(Layout.stackMoves([1, 1, 1], 1, 2)), [S.windowMoveRight]);
});

test("stackMoves moves the column next to the target first", () => {
    const S = Layout.KarouselShortcuts;
    assert.deepEqual(plain(Layout.stackMoves([1, 2, 1, 1], 3, 0)), [S.columnMoveLeft, S.columnMoveLeft, S.windowMoveLeft]);
    assert.deepEqual(plain(Layout.stackMoves([1, 1, 2, 1], 0, 3)), [S.columnMoveRight, S.columnMoveRight, S.windowMoveRight]);
});

test("stackMoves takes the window out of a shared column first", () => {
    const S = Layout.KarouselShortcuts;
    // out to a new column on the right, which is then next to the target on the right
    assert.deepEqual(plain(Layout.stackMoves([2, 1], 0, 1)), [S.windowMoveRight, S.windowMoveRight]);
    assert.deepEqual(plain(Layout.stackMoves([1, 3], 1, 0)), [S.windowMoveRight, S.columnMoveLeft, S.windowMoveLeft]);
    assert.deepEqual(plain(Layout.stackMoves([2, 1, 1], 0, 2)), [S.windowMoveRight, S.columnMoveRight, S.windowMoveRight]);
});

test("stackMoves onto its own column does nothing", () => {
    assert.deepEqual(plain(Layout.stackMoves([2, 1], 0, 0)), []);
});

test("minimizedSlots lays windows out one after another", () => {
    assert.deepEqual(plain(Layout.minimizedSlots([100, 50], 1000, 10)), { xs: [1000, 1110], end: 1160 });
    assert.deepEqual(plain(Layout.minimizedSlots([], 1000, 10)), { xs: [], end: 1000 });
});

test("Karousel shortcut names match Karousel's key bindings", () => {
    assert.equal(Layout.KarouselShortcuts.columnMoveLeft, "karousel-column-move-left");
    assert.equal(Layout.KarouselShortcuts.columnMoveRight, "karousel-column-move-right");
    assert.equal(Layout.KarouselShortcuts.windowMoveLeft, "karousel-window-move-left");
    assert.equal(Layout.KarouselShortcuts.windowMoveRight, "karousel-window-move-right");
    assert.equal(Layout.KarouselShortcuts.scrollLeftColumn, "karousel-grid-scroll-left-column");
    assert.equal(Layout.KarouselShortcuts.scrollRightColumn, "karousel-grid-scroll-right-column");
    assert.equal(Layout.KarouselShortcuts.scrollFocused, "karousel-grid-scroll-focused");
    assert.equal(Layout.KarouselShortcuts.windowMoveUp, "karousel-window-move-up");
    assert.equal(Layout.KarouselShortcuts.windowMoveDown, "karousel-window-move-down");
    assert.equal(Layout.KarouselShortcuts.columnToggleStacked, "karousel-column-toggle-stacked");
    assert.equal(Layout.KarouselShortcuts.windowToggleFloating, "karousel-window-toggle-floating");
    assert.equal(Layout.KarouselShortcuts.columnMoveToDesktop + 3, "karousel-column-move-to-desktop-3");
});

test("emptyDesktops leaves out desktops with windows and kept ones", () => {
    assert.deepEqual(plain(Layout.emptyDesktops(["a", "b", "c", "d"], [["a"], ["a", "c"]], ["b"])), ["d"]);
});

test("emptyDesktops never removes every desktop", () => {
    assert.deepEqual(plain(Layout.emptyDesktops(["a", "b"], [], [])), ["b"]);
});

test("innerGaps measures the smallest gap between columns and between windows in a column", () => {
    // two columns 8 px apart, the second one with two windows 4 px apart, and a third column further away
    const geometries = [rect(0, 0, 100, 500), rect(108, 0, 100, 248), rect(108, 252, 100, 248), rect(300, 0, 100, 500)];
    assert.deepEqual(plain(Layout.innerGaps(geometries)), { horizontal: 8, vertical: 4 });
});

test("innerGaps has nothing to measure with a single window", () => {
    assert.deepEqual(plain(Layout.innerGaps([rect(0, 0, 100, 500)])), { horizontal: null, vertical: null });
});

test("innerGaps takes the most common gap, a window Karousel doesn't tile can be close to a column", () => {
    // columns 8 px apart, and a floating window 2 px after the last one
    const geometries = [rect(0, 0, 100, 500), rect(108, 0, 100, 500), rect(216, 0, 100, 500), rect(318, 100, 50, 50)];
    assert.equal(Layout.innerGaps(geometries).horizontal, 8);
});

test("tileMoves moves a window alone in its column next to the target", () => {
    const S = Layout.KarouselShortcuts;
    assert.deepEqual(plain(Layout.tileMoves([1, 1, 1], 0, 2, 1)), [S.columnMoveRight, S.columnMoveRight]);
    assert.deepEqual(plain(Layout.tileMoves([1, 1, 1], 0, 2, -1)), [S.columnMoveRight]);
    assert.deepEqual(plain(Layout.tileMoves([1, 1, 1], 2, 0, -1)), [S.columnMoveLeft, S.columnMoveLeft]);
    // already there
    assert.deepEqual(plain(Layout.tileMoves([1, 1], 0, 1, -1)), []);
});

test("tileMoves takes the window out of a shared column", () => {
    const S = Layout.KarouselShortcuts;
    assert.deepEqual(plain(Layout.tileMoves([2, 1], 0, 1, -1)), [S.windowMoveRight]);
    assert.deepEqual(plain(Layout.tileMoves([1, 2], 1, 0, 1)), [S.windowMoveRight, S.columnMoveLeft]);
    // beside the column it was in
    assert.deepEqual(plain(Layout.tileMoves([3], 0, 0, 1)), [S.windowMoveRight]);
    assert.deepEqual(plain(Layout.tileMoves([3], 0, 0, -1)), [S.windowMoveRight, S.columnMoveLeft]);
});

test("stackBesideMoves puts the window above or below the target in its column", () => {
    const S = Layout.KarouselShortcuts;
    // joins at the bottom, below the only window there already
    assert.deepEqual(plain(Layout.stackBesideMoves([1, 1], 0, 0, 1, 0, 1)), [S.windowMoveRight]);
    assert.deepEqual(plain(Layout.stackBesideMoves([1, 1], 0, 0, 1, 0, -1)), [S.windowMoveRight, S.windowMoveUp]);
    assert.deepEqual(plain(Layout.stackBesideMoves([1, 3], 0, 0, 1, 1, -1)), [S.windowMoveRight, S.windowMoveUp, S.windowMoveUp]);
    // within its own column
    assert.deepEqual(plain(Layout.stackBesideMoves([3], 0, 0, 0, 2, 1)), [S.windowMoveDown, S.windowMoveDown]);
    assert.deepEqual(plain(Layout.stackBesideMoves([3], 0, 2, 0, 1, -1)), [S.windowMoveUp]);
    // already there
    assert.deepEqual(plain(Layout.stackBesideMoves([3], 0, 0, 0, 1, -1)), []);
});

test("isStacked tells overlapping windows from ones one under another", () => {
    assert.equal(Layout.isStacked([rect(0, 0, 800, 970), rect(8, 32, 800, 970)]), true);
    assert.equal(Layout.isStacked([rect(0, 0, 800, 490), rect(0, 500, 800, 490)]), false);
    assert.equal(Layout.isStacked([rect(0, 0, 800, 1000)]), false);
});

test("expelMoves takes the window out of its column to where it's dropped", () => {
    const S = Layout.KarouselShortcuts;
    // right after its old column, left of it, after the last one
    assert.deepEqual(plain(Layout.expelMoves(0, 1)), [S.windowMoveRight]);
    assert.deepEqual(plain(Layout.expelMoves(1, 1)), [S.windowMoveRight, S.columnMoveLeft]);
    assert.deepEqual(plain(Layout.expelMoves(0, 3)), [S.windowMoveRight, S.columnMoveRight, S.columnMoveRight]);
    assert.deepEqual(plain(Layout.expelMoves(1, 0)), [S.windowMoveRight, S.columnMoveLeft, S.columnMoveLeft]);
});

test("columnIndex finds the column with the window", () => {
    const columns = [{ windows: ["a"] }, { windows: ["b", "c"] }];
    assert.equal(Layout.columnIndex(columns, "c"), 1);
    assert.equal(Layout.columnIndex(columns, "d"), -1);
});

test("isTiledColumn tells tiled columns from floating windows", () => {
    const area = rect(0, 0, 1920, 1080);
    // full height, with gaps
    assert.equal(Layout.isTiledColumn({ y: 6, bottom: 1074 }, area, 72), true);
    // a window that can't be as tall, but more than half
    assert.equal(Layout.isTiledColumn({ y: 6, bottom: 700 }, area, 72), true);
    // floating, limited to half of the height
    assert.equal(Layout.isTiledColumn({ y: 6, bottom: 540 }, area, 72), false);
    assert.equal(Layout.isTiledColumn({ y: 300, bottom: 1074 }, area, 72), false);
});

test("dropZone splits a window into sides, top and bottom, and middle", () => {
    assert.deepEqual(plain(Layout.dropZone(-0.4, 0, true)), { kind: "tile", side: -1 });
    assert.deepEqual(plain(Layout.dropZone(0.3, -0.45, true)), { kind: "tile", side: 1 });
    assert.deepEqual(plain(Layout.dropZone(0, -0.4, true)), { kind: "beside", side: -1 });
    assert.deepEqual(plain(Layout.dropZone(0.2, 0.35, true)), { kind: "beside", side: 1 });
    assert.deepEqual(plain(Layout.dropZone(0.1, 0.1, true)), { kind: "stack", side: 1 });
    // a column that isn't stacked: its halves
    assert.deepEqual(plain(Layout.dropZone(0.1, -0.1, false)), { kind: "beside", side: -1 });
    assert.deepEqual(plain(Layout.dropZone(0.1, 0.1, false)), { kind: "beside", side: 1 });
    // the boundaries belong to the inner zone
    assert.deepEqual(plain(Layout.dropZone(0.25, 0, true)), { kind: "stack", side: 1 });
    assert.deepEqual(plain(Layout.dropZone(0, 0.3, true)), { kind: "stack", side: 1 });
});

test("scrollSteps counts the columns between the view and the target", () => {
    const lefts = [0, 500, 1000, 1500];
    assert.equal(Layout.scrollSteps(lefts, 20, 990), 2);
    assert.equal(Layout.scrollSteps(lefts, 1480, 510), -2);
    assert.equal(Layout.scrollSteps(lefts, 700, 600), 0);
});

test("placeAtEnd puts a column after the others and as tall, or in the middle of an empty desktop", () => {
    const area = rect(0, 0, 1920, 1080);
    assert.deepEqual(plain(Layout.placeAtEnd([], area, 800, 10)), { x: 560, y: 0, height: 1080 });
    assert.deepEqual(plain(Layout.placeAtEnd([rect(6, 6, 800, 520), rect(6, 536, 800, 538), rect(816, 6, 900, 1068)], area, 600, 10)),
        { x: 1726, y: 6, height: 1068 });
});

test("computeColumns keeps a floating window of the same width over a column out of it", () => {
    const columns = Layout.computeColumns([
        { window: "a", geometry: rect(0, 6, 1000, 700) },
        { window: "b", geometry: rect(0, 716, 1000, 700) },
        // floating, a bit to the side, over both
        { window: "floating", geometry: rect(150, 300, 1000, 540) },
        // floating, lined up with the column, but over it much more than a stacked column offsets its windows
        { window: "aligned", geometry: rect(2, 400, 1000, 540) },
    ]);
    assert.deepEqual(plain(columns.find(column => column.windows.includes("a")).windows), ["a", "b"]);
    assert.equal(columns.length, 3);
});
