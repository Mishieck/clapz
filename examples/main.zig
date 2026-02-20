const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const heap = std.heap;
const mem = std.mem;
const fs = std.fs;
const process = std.process;

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
    @"test",
    version,
};

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var args = try Iterator.init(allocator);
    defer args.deinit(allocator);

    const tool = try String.default(.{
        .title = "tool",
        .values = &.{.{
            .string = "tool",
            .parsed = "",
            .description = "The command for running tool.",
        }},
        .positional = true,
    });

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
                .{
                    .string = "test",
                    .parsed = .@"test",
                    .description = "Run tests.",
                },

                .{
                    .string = "--version",
                    .short_string = "-v",
                    .parsed = .version,
                    .description = "Display tool version.",
                },
            },
            .positional = true,
        },
    );

    _ = try args.next(String.Value, tool); // Path of executable.

    const sub_command_value = try args.next(SubCommand, sub_command);
    var stdout = fs.File.stdout();
    defer stdout.close();
    var buffer: [1024]u8 = undefined;
    var writer = stdout.writer(&buffer);

    try switch (sub_command_value) {
        .build => build(allocator, &writer, &args),
        .help => help(allocator, &writer, sub_command),
        .run => run(allocator, &writer, &args),
        .@"test" => handleTests(allocator, &writer, &args),
        .version => displayVersion(allocator, &writer),
    };
}

fn build(gpa: mem.Allocator, writer: *fs.File.Writer, args: *Iterator) !void {
    _ = gpa;

    const name = try createBuildName();
    const name_value = try args.next(String.Value, name);

    _ = try writer.interface.write("Building ");
    if (name_value) |value| {
        _ = try writer.interface.write(value);
        _ = try writer.interface.write("\n");
    } else _ = try writer.interface.write("all\n");
    try writer.interface.flush();
}

fn help(
    gpa: mem.Allocator,
    writer: *fs.File.Writer,
    sub_command: Arg(SubCommand),
) !void {
    const tool = try createLiteral("tool", "tool", "");
    const run_arg = try createLiteral("run", "run", "");
    const test_arg = try createLiteral("test", "test", "");
    const build_arg = try createLiteral("build", "build", "");

    const help_arg = try Literal.default(.{ .title = "help", .values = &.{.{
        .string = "--help",
        .short_string = "-h",
        .parsed = "",
    }}, .positional = true, .description = "Display these instructions." });

    const version = try Literal.default(.{
        .title = "version",
        .values = &.{.{
            .string = "--version",
            .short_string = "-v",
            .parsed = "Display tool version.",
        }},
        .positional = true,
    });

    const build_name = try createBuildName();

    const path = try createPath(
        "path",
        "The path of the source file to run or test.",
    );

    const docs_data = .{
        .usage = &.{
            &.{ tool, build_arg, build_name },
            &.{ tool, run_arg, path },
            &.{ tool, test_arg, path },
            &.{ tool, help_arg },
            &.{ tool, version },
        },
        .arguments = &.{ sub_command, path },
        .examples = &.{
            "tool build",
            "tool build example",
            "tool run ./src/main.ext",
            "tool test ./src/main.ext",
        },
    };

    try docs.write(docs_data, gpa, writer);
}

fn createBuildName() !Arg(String.Value) {
    return try String.default(.{
        .title = "name",
        .values = &.{.{
            .string = "name",
            .parsed = "",
            .description = "The name of the build process.",
        }},
        .optional = true,
        .positional = true,
    });
}

fn displayVersion(gpa: mem.Allocator, writer: *fs.File.Writer) !void {
    _ = gpa;
    _ = try writer.interface.write("0.1.0\n");
    try writer.interface.flush();
}

fn run(gpa: mem.Allocator, writer: *fs.File.Writer, args: *Iterator) !void {
    _ = gpa;

    const path = try createPath(
        "path",
        "The path of the source file to run.",
    );

    const value = try args.next(String.Value, path);
    _ = try writer.interface.write("Running ");
    _ = try writer.interface.write(value);
    _ = try writer.interface.write("\n");
    try writer.interface.flush();
}

fn handleTests(
    gpa: mem.Allocator,
    writer: *fs.File.Writer,
    args: *Iterator,
) !void {
    _ = gpa;

    const path = try createPath(
        "path",
        "The path of the source file to test.",
    );

    const value = try args.next(String.Value, path);
    _ = try writer.interface.write("Testing ");
    _ = try writer.interface.write(value);
    _ = try writer.interface.write("\n");
    try writer.interface.flush();
}

fn createLiteral(
    title: []const u8,
    string: []const u8,
    short_string: []const u8,
) !Arg([]const u8) {
    return try Literal.default(.{
        .title = title,
        .values = &.{.{
            .string = string,
            .short_string = short_string,
            .parsed = string,
        }},
        .positional = true,
    });
}

fn createPath(
    title: []const u8,
    description: []const u8,
) !Arg(String.Value) {
    return try String.default(.{
        .title = title,
        .values = &.{.{
            .string = "path",
            .parsed = "",
            .description = description,
        }},
        .positional = true,
    });
}
