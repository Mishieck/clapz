const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const fs = std.fs;
const array_list = std.array_list;

const arg = @import("./argument.zig");
const Arg = arg.Argument;

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

/// Writes the documenation of command-line arguemnts.
pub fn write(
    comptime data: anytype,
    gpa: mem.Allocator,
    writer: *fs.File.Writer,
) !void {
    try writeUsage(data, gpa, writer);
    try writeArguments(data, gpa, writer);
    try writeExamples(data, writer);
}

/// Writes the usage part of the documentation.
pub fn writeUsage(
    comptime data: anytype,
    gpa: mem.Allocator,
    writer: *fs.File.Writer,
) !void {
    _ = gpa;
    if (data.len == 0) return;
    try writeHeading(writer, "Usage");

    inline for (data) |line| {
        inline for (line, 0..) |a, i| {
            const value = a.toSyntaxString();
            // defer gpa.free(value);
            if (i > 0) _ = try writer.interface.write(separator);
            _ = try writer.interface.write(value);
        }

        _ = try writer.interface.write(delimiter);
        try writer.interface.flush();
    }

    _ = try writer.interface.write("\n\n");
    try writer.interface.flush();
}

/// Writes documents of each unique argument.
pub fn writeArguments(
    comptime data: anytype,
    gpa: mem.Allocator,
    writer: *fs.File.Writer,
) !void {
    if (data.len == 0) return;
    comptime var max_len: usize = 0;
    inline for (data) |line| max_len += line.len;
    var len: usize = 0;

    var docs = array_list.Managed([]const u8).init(gpa);
    defer docs.clearAndFree();

    inline for (data) |line| {
        inline for (line) |a| {
            const doc = try a.toString(gpa);

            const is_duplicate = for (docs.items) |d| {
                if (mem.eql(u8, d, doc)) break true;
            } else false;

            if (is_duplicate) gpa.free(doc) else {
                try docs.append(doc);
                len += 1;
            }
        }
    }

    for (docs.items) |doc| {
        defer gpa.free(doc);
        _ = try writer.interface.write(doc);
        _ = try writer.interface.write("\n");
    }

    _ = try writer.interface.write("\n");
    try writer.interface.flush();
}

/// Writes examples of all the arguemnts. The examples are all possible
/// combinations of argument values given in `Argument(Type).examples`.
pub fn writeExamples(comptime data: anytype, writer: *fs.File.Writer) !void {
    if (data.len == 0) return;
    try writeHeading(writer, "Examples");

    inline for (data) |line| {
        comptime var total_combinations: usize = 1;
        inline for (line) |a| total_combinations *= a.examples.len;

        var examples: [total_combinations][line.len][]const u8 = undefined;

        inline for (line, 0..) |a, i| {
            var j: usize = 0;

            while (j < total_combinations) {
                for (a.examples) |ex| {
                    examples[j][i] = ex;
                    j += 1;
                }
            }
        }

        inline for (examples) |ex| {
            inline for (ex, 0..) |a, i| {
                if (i > 0) _ = try writer.interface.write(separator);
                _ = try writer.interface.write(a);
            }

            _ = try writer.interface.write("\n");
            try writer.interface.flush();
        }
    }
}

/// Writes the heading of a section in the documentation. It converts kebab-case
/// and snake_case to Title Case. All leading `-` are removed.
pub fn writeHeading(writer: *fs.File.Writer, heading: []const u8) !void {
    _ = try writer.interface.write(heading);
    _ = try writer.interface.write(":\n\n");
    try writer.interface.flush();
}

test Self {
    const Command = Arg([]const u8);
    const command = Command{
        .name = .{ "zig", "" },
        .syntax = .literal,
        .description = "The command for running zig.",
        .value_descriptions = &.{},
        .examples = &.{"zig"},
    };

    const SubCommand = enum {
        run,
        @"test",
        build,
    };

    const SubCommandArg = Arg(SubCommand);

    const sub_command = SubCommandArg{
        .name = .{ "sub-command", "" },
        .syntax = .{ .one = .{ .positional = .variant } },
        .description = "",
        .value_descriptions = &.{
            .{ "build", "Build source files." },
            .{ "run", "Run a source file." },
            .{ "test", "Run tests." },
        },
        .examples = &.{ "build", "run", "test" },
    };

    const Path = Arg([]const u8);

    const path = Path{
        .name = .{ "path", "" },
        .syntax = .{ .one = .{ .positional = .string } },
        .description = "The path of the source file to run or test.",
        .value_descriptions = &.{},
        .examples = &.{"./src/main.ext"},
    };

    const Build = Arg([]const u8);

    const build = Build{
        .name = .{ "build", "" },
        .syntax = .literal,
        .description = "Build a project.",
        .value_descriptions = &.{},
        .examples = &.{"build"},
    };

    const Help = Arg([]const u8);

    const help = Help{
        .name = .{ "--help", "-h" },
        .syntax = .literal,
        .description = "Display these instructions.",
        .value_descriptions = &.{},
        .examples = &.{ "--help", "-h" },
    };

    const docs = .{
        &.{ command, help },
        &.{ command, build },
        &.{ command, sub_command, path },
    };

    const usage =
        \\Usage:
        \\
        \\zig -h|--help
        \\zig build
        \\zig <sub-command> <path>
        \\
        \\
        \\
    ;

    try testDocs(docs, writeUsage, usage);

    const arguments =
        \\Zig:
        \\
        \\zig    The command for running zig.
        \\
        \\Help:
        \\
        \\-h, --help    Display these instructions.
        \\
        \\Build:
        \\
        \\build    Build a project.
        \\
        \\Sub Command:
        \\
        \\build    Build source files.
        \\run      Run a source file.
        \\test     Run tests.
        \\
        \\Path:
        \\
        \\path    The path of the source file to run or test.
        \\
        \\
        \\
    ;

    try testDocs(docs, writeArguments, arguments);

    const examples =
        \\Examples:
        \\
        \\zig --help
        \\zig -h
        \\zig build
        \\zig build ./src/main.ext
        \\zig run ./src/main.ext
        \\zig test ./src/main.ext
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
