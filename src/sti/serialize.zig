const std = @import("std");
const sti = @import("sti");

const assert = std.debug.assert;

fn sentinel_value(comptime T: type) ?sti.meta.elem(T) {
    return switch (@typeInfo(T)) {
        .array => |a| if (a.sentinel_ptr) |ptr| @as(*const a.child, @ptrCast(@alignCast(ptr))).* else null,
        .pointer => |p| switch (p.size) {
            .slice, .many => if (p.sentinel_ptr) |ptr| @as(*const p.child, @ptrCast(@alignCast(ptr))).* else null,
            .one, .c => null,
        },
        else => null,
    };
}

fn write_bytes(to_serialize: anytype, writer: anytype) std.Io.Writer.Error!void {
    // const padded_bits_needed = (@bitSizeOf(T) - 1) & 7 + 1;
    // const bytes_needed = @divExact(padded_bits_needed, 8);
    // var buf = [_]u8{0} ** bytes_needed;
    // todo ? do something for endianness ?
    // todo ? maybe i want to do some bitpacking ?
    const bytes = std.mem.asBytes(&to_serialize);
    var index: usize = 0;
    while (index != bytes.len) {
        index += try writer.write(bytes[index..]);
    }
}

fn read_bytes(read_into: anytype, reader: anytype) std.Io.Reader.Error!void {
    // todo ? do something for endianness ?
    // todo ? maybe i want to do some bitpacking ?
    const bytes = std.mem.asBytes(read_into);
    var index: usize = 0;
    while (index != bytes.len) {
        const read_len = try reader.read(bytes[index..]);
        if (read_len == 0) return error.EndOfStream;
        index += read_len;
    }
}
fn write_string(to_serialize: anytype, writer: anytype) std.Io.Writer.Error!void {
    const as_string = @typeName(@TypeOf(to_serialize)) ++ " = ";
    try writer.writeAll(as_string);
    try writer.print("{};\n", .{to_serialize});
}
fn read_string(read_into: anytype, reader: anytype) std.Io.Reader.Error!void {
    _ = read_into;
    _ = reader;
}
pub const SerializeMode = enum {
    bytes,
    strings,
};

pub fn serialize(comptime T: type, to_serialize: T, writer: *std.Io.Writer, comptime mode: SerializeMode) !void {
    const write: *const fn (anytype, anytype) std.Io.Writer.Error!void = &write_bytes;

    switch (mode) {
        .strings => {
            var serializer = std.zon.Serializer{ .writer = writer };
            switch (@typeInfo(T)) {
                .@"struct" => {
                    if (@hasDecl(T, "serialize")) {
                        var zon_struct = try serializer.beginStruct(.{ .whitespace_style = .{ .wrap = true } });
                        inline for (0..T.serialize.len) |i| {
                            const serialize_name = comptime @tagName(T.serialize[i]);
                            if (!@hasField(T, serialize_name)) {
                                @compileError("Could not serialize field " ++ serialize_name ++ " because it does not exist");
                            }

                            try zon_struct.field(serialize_name, @field(to_serialize, serialize_name), .{});
                        }
                        try zon_struct.end();
                    } else {
                        try serializer.value(to_serialize, .{});
                    }
                },
                else => {
                    try serializer.value(to_serialize, .{});
                },
            }
        },
        .bytes => {
            switch (@typeInfo(T)) {
                .@"struct" => |s| {
                    if (@hasDecl(T, "serialize")) {
                        inline for (0..T.serialize.len) |i| {
                            const serialize_name = comptime @tagName(T.serialize[i]);
                            if (!@hasField(T, serialize_name)) {
                                @compileError("Could not serialize field " ++ serialize_name ++ " because it does not exist");
                            }
                            try serialize(@FieldType(T, serialize_name), @field(to_serialize, serialize_name), writer, mode);
                        }
                    } else {
                        inline for (0..s.fields.len) |i| {
                            try serialize(@FieldType(T, s.fields[i].name), @field(to_serialize, s.fields[i].name), writer, mode);
                        }
                    }
                },
                .@"enum" => |e| {
                    // this is assuming our enums are all reasonably packed
                    // surely this will be the case xd
                    const enum_int: e.tag_type = @intFromEnum(to_serialize);
                    return write(enum_int, writer);
                },
                .@"union" => |u| {
                    if (u.tag_type) |tag_type| {
                        try serialize(tag_type, @as(tag_type, to_serialize), writer, mode);
                        switch (to_serialize) {
                            inline else => |val| {
                                return serialize(@TypeOf(val), val, writer, mode);
                            },
                        }
                    } else {
                        @compileError("Cannot serialize union: missing tag");
                    }
                },
                .optional => |o| {
                    const opt: bool = to_serialize != null;
                    try write(opt, writer);
                    if (opt) {
                        const child = to_serialize orelse unreachable;
                        return serialize(o.child, child, writer, mode);
                    }
                },
                .array => |a| {
                    for (0..a.len) |i| {
                        try serialize(a.child, to_serialize[i], writer, mode);
                    }
                },
                .pointer => |p| {
                    switch (p.size) {
                        .many => {
                            if (p.sentinel_ptr != null) {
                                @compileError("Cannot serialize sentinel many-pointers of unknown logical length");
                            }
                            @compileError("Cannot serialize pointer of unknown size");
                        },
                        .c => @compileError("Cannot serialize pointer of unknown size"),
                        .one => {
                            return serialize(p.child, to_serialize.*, writer, mode);
                        },
                        .slice => {
                            const len_u64: u64 = @intCast(to_serialize.len);
                            try write(len_u64, writer);
                            for (0..to_serialize.len) |i| {
                                try serialize(p.child, to_serialize[i], writer, mode);
                            }
                        },
                    }
                },
                .void => {},
                .int, .float, .bool => {
                    return write(to_serialize, writer);
                },
                else => {
                    @compileError("Cannot serialize this type: " ++ @typeName(T));
                },
            }
        },
    }
}

