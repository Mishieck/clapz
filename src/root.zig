const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const heap = std.heap;
const mem = std.mem;

pub fn Argument(comptime Type: type) type {
    return struct {
        pub const Name = []const u8;
        pub const Description = []const u8;
        pub const Value = []const u8;

        pub const Parse = fn (
            comptime Type: type,
            self: *const Argument(Type),
            iterator: *ValueIterator,
        ) anyerror!Type;

        pub const Format = fn (
            comptime Type: type,
            self: *const Argument(Type),
            allocator: mem.Allocator,
        ) anyerror![]const u8;

        name: Name,
        description: Description = "",
        values: ValuesSlice,
        optional: bool,
        positional: bool,
        inline_formatter: *const Format,
        block_formatter: *const Format,
        parser: *const Parse,

        pub fn parse(
            self: *const Argument(Type),
            iterator: *ValueIterator,
        ) !Type {
            return self.parser(Type, self, iterator);
        }

        pub fn formatInline(
            self: *const Argument(Type),
            allocator: mem.Allocator,
        ) ![]const u8 {
            return self.inline_formatter(Type, self, allocator);
        }

        pub fn formatBlock(
            self: *const Argument(Type),
            allocator: mem.Allocator,
        ) ![]const u8 {
            return self.block_formatter(Type, self, allocator);
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
    };
}

pub const Enum = struct {
    /// Creates a struct that is a partial of `Argument`. The struct excludes
    /// methods and makes `optional` and `positional` optional.
    pub fn Default(comptime Type: type) type {
        const Arg = Argument(Type);

        return struct {
            name: Arg.Name,
            description: Arg.Description = "",
            values: Arg.ValuesSlice,
            optional: ?bool = null,
            positional: ?bool = null,
        };
    }

    /// Creates an `Enum` `Argument` and sets values for methods. It also
    /// verifies that the number of variants in `Argument(Type).values` is at
    /// least that of `Type`. This may prevent ommiting variants.
    pub fn default(comptime Type: type, arg: Default(Type)) !Argument(Type) {
        comptime if (arg.values.len < @typeInfo(Type).@"enum".fields.len) {
            return error.NotEnoughVariants;
        };

        return .{
            .name = arg.name,
            .description = arg.description,
            .values = arg.values,
            .optional = arg.optional orelse false,
            .positional = arg.positional orelse false,
            .parser = parse,
            .block_formatter = formatDefaultBlock,
            .inline_formatter = formatDefaultInline,
        };
    }

    pub fn parse(
        comptime Type: type,
        self: *const Argument(Type),
        iterator: *Argument(Type).ValueIterator,
    ) anyerror!Type {
        const it_value = iterator.next();

        if (it_value) |value| {
            for (self.values) |val| {
                var match = mem.eql(u8, val.string, value);

                match = match or val.short_string.len > 0 and mem.eql(
                    u8,
                    val.short_string,
                    value,
                );

                if (match) {
                    iterator.accept();
                    return val.parsed;
                }
            }
        }

        return if (self.optional)
            error.MissingOptionalArgument
        else
            error.InvalidVariant;
    }
};

pub fn formatDefaultInline(
    comptime Type: type,
    self: *const Argument(Type),
    allocator: mem.Allocator,
) ![]const u8 {
    _ = self;
    return allocator.dupe(u8, "");
}

pub fn formatDefaultBlock(
    comptime Type: type,
    self: *const Argument(Type),
    allocator: mem.Allocator,
) ![]const u8 {
    _ = self;
    return allocator.dupe(u8, "");
}

pub fn parseDefault(
    comptime Type: type,
    self: *const Argument(Type),
    value: Argument(Type).Value,
) anyerror!Type {
    _ = self;
    _ = value;
    return error.ReplaceDefaultParser;
}

test Enum {
    const En = enum { first, second };
    const Arg = Argument(En);

    var it = Arg.ValueIterator{ .data = &.{"--first"} };

    const first = Arg.Values{
        .string = "--first",
        .short_string = "-f",
        .parsed = .first,
    };

    const second = Arg.Values{ .string = "--second", .parsed = .second };

    const en = try Enum.default(En, .{
        .name = "",
        .values = &.{ first, second },
        .positional = true,
    });

    try testing.expectEqual(.first, try en.parse(&it));

    it.data = &.{"-f"};
    try testing.expectEqual(.first, try en.parse(&it));

    it.data = &.{"--second"};
    try testing.expectEqual(.second, try en.parse(&it));

    it.data = &.{"wrong"};
    try testing.expectError(error.InvalidVariant, en.parse(&it));

    const en2 = Enum.default(En, .{
        .name = "",
        .values = &.{first},
        .positional = true,
    });

    try testing.expectError(error.NotEnoughVariants, en2);
}
