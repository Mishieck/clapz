const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const heap = std.heap;
const mem = std.mem;
const fs = std.fs;
const process = std.process;

const clapz = @import("clapz");
const arg = clapz.argument;
const Arg = arg.Argument;
const Iterator = clapz.Iterator;
const docs = clapz.documentation;

const Path = Arg([]const u8);
const BuildName = Arg([]const u8);
const Literal = Arg([]const u8);

const Tool = Arg([]const u8);
const tool = Tool{
    .name = .{ "tool", "" },
    .syntax = .{ .one = .{ .positional = .string } },
    .description = "The command for running tool.",
    .value_descriptions = &.{},
    .examples = &.{"tool"},
};

const SubCommandArg = Arg(SubCommand);

const SubCommand = enum {
    build,
    @"--help",
    @"-h",
    run,
    @"test",
    @"--version",
    @"-v",
};

const sub_command = SubCommandArg{
    .name = .{ "sub-command", "" },
    .syntax = .{ .one = .{ .positional = .variant } },
    .description = "A sub-command including help and version.",
    .value_descriptions = &.{},
    .examples = &.{},
};

const Filter = Arg([]const u8);
const filter = Filter{
    .name = .{ "--filter", "-f" },
    .syntax = .{ .zero_or_one = .{ .keyed = .string } },
    .description = "Filter tests by name.",
    .value_descriptions = &.{},
    .examples = &.{ "--filter=documentation", "-f=argument" },
};

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var args = try Iterator.init(allocator);
    defer args.deinit();
    const tool_value = try args.next(Tool.Parsed, tool); // Path of executable.
    defer allocator.destroy(tool_value);

    const sub_command_value = try args.next(SubCommandArg.Parsed, sub_command);
    defer allocator.destroy(sub_command_value);

    var stdout = fs.File.stdout();
    defer stdout.close();
    var buffer: [1024]u8 = undefined;
    var writer = stdout.writer(&buffer);

    try switch (sub_command_value.*) {
        .build => build(allocator, &writer, &args),
        .@"--help", .@"-h" => help(allocator, &writer),
        .run => run(allocator, &writer, &args),
        .@"test" => handleTests(allocator, &writer, &args),
        .@"--version", .@"-v" => displayVersion(allocator, &writer),
    };
}

fn build(gpa: mem.Allocator, writer: *fs.File.Writer, args: *Iterator) !void {
    const name = comptime createBuildName();
    const name_value = try args.next(BuildName.Parsed, name);
    defer if (name_value) |v| gpa.destroy(v);

    _ = try writer.interface.write("Building ");
    if (name_value) |value| {
        _ = try writer.interface.write(value.*);
        _ = try writer.interface.write("\n");
    } else _ = try writer.interface.write("all\n");
    try writer.interface.flush();
}

fn help(gpa: mem.Allocator, writer: *fs.File.Writer) !void {
    const LiteralTool = Arg([]const u8);
    const literal_tool = LiteralTool{
        .name = tool.name,
        .syntax = .literal,
        .description = tool.description,
        .value_descriptions = &.{},
        .examples = tool.examples,
    };

    const help_arg = comptime createLiteral(
        "--help",
        "-h",
        "Display these instructions.",
    );
    const version = comptime createLiteral(
        "--version",
        "-v",
        "Display tool version.",
    );
    const path = comptime createPath(
        "The path of the source file to run or test.",
    );
    const build_arg = comptime createLiteral("build", "", "Build source files.");
    const run_arg = comptime createLiteral("run", "", "Run a source file.");
    const test_arg = comptime createLiteral("test", "", "Run tests.");

    const docs_data = comptime .{
        &.{ literal_tool, help_arg },
        &.{ literal_tool, version },
        &.{ literal_tool, build_arg, path },
        &.{ literal_tool, run_arg, path },
        &.{ literal_tool, test_arg, filter, path },
    };

    try docs.write(docs_data, gpa, writer);
}

inline fn createBuildName() BuildName {
    return .{
        .name = .{ "build-name", "" },
        .syntax = .{ .zero_or_one = .{ .positional = .string } },
        .description = "The name of the build process.",
        .value_descriptions = &.{},
        .examples = &.{"build-name"},
    };
}

fn displayVersion(gpa: mem.Allocator, writer: *fs.File.Writer) !void {
    _ = gpa;
    _ = try writer.interface.write("0.1.0\n");
    try writer.interface.flush();
}

fn run(gpa: mem.Allocator, writer: *fs.File.Writer, args: *Iterator) !void {
    const path = comptime createPath("The path of the source file to run.");
    const path_value = try args.next(Path.Parsed, path);
    defer if (path_value) |v| gpa.destroy(v);
    _ = try writer.interface.write("Running ");
    _ = try writer.interface.write(if (path_value) |v| v.* else "all");
    _ = try writer.interface.write("\n");
    try writer.interface.flush();
}

fn handleTests(
    gpa: mem.Allocator,
    writer: *fs.File.Writer,
    args: *Iterator,
) !void {
    const filter_value = args.next(Filter.Parsed, filter) catch null;
    defer if (filter_value) |v| gpa.destroy(v);
    const filter_string = if (filter_value) |v| v.* else "none";
    const path = comptime createPath("The path of the source file to test.");
    const path_value = try args.next(Path.Parsed, path);
    defer if (path_value) |v| gpa.destroy(v);
    const path_string = if (path_value) |v| v.* else "all";

    _ = try writer.interface.write("Testing ");
    _ = try writer.interface.write(path_string);
    _ = try writer.interface.write(" with filter ");
    _ = try writer.interface.write(filter_string);
    _ = try writer.interface.write("\n");
    try writer.interface.flush();
}

inline fn createLiteral(
    comptime name: []const u8,
    comptime short_name: []const u8,
    comptime description: []const u8,
) Literal {
    return .{
        .name = .{ name, short_name },
        .syntax = .literal,
        .description = description,
        .value_descriptions = &.{},
        .examples = &.{name},
    };
}

fn createPath(description: []const u8) Path {
    return .{
        .name = .{ "path", "" },
        .syntax = .{ .zero_or_one = .{ .positional = .string } },
        .description = description,
        .value_descriptions = &.{},
        .examples = &.{ "./src/main.ext", "./src/utils/process.ext" },
    };
}