pub fn deserialize(comptime T: type, read_into: *T, reader: anytype, allocator: sti.Memory.Allocator, comptime mode: SerializeMode) !void {
    const read: *const fn (anytype, anytype) std.Io.Reader.Error!void = &read_bytes;

    switch (mode) {
        .strings => {
            const content = try reader.allocRemaining(allocator.to_std(), .unlimited);
            defer allocator.free(content);
            const c_string = try allocator.dupeZ(u8, content);
            defer allocator.free(c_string);

            switch (@typeInfo(T)) {
                .@"struct" => {
                    if (@hasDecl(T, "serialize")) {
                        const TempStruct = comptime blk: {
                            var temp_struct_fields: [T.serialize.len]std.builtin.Type.StructField = undefined;
                            for (0..T.serialize.len) |i| {
                                const serialize_name = @tagName(T.serialize[i]);
                                if (!@hasField(T, serialize_name)) {
                                    @compileError("Could not serialize field " ++ serialize_name ++ " because it does not exist");
                                }
                                temp_struct_fields[i] = .{
                                    .name = serialize_name,
                                    .type = @FieldType(T, serialize_name),
                                    .default_value_ptr = null,
                                    .is_comptime = false,
                                    .alignment = @alignOf(@FieldType(T, serialize_name)),
                                };
                            }
                            break :blk @Type(.{ .@"struct" = .{
                                .layout = .auto,
                                .fields = temp_struct_fields[0..],
                                .decls = &.{},
                                .is_tuple = false,
                            } });
                        };
                        const parsed = try std.zon.parse.fromSlice(TempStruct, allocator.to_std(), c_string, null, .{});
                        inline for (0..T.serialize.len) |i| {
                            const name = comptime @tagName(T.serialize[i]);
                            @field(read_into.*, name) = @field(parsed, name);
                        }
                    } else {
                        read_into.* = try std.zon.parse.fromSlice(T, allocator.to_std(), c_string, null, .{});
                    }
                },
                else => {
                    read_into.* = try std.zon.parse.fromSlice(T, allocator.to_std(), c_string, null, .{});
                },
            }
        },
        .bytes => {
            switch (@typeInfo(T)) {
                .@"struct" => |s| {
                    if (@hasDecl(T, "serialize")) {
                        inline for (0..T.serialize.len) |i| {
                            const serialize_name = comptime @tagName(T.serialize[i]);
                            if (!@hasField(T, serialize_name)) {
                                @compileError("Could not deserialize field " ++ serialize_name ++ " because it does not exist");
                            }
                            try deserialize(@FieldType(T, serialize_name), &@field(read_into, serialize_name), reader, allocator, mode);
                        }
                    } else {
                        inline for (0..s.fields.len) |i| {
                            try deserialize(@FieldType(T, s.fields[i].name), &@field(read_into, s.fields[i].name), reader, allocator, mode);
                        }
                    }
                },
                .@"enum" => |e| {
                    // this is assuming our enums are all reasonably packed
                    // surely this will be the case xd
                    var enum_int: e.tag_type = undefined;
                    try read(&enum_int, reader);

                    inline for (e.fields) |f| {
                        if (enum_int == f.value) {
                            read_into.* = @enumFromInt(enum_int);
                            return;
                        }
                    }
                    return error.InvalidValue;
                },
                .@"union" => |u| {
                    if (u.tag_type) |e| {
                        const e_inf = @typeInfo(e).@"enum";
                        var enum_int: e_inf.tag_type = undefined;
                        try read(&enum_int, reader);
                        inline for (e_inf.fields) |f| {
                            if (enum_int == f.value) {
                                // std.log.debug("trying to set {s}.{s}", .{ @typeName(@TypeOf(read_into.*)), f.name });
                                read_into.* = @unionInit(T, f.name, undefined);
                                return deserialize(@FieldType(T, f.name), &@field(read_into, f.name), reader, allocator, mode);
                            }
                        }
                        return error.InvalidValue;
                    } else {
                        @compileError("Cannot deserialize union: missing tag");
                    }
                },
                .optional => |o| {
                    var opt: bool = undefined;
                    try read(&opt, reader);
                    if (opt) {
                        // kludge but what if i want to fucking partially initialize my optional value instead of memcpying mr. zig ?
                        var opt_unwrapped: o.child = undefined;
                        try deserialize(o.child, &opt_unwrapped, reader, allocator, mode);
                        read_into.* = opt_unwrapped;
                    } else {
                        read_into.* = null;
                    }
                },
                .array => |a| {
                    for (0..a.len) |i| {
                        try deserialize(a.child, &read_into[i], reader, allocator, mode);
                    }

                    if (sentinel_value(T)) |sentinel| {
                        read_into[a.len] = sentinel;
                    }
                },
                .pointer => |p| {
                    switch (p.size) {
                        .many => {
                            if (p.sentinel_ptr != null) {
                                @compileError("Cannot deserialize sentinel many-pointers of unknown logical length");
                            }
                            @compileError("Cannot deserialize pointer of unknown size");
                        },
                        .c => @compileError("Cannot deserialize pointer of unknown size"),
                        .one => {
                            read_into.* = try allocator.create(p.child);
                            return deserialize(p.child, read_into.*, reader, allocator, mode);
                        },
                        .slice => {
                            var len_u64: u64 = undefined;
                            try read(&len_u64, reader);
                            if (len_u64 > std.math.maxInt(usize)) {
                                return error.IntegerOverflow;
                            }
                            const len: usize = @intCast(len_u64);

                            if (sentinel_value(T)) |sentinel| {
                                read_into.* = try allocator.alloc_sentinel(p.child, len, sentinel);
                            } else {
                                read_into.* = try allocator.alloc(p.child, len);
                            }

                            for (0..len) |i| {
                                try deserialize(p.child, &read_into.*[i], reader, allocator, mode);
                            }
                        },
                    }
                },
                .void => {},
                .int, .float, .bool => {
                    return read(read_into, reader);
                },
                else => {
                    @compileError("Cannot deserialize this type: " ++ @typeName(T));
                },
            }
        },
    }
}

