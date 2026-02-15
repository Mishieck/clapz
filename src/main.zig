const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const heap = std.heap;
const zarg = @import("zarg");

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    while (args.next()) |arg| debug.print("{s}\n", .{arg});
}
