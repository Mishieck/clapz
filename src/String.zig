const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const heap = std.heap;
const mem = std.mem;

const Arg = @import("./argument.zig").Argument;

const Self = @This();

/// Creates an string `Argument` and sets values for methods.
pub fn default(comptime Type: type, arg: Arg(Type).Default) !Arg(Type) {
    return .{
        .name = arg.name,
        .description = arg.description,
        .values = arg.values,
        .optional = arg.optional orelse false,
        .positional = arg.positional orelse false,
        .parser = parse,
        .value_formatter = formatValue,
    };
}

pub fn parse(
    comptime Type: type,
    self: *const Arg(Type),
    iterator: *Arg(Type).ValueIterator,
) anyerror!Type {
    const it_value = iterator.next();

    if (it_value) |value| {
        iterator.accept();
        return value;
    } else if (self.optional) {
        return error.MissingOptionalArgument;
    } else return error.MissingArgument;
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

    const StringArg = Arg([]const u8);

    var it = StringArg.ValueIterator{ .data = &.{"value"} };

    const str = try default([]const u8, .{
        .name = "",
        .values = &.{},
        .positional = true,
    });

    try testing.expectEqual("value", try str.parse(&it));

    it.data = &.{};
    it.current = null;

    const str2 = try default([]const u8, .{
        .name = "",
        .values = &.{},
        .positional = true,
    });

    try testing.expectError(error.MissingArgument, str2.parse(&it));

    const inline_str = try str.formatValue(allocator);
    defer allocator.free(inline_str);
    try testing.expectEqualStrings("<string>", inline_str);
}
