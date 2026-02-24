# Clapz

A CLI argument parser written in Zig.

## Features

- **Typed**: Parse arguments using user-defined types. The types supported are:
  - Strings: Parsed as an slice of bytes of type `[]const u8`.
  - Enums: Parsed using custom enum types. Each value is matched with one or
    more argument strings.
  - Literals: Parsed exactly as their value. This can be used to match arguments
    like `--help` and `--version`.
- **Granular**: An iterator is used to parse one argument at a time. This way
  you can make the parsing logic as fine-grained as you want.
- **Short Aliases**: Each argument may have a short alias. For example `--help`,
  can have an alias like `-h`, as is usually the case.
- **Named Arguments**: Named arguments are passed using the syntax `name=value`.
  Space-separated named arguments are not supported.
- **Documentation**: The following can be documented:
  - Usage: A summary of usage syntax. This can be multiple lines to show
    variations in the syntax.
  - Arguments: Each argument can be documented with its own section.
  - Examples: A list of examples on how to use the program can be documented.

## Installation

The minimum zig version required is `0.15.1`.

```sh
zig fetch --save git+https://github.com/mishieck/clapz
```

Update `build.zig` with

```zig
const clapz = b.dependency("clapz", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("clapz", clapz.module("clapz"));
```

## Usage

### Import

```zig
const std = @import("std");    
const clapz = @import("clapz");    
```

### Create Argument

```zig
// Where `Type` is the type of the parsed value.    
const ArgType = clapz.argument.Argument(Type);

const arg_type = ArgType{
    .name = .{"long-name", "short-name"}, // For example `.{ "--help", "-h" }`.
    .syntax = .{
        // Set the syntax of the argument.
     },
    .description = "The description of the argument.",

    // Entries of values and their descriptions. This is useful in describing
    // each value of a variant.
    .value_descriptions = &.{},

    // Examples of values that the argument can be set to. For `keyed`
    // arguments, you have give both the key and value in the example. For
    // example, to show an example of an argument with name `--filter`, that
    // has the type of `string`, you can give an example like `--filter=value`. 
    .examples  = &.{},
};
```

### Initialize Iterator

Create an iterator for iterating through the values of the arguments.

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer std.debug.assert(gpa.deinit() == .ok);
const allocator = gpa.allocator();

var args = try Iterator.init(allocator);
defer args.deinit();
```

### Parse Arguments

```zig
// `ArgType.Parsed` is the parsed value type passed an argument to `Argument`
// earlier.
const arg_value = try args.next(ArgType.Parsed, arg_type);
defer allocator.destroy(arg_value); // or `defer arg_value.clearAndFree()`
```

The type of `arg_value` is inferred according to the syntax. The possible Values
of the syntax and corresponding `arg_value` types are:

| Syntax         | Type                           |
|----------------|--------------------------------|
| `literal`      | `*Type`                        |
| `zero_or_more` | `std.array_list.Managed(Type)` |
| `zero_or_one`  | `?*Type`                       |
| `one`          | `*Type`                        |
| `one_or_more`  | `std.array_list.Managed(Type)` |

## Example

### Executable

Put the following code in `./src/main.zig`:

```zig
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

const Tool = Arg([]const u8);
const SubCommandArg = Arg(SubCommand);
const SubCommand = enum { build, @"--help", @"-h", run };
const Path = Arg([]const u8);

// The first argument, the path of the executable.
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
```

### Running the Executable

#### Running a Sub-command

Run `zig build run -- run ./src/main.ext`. The output will be:

```sh
Running ./src/main.ext
```

#### Documentation

Run `zig build run -- --help`. The output will be:

```sh
Usage:

tool -h|--help
tool <sub-command> [path]


Tool:

tool    The command for running tool.

Help:

-h, --help    Display these instructions.

Sub Command:

build    Build source files.
run      Run a source file.

Path:

path    Path of file to build or run.


Examples:

tool --help
tool -h
tool build ./src/main.ext
tool run ./src/main.ext

```

For a complex example, look at [this](./examples/main.zig).
