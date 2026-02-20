const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const heap = std.heap;
const mem = std.mem;

pub const Title = []const u8;
pub const Description = []const u8;
pub const Value = []const u8;

pub fn Argument(comptime Type: type) type {
    return struct {
        const Arg = Argument(Type);

        pub const Parse = fn (
            comptime Type: type,
            self: *const Arg,
            value: Value,
        ) anyerror!Type;

        pub const Format = fn (
            comptime Type: type,
            self: *const Arg,
            allocator: mem.Allocator,
        ) anyerror![]const u8;

        title: Title,
        values: ValuesSlice,
        optional: bool,
        positional: bool,
        value_formatter: *const Format,
        literal: bool = false,
        parser: *const Parse,

        pub fn parse(self: *const Arg, value: Value) !Type {
            return try self.parser(Type, self, value);
        }

        pub fn formatValue(self: *const Arg, gpa: mem.Allocator) ![]const u8 {
            const value = try self.value_formatter(Type, self, gpa);
            defer gpa.free(value);
            const positional = try self.formatPositional(gpa, value);
            defer gpa.free(positional);
            return try self.formatOptional(gpa, positional);
        }

        pub fn formatOptional(
            self: *const Arg,
            allocator: mem.Allocator,
            value: []const u8,
        ) ![]const u8 {
            if (self.literal) return try allocator.dupe(u8, value);
            const enclosure = if (self.optional) "[]" else "<>";

            return try mem.concat(
                allocator,
                u8,
                &.{ &.{enclosure[0]}, value, &.{enclosure[1]} },
            );
        }

        pub fn formatPositional(
            self: *const Arg,
            allocator: mem.Allocator,
            value: []const u8,
        ) ![]const u8 {
            if (self.literal) return allocator.dupe(u8, value);
            if (self.positional) return allocator.dupe(u8, self.title);
            return try mem.concat(allocator, u8, &.{ self.title, "=", value });
        }

        /// Formats an argument as a block of documentation. Caller owns the
        /// memory.
        pub fn formatBlock(self: *const Arg, gpa: mem.Allocator) ![]const u8 {
            var rows = std.ArrayList([2][]const u8){};
            defer {
                for (rows.items) |row| for (row) |item| gpa.free(item);
                rows.clearAndFree(gpa);
            }

            const heading = try formatHeading(gpa, self.title);
            defer gpa.free(heading);

            var max_left_col_size: usize = 0;

            var docs = std.ArrayList(u8){};
            defer docs.clearAndFree(gpa);
            try docs.appendSlice(gpa, heading);
            try docs.appendSlice(gpa, ":\n\n");

            var string = std.ArrayList(u8){};
            defer string.clearAndFree(gpa);

            for (self.values) |value| {
                defer string.clearAndFree(gpa);

                if (value.short_string.len > 0) {
                    try string.appendSlice(gpa, value.short_string);
                    try string.appendSlice(gpa, ", ");
                }

                try string.appendSlice(gpa, value.string);
                const col_size = string.items.len;
                if (col_size > max_left_col_size) max_left_col_size = col_size;
                const left_col = try gpa.dupe(u8, string.items);

                var row = [2][]const u8{ left_col, "" };

                string.clearAndFree(gpa);
                try string.appendSlice(gpa, value.description);
                const right_col = try gpa.dupe(u8, string.items);
                row[1] = right_col;
                try rows.append(gpa, row);
            }

            for (rows.items) |row| {
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
        /// A partial of `Argument`. The struct excludes methods and makes
        /// `optional` and `positional` optional.
        pub const Default = struct {
            title: Title,
            description: Description = "",
            values: Arg.ValuesSlice,
            optional: ?bool = null,
            positional: ?bool = null,
        };

        pub const ValuesSlice = []const Values;

        pub const Values = struct {
            pub const String = []const u8;

            string: String,
            short_string: String = "",
            parsed: Type,
            description: Description = "",
        };
    };
}

pub fn verify(
    comptime Type: type,
    comptime title: Title,
    comptime values: Argument(Type).ValuesSlice,
) void {
    comptime {
        if (title.len == 0) @compileError("Empty title!\n");

        if (values.len == 0) @compileError(
            "Empty values slice in argument '" ++ title ++ "'!\n",
        );
    }
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
    allocator.free(actual);
}
