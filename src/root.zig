const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const heap = std.heap;
const mem = std.mem;

pub const Argument = @import("argument.zig");
pub const Enum = @import("Enum.zig");
pub const String = @import("String.zig");

test {
    _ = @import("argument.zig");
    _ = @import("Enum.zig");
    _ = @import("String.zig");
}
