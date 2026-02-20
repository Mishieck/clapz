const std = @import("std");
const debug = std.debug;
const heap = std.heap;
const mem = std.mem;
const fs = std.fs;

const clapz = @import("clapz");
const arg = clapz.argument;
const String = clapz.String;
const Enum = clapz.Enum;
const Literal = clapz.Literal;
const Arg = arg.Argument;
const Iterator = clapz.Iterator;
const docs = clapz.documentation;

const SubCommand = enum {
    build,
    help,
    run,
};

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var args = try Iterator.init(allocator);
    defer args.deinit(allocator);

    // For the first argument, the path of the executable.
    const tool = try String.default(.{
        .title = "tool",
        .values = &.{.{
            .string = "tool",
            .parsed = "",
            .description = "The command for running tool.",
        }},
        .positional = true,
    });

    // The sub-commands of `tool`, including the `--help` argument.
    const sub_command = try Enum.default(
        SubCommand,
        .{
            .title = "sub-command",
            .values = &.{
                .{
                    .string = "build",
                    .parsed = .build,
                    .description = "Build source files.",
                },
                .{
                    .string = "--help",
                    .short_string = "-h",
                    .parsed = .help,
                    .description = "Display these instructions.",
                },
                .{
                    .string = "run",
                    .parsed = .run,
                    .description = "Run a source file.",
                },
            },
            .positional = true,
        },
    );

    // Path of file to run a command on.
    const path = try String.default(.{
        .title = "path",
        .values = &.{.{
            .string = "path",
            .parsed = "",
            .description = "Path of file to build or run.",
        }},
        .optional = true,
        .positional = true,
    });

    // Discard the path of this executable.
    _ = try args.next(String.Value, tool);

    const sub_command_value = try args.next(SubCommand, sub_command);

    try switch (sub_command_value) {
        .build => build(allocator, &args, path),
        .help => help(allocator, sub_command, path),
        .run => run(allocator, &args, path),
    };
}

fn build(gpa: mem.Allocator, args: *Iterator, path: Arg(String.Value)) !void {
    _ = gpa;
    const path_value = try args.next(String.Value, path);
    debug.print("Building {s}\n", .{path_value orelse "all"});
}

fn run(gpa: mem.Allocator, args: *Iterator, path: Arg(String.Value)) !void {
    _ = gpa;
    const path_value = try args.next(String.Value, path);
    debug.print("Running {s}\n", .{path_value.?});
}

fn help(gpa: mem.Allocator, sub_command: Arg(SubCommand), path: Arg(String.Value)) !void {
    const tool = try Literal.default(.{
        .title = "tool",
        .values = &.{.{ .string = "tool", .parsed = "" }},
    });

    const help_arg = try Literal.default(.{
        .title = "help",
        .values = &.{.{
            .string = "--help",
            .short_string = "-h",
            .parsed = "",
        }},
    });

    const build_arg = try Literal.default(.{
        .title = "build",
        .values = &.{.{ .string = "build", .parsed = "" }},
    });

    const run_arg = try Literal.default(.{
        .title = "run",
        .values = &.{.{ .string = "run", .parsed = "" }},
    });

    // All of the fields are required
    const docs_data = .{
        // Usage docs. Each slice of arguments will be printed as a line.
        .usage = &.{
            &.{ tool, build_arg, path },
            &.{ tool, run_arg, path },
            &.{ tool, help_arg },
        },

        // Arguments that need to be documented on their own.
        .arguments = &.{ sub_command, path },

        // Examples of usage. This list may be empty.
        .examples = &.{
            "tool build ./src/main.ext",
            "tool build",
            "tool run ./src/main.ext",
            "tool --help",
        },
    };

    var stdout = fs.File.stdout();
    defer stdout.close();
    var buffer: [1024]u8 = undefined;
    var writer = stdout.writer(&buffer);

    try docs.write(docs_data, gpa, &writer);
}
