const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const heap = std.heap;
const mem = std.mem;
const array_list = std.array_list;

pub const Title = []const u8;
pub const Description = []const u8;
pub const Value = []const u8;

/// Creates a type of an argument that can parse command-line arguemnts into
/// `Type`. The argument can also document itself.
pub fn Argument(comptime Type: type) type {
    return struct {
        const Self = Argument(Type);

        pub const ValueDescriptions = []const struct { []const u8, []const u8 };
        pub const Parsed = Type;

        name: Name,
        syntax: Syntax,
        description: []const u8,
        value_descriptions: ValueDescriptions,
        examples: Examples,

        pub const default = Self{
            .name = "",
            .syntax = .default,
            .description = "",
            .value_descriptions = &.{},
            .examples = &.{},
        };

        pub fn parse(comptime self: Self, gpa: mem.Allocator, it: *Iterator) !self.syntax.Infer(Type) {
            return try self.syntax.parse(Type, gpa, self.name, it);
        }

        pub fn toSyntaxString(comptime self: Self) []const u8 {
            return self.syntax.toString(self.name);
        }

        /// Formats an argument as a block of documentation. Caller owns the
        /// memory.
        pub fn toString(self: Self, gpa: mem.Allocator) ![]const u8 {
            const heading = try formatHeading(gpa, self.name.@"0");
            defer gpa.free(heading);

            var max_left_col_size: usize = 0;

            var docs = std.ArrayList(u8){};
            defer docs.clearAndFree(gpa);
            try docs.appendSlice(gpa, heading);
            try docs.appendSlice(gpa, ":\n\n");

            var string = std.ArrayList(u8){};
            defer string.clearAndFree(gpa);

            var values = self.value_descriptions;
            var first_column: []const u8 = "";
            defer if (first_column.len > 0) gpa.free(first_column);

            if (self.value_descriptions.len == 0) {
                const prefix = try if (self.name.@"1".len == 0) gpa.dupe(u8, "") else mem.concat(
                    gpa,
                    u8,
                    &.{ self.name.@"1", ", " },
                );
                defer gpa.free(prefix);

                first_column = try mem.concat(gpa, u8, &.{ prefix, self.name.@"0" });
                values = &.{.{ first_column, self.description }};
            }

            for (values) |value| {
                const first_col, _ = value;
                if (first_col.len > max_left_col_size) max_left_col_size = first_col.len;
            }

            for (values) |row| {
                const gap: usize = 4;
                try docs.appendSlice(gpa, row[0]);

                for (0..(max_left_col_size - row[0].len + gap)) |_| {
                    try docs.append(gpa, ' ');
                }

                try docs.appendSlice(gpa, row[1]);
                try docs.append(gpa, '\n');
            }

            return try gpa.dupe(u8, docs.items);
        }

        pub inline fn Infer(comptime self: Self) type {
            return self.syntax.Infer(Type);
        }
    };
}

/// Iterator of string values of command-line arguments.
pub const Iterator = struct {
    strings: []const [:0]const u8,
    index: usize = 0,

    fn next(self: *Iterator) ?[:0]const u8 {
        const is_within_bounds = self.index < self.strings.len;
        return if (is_within_bounds) self.strings[self.index] else null;
    }

    fn accept(self: *Iterator) void {
        self.index += 1;
    }
};

/// The name of the argument. The first value is the long name and the short value
/// is the short name. For example, `.{ "--help", "-h" }`.
pub const Name = struct { []const u8, []const u8 };

/// Examples of values of the command-line argument.
pub const Examples = []const []const u8;

test Argument {
    const allocator = testing.allocator;

    const Literal = Argument([]const u8);

    const literal = Literal{
        .name = .{ "tool", "" },
        .syntax = .literal,
        .description = "A CLI tool.",
        .value_descriptions = &.{},
        .examples = &.{},
    };

    var it = Iterator{ .strings = &.{ "tool", "wrong" } };
    const literal_value = try literal.parse(allocator, &it);
    defer allocator.destroy(literal_value);
    try testing.expectEqualStrings("tool", literal_value.*);

    const String = Argument([]const u8);

    const string = String{
        .name = .{ "path", "" },
        .syntax = .{ .one = .{ .positional = .string } },
        .description = "A path of a file.",
        .value_descriptions = &.{},
        .examples = &.{},
    };

    it = Iterator{ .strings = &.{"./path/to/file"} };
    const string_value = try string.parse(allocator, &it);
    defer allocator.destroy(string_value);
    try testing.expectEqualStrings("./path/to/file", string_value.*);

    const SubCommand = enum {
        build,
        run,
        @"test",
    };

    const Enum = Argument(SubCommand);

    const en = Enum{
        .name = .{ "sub-command", "" },
        .syntax = .{ .one = .{ .positional = .variant } },
        .description = "A sub-command.",
        .value_descriptions = &.{},
        .examples = &.{},
    };

    it = Iterator{ .strings = &.{"run"} };
    const enum_value = try en.parse(allocator, &it);
    defer allocator.destroy(enum_value);
    try testing.expectEqual(.run, enum_value.*);

    try testing.expectEqualStrings("<sub-command>", en.toSyntaxString());

    const docs = try en.toString(allocator);
    defer allocator.free(docs);

    const expected_docs =
        \\Sub Command:
        \\
        \\sub-command    A sub-command.
        \\
    ;

    try testing.expectEqualStrings(expected_docs, docs);
}

