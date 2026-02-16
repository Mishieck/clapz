const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const heap = std.heap;
const mem = std.mem;

pub fn Argument(comptime Type: type) type {
    return struct {
        const Arg = Argument(Type);
        pub const Name = []const u8;
        pub const Description = []const u8;
        pub const Value = []const u8;

        pub const Parse = fn (
            comptime Type: type,
            self: *const Arg,
            iterator: *ValueIterator,
        ) anyerror!Type;

        pub const Format = fn (
            comptime Type: type,
            self: *const Arg,
            allocator: mem.Allocator,
        ) anyerror![]const u8;

        name: Name,
        description: Description = "",
        values: ValuesSlice,
        optional: bool,
        positional: bool,
        value_formatter: *const Format,
        parser: *const Parse,

        pub fn parse(self: *const Arg, iterator: *ValueIterator) !Type {
            return self.parser(Type, self, iterator);
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
            if (self.positional) {
                return try allocator.dupe(u8, value);
            } else return try mem.concat(
                allocator,
                u8,
                &.{ self.name, "=", value },
            );
        }

        /// Formats an argument as a block of documentation. Caller owns the
        /// memory.
        pub fn formatBlock(self: *const Arg, gpa: mem.Allocator) ![]const u8 {
            var rows = std.ArrayList([2][]const u8){};
            defer {
                for (rows.items) |row| for (row) |item| gpa.free(item);
                rows.clearAndFree(gpa);
            }

            const heading = try self.formatHeading(gpa);
            defer gpa.free(heading);

            var max_left_col_size = heading.len;

            var docs = std.ArrayList(u8){};
            defer docs.clearAndFree(gpa);
            try docs.appendSlice(gpa, heading);

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

        /// Formats the heading of the documentation.
        pub fn formatHeading(
            self: *const Arg,
            gpa: mem.Allocator,
        ) ![]const u8 {
            const capitalized = try if (self.name.len > 0) mem.concat(
                gpa,
                u8,
                &.{ &.{std.ascii.toUpper(self.name[0])}, self.name[1..] },
            ) else gpa.dupe(u8, "");
            defer gpa.free(capitalized);

            return try mem.concat(gpa, u8, &.{ capitalized, ":\n\n" });
        }

        /// Iterates through command-line arguments. This is used by argument
        /// parsers. After a value has been read by a parser, it is saved in
        /// `ValueIterator.current`. This is done to allow persistent access to
        /// the value just in case the parser is an optional parser.
        ///
        /// Optional parsers may succeed on invalid input. This means that if
        /// the iterator does not save the value somewhere, the next parser will
        /// read the wrong value. When a parser has accepted a value, it must
        /// call `accept` to release the value. If a value is not released, the
        /// next parser will read a value that has already been used by the
        /// previous parser.
        pub const ValueIterator = struct {
            data: []const Value,
            current: ?Value = null,

            pub fn next(self: *ValueIterator) ?Value {
                return if (self.current) |value| current: {
                    break :current value;
                } else if (self.data.len > 0) has_data: {
                    const value = self.data[0];
                    self.data = self.data[1..];
                    self.current = value;
                    break :has_data value;
                } else null;
            }

            pub fn accept(self: *ValueIterator) void {
                self.current = null;
            }
        };

        pub const ValuesSlice = []const Values;

        pub const Values = struct {
            pub const String = []const u8;

            string: String,
            short_string: String = "",
            parsed: Type,
            description: Description = "",
        };

        /// A partial of `Argument`. The struct excludes methods and makes
        /// `optional` and `positional` optional.
        pub const Default = struct {
            name: Arg.Name,
            description: Arg.Description = "",
            values: Arg.ValuesSlice,
            optional: ?bool = null,
            positional: ?bool = null,
        };
    };
}
