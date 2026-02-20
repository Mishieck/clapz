//! Iterates through command-line arguments. This is used by argument
//! parsers. After a value has been read by a parser, it is saved in
//! `ValueIterator.current`. This is done to allow persistent access to
//! the value just in case the parser is an optional parser.
//!
//! Optional parsers may succeed on invalid input. This means that if
//! the iterator does not save the value somewhere, the next parser will
//! read the wrong value. When a parser has accepted a value, it must
//! call `accept` to release the value. If a value is not released, the
//! next parser will read a value that has already been used by the
//! previous parser.

const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const heap = std.heap;
const mem = std.mem;
const process = std.process;

const arg = @import("./argument.zig");
const Arg = arg.Argument;
const String = @import("./String.zig");
const Enum = @import("./Enum.zig");

const Self = @This();

strings: []const [:0]u8,
index: usize = 0,

/// Creates an iterator of arguments. Call `deinit` to free memory of process
/// arguments.
pub fn init(gpa: mem.Allocator) !Self {
    const strings = try process.argsAlloc(gpa);
    return .{ .strings = strings };
}

/// Frees process arguments memory.
pub fn deinit(self: *Self, gpa: mem.Allocator) void {
    process.argsFree(gpa, self.strings);
}

pub fn next(self: *Self, comptime Type: type, argument: Arg(Type)) !if (argument.optional) ?Type else Type {
    const is_within_bounds = self.index < self.strings.len;
    const string = if (is_within_bounds) self.strings[self.index] else null;

    if (string) |value| {
        const result = argument.parse(value);

        if (result) |val| {
            self.index += 1;
            return val;
        } else |err| {
            if (argument.optional) {
                if (err == error.InvalidValue) return null;
            }

            return err;
        }
    } else if (argument.optional) {
        return null;
    } else return error.MissingValue;
}

test {
    var it = Self{
        .strings = &.{ "./src/Iterator.zig", "run", "./src/main.ext" },
    };

    const command = try String.default(.{
        .title = "tool",
        .values = &.{.{
            .string = "tool",
            .parsed = "",
            .description = "The command for running tool.",
        }},
        .positional = true,
    });

    const SubCommand = enum {
        run,
        @"test",
        build,
    };

    const sub_command = try Enum.default(
        SubCommand,
        .{
            .title = "sub-command",
            .values = &.{
                .{
                    .string = "run",
                    .parsed = .run,
                    .description = "Run a source file.",
                },
                .{
                    .string = "test",
                    .parsed = .@"test",
                    .description = "Run a tests.",
                },
                .{
                    .string = "build",
                    .parsed = .build,
                    .description = "Build source files.",
                },
            },
            .positional = true,
        },
    );

    const path = try String.default(.{
        .title = "path",
        .values = &.{.{
            .string = "path",
            .parsed = "",
            .description = "The path of the source file to run.",
        }},
        .optional = true,
        .positional = true,
    });

    const exe_path = try it.next(String.Value, command);
    try testing.expectStringEndsWith("./src/Iterator.zig", exe_path);

    const sub_command_variant = try it.next(SubCommand, sub_command);
    try testing.expectEqual(.run, sub_command_variant);

    const path_value = try it.next(String.Value, path);
    try testing.expect(path_value != null);
    try testing.expectEqual("./src/main.ext", path_value.?);
}