/// The syntax of a command-line argument.
pub const Syntax = union(enum) {
    const Self = @This();

    pub const Range = struct { usize, usize };
    pub const RangeUpperLimit = 1024;
    pub const default = Self{ .one = .default };

    /// The value matches the name exactly. This can match both the long name
    /// and short name.
    literal: void,

    /// Optional argument.
    zero_or_one: Structure,

    /// A sequence of arguments which may be empty.
    zero_or_more: Structure,

    /// Exactly 1 argument.
    one: Structure,

    /// A sequence of arguemnts with at lease 1 arguement.
    one_or_more: Structure,

    /// Converts the syntax of the argument to a string representation. This is
    /// used in usage instructions.
    pub inline fn toString(comptime self: Self, comptime name: Name) []const u8 {
        return switch (self) {
            .literal => Structure.formatName(name),
            .zero_or_one => |value| "[" ++ value.toString(name) ++ "]",
            .zero_or_more => |value| "[" ++ value.toString(name) ++ "...]",
            .one => |value| "<" ++ value.toString(name) ++ ">",
            .one_or_more => |value| "<" ++ value.toString(name) ++ "...>",
        };
    }

    /// Gets the range of count of values using the syntax.
    pub inline fn toRange(comptime self: Self) Range {
        return switch (self) {
            .literal => |_| .{ 1, 1 },
            .zero_or_one => |_| .{ 0, 1 },
            .zero_or_more => |_| .{ 0, RangeUpperLimit },
            .one => |_| .{ 1, 1 },
            .one_or_more => |_| .{ 1, RangeUpperLimit },
        };
    }

    /// Parses a string of a command-line argument into its type.
    pub fn parse(
        comptime self: Self,
        comptime Type: type,
        gpa: mem.Allocator,
        comptime name: Name,
        it: *Iterator,
    ) !self.Infer(Type) {
        const lower, const upper = self.toRange();
        var i: usize = 0;
        var values = array_list.Managed(Type).init(gpa);
        // defer values.clearAndFree();

        const structure = switch (self) {
            .literal => return if (it.next()) |v| switch (mem.eql(u8, name.@"0", v) or mem.eql(u8, name.@"1", v)) {
                true => lit: {
                    it.accept();
                    break :lit try createValue(Type, gpa, &values, v);
                },
                false => error.InvalidValue,
            } else error.NotEnoughValues,
            else => |s| switch (s) {
                .zero_or_one => |v| v,
                .zero_or_more => |v| v,
                .one => |v| v,
                .one_or_more => |v| v,
                else => unreachable,
            },
        };

        // Get required number of values.
        while (i < lower) : (i += 1) {
            const value = it.next() orelse return error.NotEnoughValues;
            try values.append(try structure.parse(Type, name, value));
            it.accept();
        }

        // Get optional additional values.
        while (i < upper) : (i += 1) {
            const value = it.next() orelse break;
            try values.append(structure.parse(Type, name, value) catch break);
            it.accept();
        }

        return switch (self) {
            .zero_or_one => if (values.getLastOrNull()) |v| try createValue(Type, gpa, &values, v) else null,
            .zero_or_more => values,
            .literal, .one => try createValue(Type, gpa, &values, values.getLast()),
            .one_or_more => if (values.items.len > 0) values else error.NotEnoughValues,
        };
    }

    /// Creates a value for `literal`, `.one`, and `zero_or_one`.
    pub inline fn createValue(
        comptime Type: type,
        gpa: mem.Allocator,
        list: *array_list.Managed(Type),
        value: Type,
    ) !*Type {
        defer list.clearAndFree();
        const val = try gpa.create(Type);
        val.* = value;
        return val;
    }

    /// Infers the type of the argument using the syntax.
    pub inline fn Infer(comptime self: Self, comptime Type: type) type {
        return switch (self) {
            .literal => *Type,
            .zero_or_one => |_| ?*Type,
            .one => |_| *Type,
            else => |_| array_list.Managed(Type),
        };
    }
};