const testing = @import("testing.zig");
const test_allocator = testing.allocator;

const ChunkedReader = struct {
    data: []const u8,
    index: usize = 0,
    chunk_size: usize,

    pub const Error = error{EndOfStream};

    pub fn read(self: *ChunkedReader, dest: []u8) Error!usize {
        if (dest.len == 0) return 0;
        if (self.index >= self.data.len) return 0;

        const remaining = self.data.len - self.index;
        const amt = @min(@min(dest.len, self.chunk_size), remaining);
        @memcpy(dest[0..amt], self.data[self.index..][0..amt]);
        self.index += amt;
        return amt;
    }

    pub fn alloc_remaining(self: *ChunkedReader, allocator: std.mem.Allocator, limit: std.Io.Limit) ![]u8 {
        _ = limit;
        defer self.index = self.data.len;
        return allocator.dupe(u8, self.data[self.index..]);
    }
};

fn bytes_round_trip(comptime T: type, value: T, out: *T) !void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try serialize(T, value, &writer, .bytes);

    const written = writer.buffered();
    var reader = ChunkedReader{ .data = written, .chunk_size = 1 };
    try deserialize(T, out, &reader, test_allocator, .bytes);
}

fn strings_round_trip(comptime T: type, value: T, out: *T) !void {
    var buffer: [16384]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try serialize(T, value, &writer, .strings);

    const written = writer.buffered();
    var reader = ChunkedReader{ .data = written, .chunk_size = 7 };
    try deserialize(T, out, &reader, test_allocator, .strings);
}

