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