test Syntax {
    const allocator = testing.allocator;

    const tool: Syntax = .literal;
    const tool_name = Name{ "tool", "" };

    var it = Iterator{ .strings = &.{ "tool", "wrong" } };
    const tool_value = try tool.parse([]const u8, allocator, tool_name, &it);
    defer allocator.destroy(tool_value);
    try testing.expectEqualStrings("tool", tool_value.*);
    try testing.expectError(
        error.InvalidValue,
        tool.parse([]const u8, allocator, tool_name, &it),
    );

    try testing.expectEqualStrings("tool", tool.toString(.{ "tool", "" }));

    const path = Syntax{ .zero_or_more = .{ .positional = .string } };
    const path_name = Name{ "path", "" };

    it = Iterator{ .strings = &.{} };
    var path_value = try path.parse([]const u8, allocator, path_name, &it);
    try testing.expectEqualSlices([]const u8, &.{}, path_value.items);
    it = Iterator{ .strings = &.{"./path/to/file"} };
    path_value.clearAndFree();
    path_value = try path.parse([]const u8, allocator, path_name, &it);
    defer path_value.clearAndFree();
    try testing.expectEqualSlices(
        []const u8,
        &.{"./path/to/file"},
        path_value.items,
    );

    try testing.expectEqualStrings("[path...]", path.toString(.{ "path", "" }));

    const file_extension = Syntax{ .one_or_more = .{ .positional = .string } };
    const file_extension_name = Name{ "file-extension", "" };

    it = Iterator{ .strings = &.{"zig"} };
    var file_extension_value = try file_extension.parse(
        []const u8,
        allocator,
        file_extension_name,
        &it,
    );
    try testing.expectEqualSlices(
        []const u8,
        &.{"zig"},
        file_extension_value.items,
    );
    it = Iterator{ .strings = &.{ "zig", "c" } };
    file_extension_value.clearAndFree();
    file_extension_value = try file_extension.parse(
        []const u8,
        allocator,
        file_extension_name,
        &it,
    );
    defer file_extension_value.clearAndFree();
    try testing.expectEqualSlices(
        []const u8,
        &.{ "zig", "c" },
        file_extension_value.items,
    );

    try testing.expectEqualStrings(
        "<extension...>",
        file_extension.toString(.{ "extension", "" }),
    );

    it = Iterator{ .strings = &.{} };
    const file_extension_result = file_extension.parse(
        []const u8,
        allocator,
        file_extension_name,
        &it,
    );
    try testing.expectError(error.NotEnoughValues, file_extension_result);

    const SubCommand = enum { build, run, @"test" };
    const sub_command = Syntax{ .zero_or_one = .{ .positional = .variant } };
    const sub_command_name = Name{ "sub-command", "" };

    it = Iterator{ .strings = &.{} };
    var sub_command_value = try sub_command.parse(
        SubCommand,
        allocator,
        sub_command_name,
        &it,
    );
    try testing.expectEqual(null, sub_command_value);
    if (sub_command_value) |v| allocator.destroy(v);

    it = Iterator{ .strings = &.{"run"} };
    sub_command_value = try sub_command.parse(
        SubCommand,
        allocator,
        sub_command_name,
        &it,
    );
    defer if (sub_command_value) |v| allocator.destroy(v);
    try testing.expectEqual(.run, sub_command_value.?.*);

    try testing.expectEqualStrings(
        "[sub-command]",
        sub_command.toString(.{ "sub-command", "" }),
    );
}