test "bytes round trip handles partial primitive reads" {
    const input: u32 = 0x12345678;
    var output: u32 = 0;
    try bytes_round_trip(u32, input, &output);
    try testing.expect_equal(input, output);
}

test "bytes enum round trip" {
    const ExampleEnum = enum(u8) { alpha = 1, beta = 3 };

    var output: ExampleEnum = .alpha;
    try bytes_round_trip(ExampleEnum, .beta, &output);
    try testing.expect_equal(.beta, output);
}

test "bytes tagged union round trip" {
    const ExampleUnion = union(enum) {
        int: u16,
        flag: bool,
    };

    var output: ExampleUnion = .{ .flag = false };
    try bytes_round_trip(ExampleUnion, .{ .int = 99 }, &output);
    try testing.expect_equal_deep(ExampleUnion{ .int = 99 }, output);
}

test "bytes optional round trip" {
    var some_value: ?u16 = null;
    try bytes_round_trip(?u16, 42, &some_value);
    try testing.expect_equal(@as(?u16, 42), some_value);

    var none_value: ?u16 = 7;
    try bytes_round_trip(?u16, null, &none_value);
    try testing.expect_equal(@as(?u16, null), none_value);
}

test "bytes fixed array round trip" {
    const input = [_]u16{ 4, 5, 6, 7 };
    var output: [4]u16 = undefined;
    try bytes_round_trip([4]u16, input, &output);
    try testing.expect_equal_deep(input, output);
}

test "bytes pointer one round trip" {
    var input: u32 = 77;
    var output: *u32 = undefined;
    defer test_allocator.destroy(output);

    try bytes_round_trip(*u32, &input, &output);
    try testing.expect_equal(@as(u32, 77), output.*);
}

test "bytes slice round trip" {
    var input = [_]u16{ 10, 20, 30 };
    var output: []u16 = undefined;
    defer test_allocator.free(output);

    try bytes_round_trip([]u16, input[0..], &output);
    try testing.expect_equal_slices(u16, &input, output);
}

test "bytes sentinel array round trip" {
    const input: [3:0]u8 = .{ 1, 2, 3 };
    var output: [3:0]u8 = undefined;

    try bytes_round_trip([3:0]u8, input, &output);
    try testing.expect_equal_slices(u8, input[0..], output[0..]);
    try testing.expect_equal(@as(u8, 0), output[3]);
}

test "bytes pointer to sentinel array round trip" {
    var input: [3:0]u8 = .{ 7, 8, 9 };
    var output: *[3:0]u8 = undefined;
    defer test_allocator.destroy(output);

    try bytes_round_trip(*[3:0]u8, &input, &output);
    try testing.expect_equal_slices(u8, input[0..], output[0..]);
    try testing.expect_equal(@as(u8, 0), output[3]);
}

