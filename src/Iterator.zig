//! Iterates through command-line arguments. This is used by argument parsers.
//! The iterator only advances when the value it returns is accepted by a
//! parser. This is done to handle optional arguments. If a parser of an
//! optional argument finds that the value is invalid, the next parser has to
//! start from the current value. So, the iterator stays at the same index until
//! the parsing is successful.

const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const heap = std.heap;
const mem = std.mem;
const process = std.process;

const arg = @import("./argument.zig");
const Arg = arg.Argument;

const Self = @This();

gpa: mem.Allocator,
strings: []const [:0]u8,
string_iterator: arg.Iterator,
index: usize = 0,

/// Creates an iterator of arguments. Call `deinit` to free memory of process
/// arguments.
pub inline fn init(gpa: mem.Allocator) !Self {
    const strings = try process.argsAlloc(gpa);
    return .{
        .gpa = gpa,
        .strings = strings,
        .string_iterator = .{ .strings = strings },
    };
}

/// Frees process arguments memory.
pub inline fn deinit(self: *Self) void {
    process.argsFree(self.gpa, self.strings);
}

pub fn next(
    self: *Self,
    comptime Type: type,
    comptime argument: Arg(Type),
) !argument.Infer() {
    return argument.parse(self.gpa, &self.string_iterator);
}

test {
    const allocator = testing.allocator;
    const args = .{ "./src/Iterator.zig", "run", "./src/main.ext" };

    var strings: [3][:0]u8 = undefined;

    inline for (args, 0..) |str, i| {
        var buffer: [128]u8 = undefined;
        for (str, 0..) |char, j| buffer[j] = char;
        buffer[str.len] = 0;
        strings[i] = buffer[0..str.len :0];
    }

    var it = Self{
        .gpa = allocator,
        .strings = &strings,
        .string_iterator = .{ .strings = &strings },
    };

    const Command = Arg([]const u8);

    const command = Command{
        .name = .{ "tool", "" },
        .description = "",
        .syntax = .{ .one = .{ .positional = .string } },
        .value_descriptions = &.{},
        .examples = &.{},
    };

    const SubCommand = enum { build, run, @"test" };
    const SubCommandArg = Arg(SubCommand);

    const sub_command = SubCommandArg{
        .name = .{ "sub-command", "" },
        .description = "",
        .syntax = .{ .one = .{ .positional = .variant } },
        .value_descriptions = &.{
            .{ "run", "Run a source file." },
            .{ "test", "Run a tests." },
            .{ "build", "Build source files." },
        },
        .examples = &.{},
    };

    const Path = Arg([]const u8);

    const path = Path{
        .name = .{ "path", "" },
        .description = "The path of the source file to run.",
        .syntax = .{ .zero_or_more = .{ .positional = .string } },
        .value_descriptions = &.{},
        .examples = &.{},
    };

    const exe_path = try it.next(Command.Parsed, command);
    defer allocator.destroy(exe_path);
    try testing.expectEqualStrings("./src/Iterator.zig", exe_path.*);

    const sub_command_variant = try it.next(SubCommandArg.Parsed, sub_command);
    defer allocator.destroy(sub_command_variant);
    try testing.expectEqual(.run, sub_command_variant.*);

    var path_value = try it.next(Path.Parsed, path);
    defer path_value.clearAndFree();
    try testing.expectEqual(1, path_value.items.len);
    try testing.expectEqualStrings("./src/main.ext", path_value.items[0]);
}