/// The structure of the argument. This specifies how the user writes the
/// argument. It determines whether the argument is positional or keyed.
pub const Structure = union(enum) {
    const Self = @This();

    pub const default = Self{ .positional = .default };
    pub const Pair = struct { []const u8, []const u8 };

    /// An argument written with a name and a value.
    keyed: ValueType,

    /// An argument witten without a name.
    positional: ValueType,

    /// Creates the string representation of the argument structure.
    pub inline fn toString(comptime self: Self, comptime name: Name) []const u8 {
        return switch (self) {
            .keyed => |vt| formatName(name) ++ "=" ++ vt.toString(),
            .positional => |_| name.@"0",
        };
    }

    /// Formatx the name of the argument depending on whether the short version
    /// of the name is provided or not. If it is provided, both the long and
    /// short strings are included in the format.
    pub inline fn formatName(comptime name: Name) []const u8 {
        return (if (name.@"1".len > 0) name.@"1" ++ "|" else "") ++ name.@"0";
    }

    /// Parses a string value into the expected type.
    pub fn parse(
        comptime self: Self,
        comptime Type: type,
        comptime name: Name,
        value: Value,
    ) !Type {
        return switch (self) {
            .keyed => |vt| keyed: {
                break :keyed if (getPair(value)) |pair| {
                    const nam, const val = pair;

                    const is_valid_name = inline for (name) |n| {
                        if (mem.eql(u8, n, nam)) break true;
                    } else false;

                    break :keyed if (is_valid_name) try vt.parse(
                        Type,
                        val,
                    ) else error.InvalidValue;
                } else |err| err;
            },
            .positional => |vt| try vt.parse(Type, value),
        };
    }

    /// Gets the pair of a name and a value from a keyed command-line argument.
    pub inline fn getPair(string: Value) !Pair {
        var pair = mem.splitScalar(u8, string, '=');
        const name = pair.next() orelse return error.InvalidValue;
        const value = pair.next() orelse return error.InvalidValue;
        return .{ name, value };
    }
};

test Structure {
    const Enum = enum { first, second };
    const positional = Structure{ .positional = ValueType.variant };
    try testing.expectEqualStrings("enum", positional.toString(.{ "enum", "" }));
    try testing.expectEqual(
        .first,
        try positional.parse(Enum, .{ "enum", "" }, "first"),
    );

    const keyed = Structure{ .keyed = ValueType.string };
    const keyed_name = Name{ "--path", "-p" };
    try testing.expectEqualStrings("-p|--path=string", keyed.toString(keyed_name));

    inline for (keyed_name) |n| try testing.expectEqualStrings(
        "value",
        try keyed.parse([]const u8, keyed_name, n ++ "=value"),
    );
}

/// The type that command-line arguments should be parsed into.
pub const ValueType = enum {
    const Self = @This();

    pub const default = Self.string;

    string,
    variant,

    /// Gets the name of the type of an argument.
    pub inline fn toString(self: Self) []const u8 {
        return switch (self) {
            .string => "string",
            .variant => "variant",
        };
    }

    /// Parses a string command-line argument to the expected type.
    pub inline fn parse(comptime self: Self, comptime Type: type, value: Value) !Type {
        return switch (self) {
            .string => value,
            .variant => inline for (@typeInfo(Type).@"enum".fields) |field| {
                if (mem.eql(u8, field.name, value)) break @enumFromInt(field.value);
            } else error.InvalidValue,
        };
    }
};

test ValueType {
    const s = ValueType.string;
    try testing.expectEqualStrings("string", s.toString());
    try testing.expectEqual("value", try s.parse([]const u8, "value"));

    const Enum = enum { first, second };
    const v = ValueType.variant;

    try testing.expectEqualStrings("variant", v.toString());
    try testing.expectEqual(.first, try v.parse(Enum, "first"));
    try testing.expectEqual(error.InvalidValue, v.parse(Enum, "third"));
}

/// Formats the heading of the documentation. The heading is formatted
/// using Title Case.
pub fn formatHeading(
    gpa: mem.Allocator,
    value: []const u8,
) ![]const u8 {
    var title = std.ArrayList([]const u8){};
    defer {
        for (title.items) |word| gpa.free(word);
        title.deinit(gpa);
    }

    var words = mem.splitAny(u8, value, "-_");

    while (words.next()) |word| {
        if (word.len == 0) continue;
        const capitalized = try if (word.len > 0) mem.concat(
            gpa,
            u8,
            &.{ &.{std.ascii.toUpper(word[0])}, word[1..] },
        ) else gpa.dupe(u8, "");

        try title.append(gpa, capitalized);
    }

    const joined = try mem.join(gpa, " ", title.items);

    return joined;
}

test formatHeading {
    const allocator = testing.allocator;

    const kebab = "command-arg";
    var actual = try formatHeading(allocator, kebab);
    try testing.expectEqualStrings("Command Arg", actual);

    const snake = "command_arg";
    allocator.free(actual);
    actual = try formatHeading(allocator, snake);
    try testing.expectEqualStrings("Command Arg", actual);

    const kebab_and_snake = "mixed-command_arg";
    allocator.free(actual);
    actual = try formatHeading(allocator, kebab_and_snake);
    try testing.expectEqualStrings("Mixed Command Arg", actual);

    const prefixed = "--prefixed";
    allocator.free(actual);
    actual = try formatHeading(allocator, prefixed);
    try testing.expectEqualStrings("Prefixed", actual);
    allocator.free(actual);
}