test "bytes sentinel slice round trip" {
    var input = [_]u8{ 'z', 'i', 'g', 0 };
    const sentinel_input: [:0]u8 = input[0..3 :0];
    var output: [:0]u8 = undefined;
    defer test_allocator.free(output);

    try bytes_round_trip([:0]u8, sentinel_input, &output);
    try testing.expect_equal_slices(u8, sentinel_input, output);
    try testing.expect_equal(@as(u8, 0), output[output.len]);
}

test "bytes struct with sentinel fields round trip" {
    const Example = struct {
        label: [3:0]u8,
        bytes: [:0]u8,
    };

    var backing = [_]u8{ 'a', 'b', 'c', 0 };
    const input = Example{
        .label = .{ 4, 5, 6 },
        .bytes = backing[0..3 :0],
    };

    var output = Example{
        .label = undefined,
        .bytes = undefined,
    };
    defer test_allocator.free(output.bytes);

    try bytes_round_trip(Example, input, &output);
    try testing.expect_equal_slices(u8, input.label[0..], output.label[0..]);
    try testing.expect_equal(@as(u8, 0), output.label[3]);
    try testing.expect_equal_slices(u8, input.bytes, output.bytes);
    try testing.expect_equal(@as(u8, 0), output.bytes[output.bytes.len]);
}

test "bytes custom serialize struct uses only listed fields" {
    const Example = struct {
        pub const serialize = .{ .a, .c };

        a: u16,
        b: u16,
        c: bool,
    };

    var buffer: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try serialize(Example, .{ .a = 5, .b = 99, .c = true }, &writer, .bytes);

    const expected_len = @sizeOf(u16) + @sizeOf(bool);
    try testing.expect_equal(expected_len, writer.buffered().len);

    var output = Example{ .a = 0, .b = 1234, .c = false };
    var reader = ChunkedReader{ .data = writer.buffered(), .chunk_size = 1 };
    try deserialize(Example, &output, &reader, test_allocator, .bytes);

    try testing.expect_equal(@as(u16, 5), output.a);
    try testing.expect_equal(@as(u16, 1234), output.b);
    try testing.expect_equal(true, output.c);
}

test "strings simple struct round trip" {
    const Example = struct {
        a: u32,
        b: bool,
    };

    var output = Example{ .a = 0, .b = false };
    try strings_round_trip(Example, .{ .a = 15, .b = true }, &output);
    try testing.expect_equal_deep(Example{ .a = 15, .b = true }, output);
}

test "strings custom serialize struct preserves non serialized fields" {
    const Example = struct {
        pub const serialize = .{ .a, .items };

        a: u32,
        b: u32,
        items: []const u8,
    };

    var output = Example{
        .a = 0,
        .b = 999,
        .items = &.{},
    };
    defer test_allocator.free(output.items);

    try strings_round_trip(Example, .{
        .a = 22,
        .b = 33,
        .items = "zig",
    }, &output);

    try testing.expect_equal(@as(u32, 22), output.a);
    try testing.expect_equal(@as(u32, 999), output.b);
    try testing.expect_equal_strings("zig", output.items);
}

