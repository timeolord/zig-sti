const sti = @import("sti");
const fmt = @import("std").fmt;

const Allocator = sti.Memory.Allocator;

pub fn append_fmt(allocator: Allocator, string: *sti.ArrayList(u8), comptime format: []const u8, args: anytype) !void {
    const s = try fmt.allocPrint(allocator.to_std(), format, args);
    defer allocator.free(s);
    try string.extend_from_slice(allocator, s);
}

pub fn alloc_print(gpa: Allocator, comptime format: []const u8, args: anytype) Allocator.Error![]u8 {
    return fmt.allocPrint(gpa.to_std(), format, args);
}

pub fn buf_print(buf: []u8, comptime format: []const u8, args: anytype) fmt.BufPrintError![]u8 {
    return fmt.bufPrint(buf, format, args);
}
