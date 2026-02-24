const std = @import("std");
const debug = std.debug;
const heap = std.heap;
const mem = std.mem;
const fs = std.fs;

const clapz = @import("clapz");
const arg = clapz.argument;
const Arg = arg.Argument;
const Iterator = clapz.Iterator;
const docs = clapz.documentation;

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var args = try Iterator.init(allocator);
    defer args.deinit();

    // Discard the path of this executable.
    const tool_value = try args.next(Tool.Parsed, tool);
    defer allocator.destroy(tool_value);

    const sub_command_value = try args.next(SubCommandArg.Parsed, sub_command);
    defer allocator.destroy(sub_command_value);

    try switch (sub_command_value.*) {
        .build => build(allocator, &args),
        .@"--help", .@"-h" => help(allocator),
        .run => run(allocator, &args),
    };
}

const Tool = Arg([]const u8);
const SubCommandArg = Arg(SubCommand);
const SubCommand = enum { build, @"--help", @"-h", run };
const Path = Arg([]const u8);

// For the first argument, the path of the executable.
const tool = Tool{
    .name = .{ "tool", "" },
    .syntax = .{ .one = .{ .positional = .string } },
    .description = "The command for running tool.",
    .value_descriptions = &.{},
    .examples = &.{"tool"},
};

// The sub-commands of `tool`, including the `--help` argument.
const sub_command = SubCommandArg{
    .name = .{ "sub-command", "" },
    .syntax = .{ .one = .{ .positional = .variant } },
    .description = "A sub-command.",
    .value_descriptions = &.{
        .{ "build", "Build source files." },
        .{ "run", "Run a source file." },
    },
    .examples = &.{ "build", "run" },
};

// Path of file to run a command on.
const path = Path{
    .name = .{ "path", "" },
    .syntax = .{ .zero_or_one = .{ .positional = .string } },
    .description = "Path of file to build or run.",
    .value_descriptions = &.{},
    .examples = &.{"./src/main.ext"},
};

fn build(gpa: mem.Allocator, args: *Iterator) !void {
    const path_value = try args.next(Path.Parsed, path);
    defer if (path_value) |v| gpa.destroy(v);
    debug.print("Building {s}\n", .{if (path_value) |v| v.* else "all"});
}

fn run(gpa: mem.Allocator, args: *Iterator) !void {
    const path_value = try args.next(Path.Parsed, path);
    defer if (path_value) |v| gpa.destroy(v);
    debug.print("Running {s}\n", .{if (path_value) |v| v.* else "main"});
}

fn help(gpa: mem.Allocator) !void {
    const LiteralTool = Arg([]const u8);
    const literal_tool = LiteralTool{
        .name = tool.name,
        .syntax = .literal,
        .description = tool.description,
        .value_descriptions = &.{},
        .examples = tool.examples,
    };

    const Help = Arg([]const u8);
    const help_arg = Help{
        .name = .{ "--help", "-h" },
        .syntax = .literal,
        .description = "Display these instructions.",
        .value_descriptions = &.{},
        .examples = &.{ "--help", "-h" },
    };

    const docs_data = .{
        &.{ literal_tool, help_arg },
        &.{ literal_tool, sub_command, path },
    };

    var stdout = fs.File.stdout();
    defer stdout.close();
    var buffer: [1024]u8 = undefined;
    var writer = stdout.writer(&buffer);

    try docs.write(docs_data, gpa, &writer);
}
