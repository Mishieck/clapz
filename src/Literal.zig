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
        .positional = true,
        .literal = true,
        .parser = parse,
        .value_formatter = formatValue,
    };
}

pub fn parse(
    comptime Type: type,
    self: *const Arg(Type),
    value: arg.Value,
) anyerror!Type {
    const constant = self.values[0];

    for ([2][]const u8{ constant.string, constant.short_string }) |str| {
        if (mem.eql(u8, str, value)) return str;
    }

    return error.InvalidValue;
}

pub fn formatValue(
    comptime Type: type,
    self: *const Arg(Type),
    allocator: mem.Allocator,
) ![]const u8 {
    const literal = self.values[0];

    const short = try if (literal.short_string.len > 0) mem.concat(
        allocator,
        u8,
        &.{ literal.short_string, "|" },
    ) else allocator.dupe(u8, "");

    defer allocator.free(short);

    return try mem.concat(allocator, u8, &.{ short, literal.string });
}

test Self {
    const allocator = testing.allocator;

    const literal = try default(.{
        .title = "command",
        .values = &.{
            .{ .string = "command", .short_string = "c", .parsed = "command" },
        },
        .positional = true,
    });

    try testing.expectEqual("command", try literal.parse("command"));
    try testing.expectEqual("c", try literal.parse("c"));
    try testing.expectError(error.InvalidValue, literal.parse("b"));

    const inline_const = try literal.formatValue(allocator);
    defer allocator.free(inline_const);
    try testing.expectEqualStrings("c|command", inline_const);
}