test "strings custom serialize supports more than 128 fields" {
    const Large = struct {
        pub const serialize =
            .{
                .f000,
                .f001,
                .f002,
                .f003,
                .f004,
                .f005,
                .f006,
                .f007,
                .f008,
                .f009,
                .f010,
                .f011,
                .f012,
                .f013,
                .f014,
                .f015,
                .f016,
                .f017,
                .f018,
                .f019,
                .f020,
                .f021,
                .f022,
                .f023,
                .f024,
                .f025,
                .f026,
                .f027,
                .f028,
                .f029,
                .f030,
                .f031,
                .f032,
                .f033,
                .f034,
                .f035,
                .f036,
                .f037,
                .f038,
                .f039,
                .f040,
                .f041,
                .f042,
                .f043,
                .f044,
                .f045,
                .f046,
                .f047,
                .f048,
                .f049,
                .f050,
                .f051,
                .f052,
                .f053,
                .f054,
                .f055,
                .f056,
                .f057,
                .f058,
                .f059,
                .f060,
                .f061,
                .f062,
                .f063,
                .f064,
                .f065,
                .f066,
                .f067,
                .f068,
                .f069,
                .f070,
                .f071,
                .f072,
                .f073,
                .f074,
                .f075,
                .f076,
                .f077,
                .f078,
                .f079,
                .f080,
                .f081,
                .f082,
                .f083,
                .f084,
                .f085,
                .f086,
                .f087,
                .f088,
                .f089,
                .f090,
                .f091,
                .f092,
                .f093,
                .f094,
                .f095,
                .f096,
                .f097,
                .f098,
                .f099,
                .f100,
                .f101,
                .f102,
                .f103,
                .f104,
                .f105,
                .f106,
                .f107,
                .f108,
                .f109,
                .f110,
                .f111,
                .f112,
                .f113,
                .f114,
                .f115,
                .f116,
                .f117,
                .f118,
                .f119,
                .f120,
                .f121,
                .f122,
                .f123,
                .f124,
                .f125,
                .f126,
                .f127,
                .f128,
            };

        f000: u8,
        f001: u8,
        f002: u8,
        f003: u8,
        f004: u8,
        f005: u8,
        f006: u8,
        f007: u8,
        f008: u8,
        f009: u8,
        f010: u8,
        f011: u8,
        f012: u8,
        f013: u8,
        f014: u8,
        f015: u8,
        f016: u8,
        f017: u8,
        f018: u8,
        f019: u8,
        f020: u8,
        f021: u8,
        f022: u8,
        f023: u8,
        f024: u8,
        f025: u8,
        f026: u8,
        f027: u8,
        f028: u8,
        f029: u8,
        f030: u8,
        f031: u8,
        f032: u8,
        f033: u8,
        f034: u8,
        f035: u8,
        f036: u8,
        f037: u8,
        f038: u8,
        f039: u8,
        f040: u8,
        f041: u8,
        f042: u8,
        f043: u8,
        f044: u8,
        f045: u8,
        f046: u8,
        f047: u8,
        f048: u8,
        f049: u8,
        f050: u8,
        f051: u8,
        f052: u8,
        f053: u8,
        f054: u8,
        f055: u8,
        f056: u8,
        f057: u8,
        f058: u8,
        f059: u8,
        f060: u8,
        f061: u8,
        f062: u8,
        f063: u8,
        f064: u8,
        f065: u8,
        f066: u8,
        f067: u8,
        f068: u8,
        f069: u8,
        f070: u8,
        f071: u8,
        f072: u8,
        f073: u8,
        f074: u8,
        f075: u8,
        f076: u8,
        f077: u8,
        f078: u8,
        f079: u8,
        f080: u8,
        f081: u8,
        f082: u8,
        f083: u8,
        f084: u8,
        f085: u8,
        f086: u8,
        f087: u8,
        f088: u8,
        f089: u8,
        f090: u8,
        f091: u8,
        f092: u8,
        f093: u8,
        f094: u8,
        f095: u8,
        f096: u8,
        f097: u8,
        f098: u8,
        f099: u8,
        f100: u8,
        f101: u8,
        f102: u8,
        f103: u8,
        f104: u8,
        f105: u8,
        f106: u8,
        f107: u8,
        f108: u8,
        f109: u8,
        f110: u8,
        f111: u8,
        f112: u8,
        f113: u8,
        f114: u8,
        f115: u8,
        f116: u8,
        f117: u8,
        f118: u8,
        f119: u8,
        f120: u8,
        f121: u8,
        f122: u8,
        f123: u8,
        f124: u8,
        f125: u8,
        f126: u8,
        f127: u8,
        f128: u8,
    };

    const input = comptime blk: {
        var value: Large = undefined;
        for (sti.meta.fields(Large), 0..) |field, i| {
            @field(value, field.name) = @intCast(i);
        }
        break :blk value;
    };

    var output: Large = undefined;
    try strings_round_trip(Large, input, &output);
    try testing.expect_equal_deep(input, output);
}
