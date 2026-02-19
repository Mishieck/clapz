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

strings: *process.ArgIterator,
current_string: ?[:0]const u8 = null,

pub fn next(self: *Self, comptime Type: type, argument: Arg(Type)) !if (argument.optional) ?Type else Type {
    const string = if (self.current_string) |str| str else current: {
        const value = self.strings.next();
        self.current_string = value;
        break :current value;
    };

    if (string) |value| {
        const result = argument.parse(value);

        if (result) |val| {
            self.current_string = null;
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
    var arg_it = process.args();
    var it = Self{ .strings = &arg_it };

    while (arg_it.next()) |v| debug.print("arg: {s}\n", .{v});

    const command = try String.default(.{
        .title = "zig",
        .values = &.{.{
            .string = "zig",
            .parsed = "",
            .description = "The command for running zig.",
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
        .positional = true,
    });

    const exe_path = try it.next(String.Value, command);
    var buffer: [1024]u8 = undefined;
    const expected_exe_path = try std.fs.selfExePath(&buffer);
    try testing.expectStringEndsWith(expected_exe_path, exe_path[1..]);

    const sub_command_variant = try it.next(SubCommand, sub_command);
    try testing.expectEqual(.run, sub_command_variant);

    const path_value = try it.next(String.Value, path);
    try testing.expectEqual("./src/main.zig", path_value);
}
