const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const heap = std.heap;
const mem = std.mem;
const fs = std.fs;
const process = std.process;

const arg = @import("./argument.zig");
const Arg = arg.Argument;
pub const Enum = @import("Enum.zig");
pub const String = @import("String.zig");
pub const Literal = @import("Literal.zig");

const Self = @This();

pub const Usage = []const []const anyopaque;
pub const Args = []const anyopaque;
pub const Examples = []const []const u8;

const separator = " ";
const delimiter = "\n";

pub const Data = struct {
    usage: type,
    arguments: type,
    examples: type,
};

pub fn write(
    comptime data: anytype,
    gpa: mem.Allocator,
    writer: *fs.File.Writer,
) !void {
    try writeUsage(data, gpa, writer);
    try writeArguments(data, gpa, writer);
    try writeExamples(data, writer);
}

pub fn writeUsage(
    comptime data: anytype,
    gpa: mem.Allocator,
    writer: *fs.File.Writer,
) !void {
    if (data.usage.len == 0) return;
    try writeHeading(writer, "Usage");

    inline for (data.usage) |line| {
        inline for (line, 0..) |a, i| {
            const value = try a.formatValue(gpa);
            defer gpa.free(value);
            if (i > 0) _ = try writer.interface.write(separator);
            _ = try writer.interface.write(value);
        }

        _ = try writer.interface.write(delimiter);
        try writer.interface.flush();
    }

    _ = try writer.interface.write("\n");
    try writer.interface.flush();
}

pub fn writeArguments(
    comptime data: anytype,
    gpa: mem.Allocator,
    writer: *fs.File.Writer,
) !void {
    if (data.arguments.len == 0) return;

    inline for (data.arguments) |a| {
        const block = try a.formatBlock(gpa);
        defer gpa.free(block);
        _ = try writer.interface.write(block);
        _ = try writer.interface.write("\n");
        try writer.interface.flush();
    }
}

pub fn writeExamples(comptime data: anytype, writer: *fs.File.Writer) !void {
    if (data.examples.len == 0) return;
    try writeHeading(writer, "Examples");

    inline for (data.examples) |example| {
        _ = try writer.interface.write(example);
        _ = try writer.interface.write("\n");
        try writer.interface.flush();
    }
}

pub fn writeHeading(writer: *fs.File.Writer, heading: []const u8) !void {
    _ = try writer.interface.write(heading);
    _ = try writer.interface.write(":\n\n");
    try writer.interface.flush();
}

test Self {
    const command = try Literal.default(.{
        .title = "zig",
        .values = &.{.{
            .string = "zig",
            .parsed = "zig",
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
                    .string = "build",
                    .short_string = "b",
                    .parsed = .build,
                    .description = "Build source files.",
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
            },
            .positional = true,
        },
    );

    const path = try String.default(.{
        .title = "path",
        .values = &.{.{
            .string = "path",
            .parsed = "",
            .description = "The path of the source file to run or test.",
        }},
        .positional = true,
    });

    const docs = .{
        .usage = &.{
            &.{ command, sub_command, path },
        },
        .arguments = &.{ sub_command, path },
        .examples = &.{
            "zig build",
            "zig run ./src/main.zig",
            "zig test ./src/root.zig",
        },
    };

    const usage =
        \\Usage:
        \\
        \\zig <sub-command> <path>
        \\
        \\
    ;

    try testDocs(docs, writeUsage, usage);

    const arguments =
        \\Sub Command:
        \\
        \\b, build    Build source files.
        \\run         Run a source file.
        \\test        Run tests.
        \\
        \\Path:
        \\
        \\path    The path of the source file to run or test.
        \\
        \\
    ;

    try testDocs(docs, writeArguments, arguments);

    const examples =
        \\Examples:
        \\
        \\zig build
        \\zig run ./src/main.zig
        \\zig test ./src/root.zig
        \\
    ;

    try testDocs(docs, testWriteExamples, examples);

    const doc_string = usage ++ arguments ++ examples;
    try testDocs(docs, write, doc_string);
}

fn testWriteExamples(
    comptime data: anytype,
    allocator: mem.Allocator,
    writer: *fs.File.Writer,
) anyerror!void {
    _ = allocator;
    return writeExamples(data, writer);
}

fn testDocs(
    comptime data: anytype,
    writeData: *const fn (
        comptime data: anytype,
        allocator: mem.Allocator,
        writer: *fs.File.Writer,
    ) anyerror!void,
    expected: []const u8,
) !void {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var output_file = try tmp_dir.dir.createFile(
        "output.txt",
        .{ .read = true },
    );
    defer output_file.close();

    var writer_buffer: [1024]u8 = undefined;
    var writer = output_file.writer(&writer_buffer);
    try writeData(data, allocator, &writer);
    var data_writer = std.Io.Writer.Allocating.init(allocator);
    defer data_writer.deinit();

    var reader_buffer: [1024]u8 = undefined;
    var reader = output_file.reader(&reader_buffer);
    _ = try reader.interface.streamRemaining(&data_writer.writer);
    const written = data_writer.written();

    try testing.expectEqualStrings(expected, written);
}
