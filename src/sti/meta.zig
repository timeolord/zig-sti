const std = @import("std");

pub fn eql(a: anytype, b: @TypeOf(a)) bool {
    return std.meta.eql(a, b);
}

pub fn elem(comptime T: type) type {
    return std.meta.Elem(T);
}

pub fn fields(comptime T: type) []const std.meta.fields(T)[0..].child {
    return std.meta.fields(T);
}

pub fn tag(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .@"enum" => T,
        .@"union" => |u| u.tag_type orelse @compileError("tag requires a tagged union"),
        else => @compileError("tag requires an enum or tagged union"),
    };
}

pub fn tag_name(value: anytype) []const u8 {
    return @tagName(value);
}

pub fn active_tag(value: anytype) tag(@TypeOf(value)) {
    return switch (@typeInfo(@TypeOf(value))) {
        .@"enum" => value,
        .@"union" => |u| {
            const tag_type = u.tag_type orelse @compileError("active_tag requires a tagged union");
            return @as(tag_type, value);
        },
        else => @compileError("active_tag requires an enum or tagged union"),
    };
}

pub fn field_info(comptime T: type, comptime field_name: []const u8) @TypeOf(fields(T)[0]) {
    inline for (fields(T)) |field| {
        if (std.mem.eql(u8, field.name, field_name)) return field;
    }
    @compileError("field not found: " ++ field_name);
}

const testing = @import("testing.zig");

test "eql compares structs" {
    const T = struct { a: u8, b: bool };
    try testing.expect(eql(T{ .a = 1, .b = true }, T{ .a = 1, .b = true }));
    try testing.expect(!eql(T{ .a = 1, .b = true }, T{ .a = 2, .b = true }));
}

test "elem returns pointee type" {
    try testing.expect_equal(u8, elem([]const u8));
}

test "fields exposes struct fields" {
    const T = struct { a: u8, b: bool };
    try testing.expect_equal(@as(usize, 2), fields(T).len);
    try testing.expect_equal_strings("a", fields(T)[0].name);
}

test "tag_name and active_tag work for tagged unions" {
    const T = union(enum) { a: u8, b: bool };
    const value: T = .{ .b = true };
    try testing.expect_equal_strings("b", tag_name(active_tag(value)));
}

test "field_info returns named field metadata" {
    const T = struct { alpha: u8, beta: bool };
    const field = field_info(T, "beta");
    try testing.expect_equal_strings("beta", field.name);
}
