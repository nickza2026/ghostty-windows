//! Compare cell data before fonts/rendering. Call with the actual mutex held.
const std = @import("std");
const global = @import("../../global.zig");
const Terminal = @import("../../terminal/main.zig").Terminal;
const fixture = @import("thai_tui_fixture.zig");

pub fn compare(actual: *Terminal, alloc: std.mem.Allocator, require_unicode_match: bool) !void {
    var unicode_match = false;
    for ([_]bool{ false, true }) |grapheme_default| {
        var reference = try Terminal.init(global.io(), alloc, .{
            .cols = actual.cols,
            .rows = actual.rows,
            .default_modes = .{ .grapheme_cluster = grapheme_default },
        });
        defer reference.deinit(alloc);
        var stream = reference.vtStream();
        defer stream.deinit();
        stream.nextSlice(fixture.output);
        var differences: usize = 0;
        for (0..@min(actual.rows, 20)) |y| for (0..actual.cols) |x| {
            const got = actual.screens.active.pages.getCell(.{ .viewport = .{ .x = @intCast(x), .y = @intCast(y) } }).?;
            const want = reference.screens.active.pages.getCell(.{ .viewport = .{ .x = @intCast(x), .y = @intCast(y) } }).?;
            const got_cp = got.cell.codepoint();
            const want_cp = want.cell.codepoint();
            const got_g = got.node.page().lookupGrapheme(got.cell) orelse &.{};
            const want_g = want.node.page().lookupGrapheme(want.cell) orelse &.{};
            if ((if (got_cp == 0) @as(u21, 32) else got_cp) != (if (want_cp == 0) @as(u21, 32) else want_cp) or !std.mem.eql(u21, got_g, want_g)) {
                if (differences < 8) std.log.info("Thai model diff default_gc={} row={} col={} expected_cp={x} got_cp={x} expected_marks={any} got_marks={any}", .{ grapheme_default, y, x, want_cp, got_cp, want_g, got_g });
                differences += 1;
            }
        };
        const rc = reference.screens.active.cursor;
        const ac = actual.screens.active.cursor;
        std.log.info("Thai model comparison direct_default_gc={} different_cells={} expected_cursor=({},{}) got_cursor=({},{}) actual_gc={}", .{ grapheme_default, differences, rc.x, rc.y, ac.x, ac.y, actual.modes.get(.grapheme_cluster) });
        if (grapheme_default) unicode_match = differences == 0 and rc.x == ac.x and rc.y == ac.y;
    }
    if (require_unicode_match) {
        if (!unicode_match) return error.ConptyUnicodeModelMismatch;
        std.log.info("controlled ConPTY Thai paced redraw matched direct VT cells+graphemes+cursor; strict regression", .{});
    }
}
