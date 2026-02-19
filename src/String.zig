const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const heap = std.heap;
const mem = std.mem;

const arg = @import("./argument.zig");
const Arg = arg.Argument;

const Self = @This();
pub const Value = []const u8;

/// Creates an string `Argument` and sets values for methods.
pub fn default(argument: Arg(Value).Default) !Arg(Value) {
    arg.verify(Value, argument.title, argument.values);

    return .{
        .title = argument.title,
        .values = argument.values,
        .optional = argument.optional orelse false,
        .positional = argument.positional orelse false,
        .parser = parse,
        .value_formatter = formatValue,
    };
}

pub fn parse(
    comptime Type: type,
    self: *const Arg(Type),
    value: arg.Value,
) anyerror!Type {
    _ = self;
    return value;
}

pub fn formatValue(
    comptime Type: type,
    self: *const Arg(Type),
    allocator: mem.Allocator,
) ![]const u8 {
    _ = self;
    return allocator.dupe(u8, "string");
}

test Self {
    const allocator = testing.allocator;

    const str = try default(.{
        .title = "command",
        .values = &.{.{
            .string = "--value",
            .short_string = "-v",
            .parsed = "",
        }},
        .positional = true,
    });

    try testing.expectEqual("value", try str.parse("value"));

    const inline_str = try str.formatValue(allocator);
    defer allocator.free(inline_str);
    try testing.expectEqualStrings("<command>", inline_str);
}
