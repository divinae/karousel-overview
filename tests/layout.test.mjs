import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

// layout.js is a QML JavaScript library, load it without the .pragma line
const source = readFileSync(new URL("../package/contents/ui/layout.js", import.meta.url), "utf8")
    .replace(/^\.pragma library$/m, "");
const Layout = {};
vm.runInNewContext(source + "\nObject.assign(exports, { KarouselShortcuts, clamp, stripBounds, computeColumns, reorderTarget, insertHintX, stackMoves, minimizedSlots, snapTarget, zoomScale, zoomOffset, wheelStep, edgeScrollSpeed, emptyDesktops, innerGaps });", { exports: Layout });

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
