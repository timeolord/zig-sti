const std = @import("std");

pub const allocator = std.testing.allocator;
pub const random_seed = std.testing.random_seed;

pub fn expect(ok: bool) !void {
    try std.testing.expect(ok);
}

pub fn expect_equal(expected: anytype, actual: @TypeOf(expected)) !void {
    try std.testing.expectEqual(expected, actual);
}

pub fn expect_equal_deep(expected: anytype, actual: @TypeOf(expected)) !void {
    try std.testing.expectEqualDeep(expected, actual);
}

pub fn expect_equal_slices(comptime T: type, expected: []const T, actual: []const T) !void {
    try std.testing.expectEqualSlices(T, expected, actual);
}

pub fn expect_equal_strings(expected: []const u8, actual: []const u8) !void {
    try std.testing.expectEqualStrings(expected, actual);
}

test "expect_equal compares values" {
    try expect_equal(@as(u8, 2), 2);
}

test "expect_equal_deep compares structs" {
    const T = struct { a: u8, b: bool };
    try expect_equal_deep(T{ .a = 1, .b = true }, T{ .a = 1, .b = true });
}

test "expect_equal_slices compares slices" {
    const expected = [_]u8{ 1, 2, 3 };
    const actual = [_]u8{ 1, 2, 3 };
    try expect_equal_slices(u8, &expected, &actual);
}

test "expect_equal_strings compares strings" {
    try expect_equal_strings("sti", "sti");
}
