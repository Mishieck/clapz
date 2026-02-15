const std = @import("std");
const zarg = @import("zarg");

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}
