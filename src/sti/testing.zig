const std = @import("std");
const sti = @import("sti");

pub const allocator = sti.Memory.Allocator.from_std(std.testing.allocator);
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
