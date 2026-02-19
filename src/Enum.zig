const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const heap = std.heap;
const mem = std.mem;

const arg = @import("./argument.zig");
const Arg = arg.Argument;

const Self = @This();

/// Creates an `Enum` `Argument` and sets values for methods. It also
/// verifies that the number of variants in `Arg(Type).values` is at
/// least that of `Type`. This may prevent ommiting variants.
pub fn default(comptime Type: type, argument: Arg(Type).Default) !Arg(Type) {
    arg.verify(Type, argument.title, argument.values);

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
    for (self.values) |val| {
        var match = mem.eql(u8, val.string, value);

        match = match or val.short_string.len > 0 and mem.eql(
            u8,
            val.short_string,
            value,
        );

        if (match) return val.parsed;
    } else return error.InvalidValue;
}

pub fn formatValue(
    comptime Type: type,
    self: *const Arg(Type),
    allocator: mem.Allocator,
) ![]const u8 {
    _ = self;
    return try allocator.dupe(u8, "enum");
}

test Self {
    const allocator = testing.allocator;

    const En = enum { first, second };
    const EnArg = Arg(En);

    const first = EnArg.Values{
        .string = "--first",
        .short_string = "-f",
        .parsed = .first,
        .description = "First value.",
    };

    const second = EnArg.Values{
        .string = "--second",
        .parsed = .second,
        .description = "Second value.",
    };

    const en = try default(En, .{
        .title = "enum",
        .values = &.{ first, second },
        .positional = true,
    });

    try testing.expectEqual(.first, try en.parse("--first"));
    try testing.expectEqual(.first, try en.parse("-f"));
    try testing.expectEqual(.second, try en.parse("--second"));
    try testing.expectError(error.InvalidValue, en.parse("wrong"));

    const en3 = try default(En, .{
        .title = "en",
        .values = &.{ first, second },
    });

    const inline_en = try en.formatValue(allocator);
    defer allocator.free(inline_en);
    try testing.expectEqualStrings("<enum>", inline_en);

    const inline_en3 = try en3.formatValue(allocator);
    defer allocator.free(inline_en3);
    try testing.expectEqualStrings("<en=enum>", inline_en3);

    const en4 = try default(En, .{
        .title = "en",
        .values = &.{ first, second },
        .optional = true,
    });

    const inline_en4 = try en4.formatValue(allocator);
    defer allocator.free(inline_en4);
    try testing.expectEqualStrings("[en=enum]", inline_en4);

    const block_en = try en.formatBlock(allocator);
    defer allocator.free(block_en);

    const expected_block_en =
        \\Enum:
        \\
        \\-f, --first    First value.
        \\--second       Second value.
        \\
    ;

    try testing.expectEqualStrings(expected_block_en, block_en);
}
