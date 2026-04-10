const std = @import("std");

pub const page_allocator: Allocator = .{ .inner = std.heap.page_allocator, .ext = &Allocator.no_ext_vtable };
pub const ArenaAllocator = @import("arena_allocator.zig").ArenaAllocator;
pub const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
pub const DebugAllocator = std.heap.DebugAllocator;

const local_debug = @import("debug.zig");

pub const Allocator = struct {
    const Self = @This();

    inner: std.mem.Allocator,
    ext: *const ExtVTable,

    pub const Snapshot = union {
        arena: struct { index: usize, node: ?*anyopaque },
        debug: void, // Todo?
    };
    pub const Error = std.mem.Allocator.Error;

    pub const ExtVTable = struct {
        snapshot: *const fn (*anyopaque) Snapshot,
        restore: *const fn (*anyopaque, Snapshot) void,
    };

    pub const no_ext_vtable: ExtVTable = .{
        .snapshot = no_snapshot,
        .restore = no_restore,
    };

    fn no_snapshot(_: *anyopaque) Snapshot {
        local_debug.panic("Snapshot is not implemented for this allocator", .{});
    }

    fn no_restore(_: *anyopaque, _: Snapshot) void {
        local_debug.panic("Restore is not implemented for this allocator", .{});
    }

    pub fn from_std(a: std.mem.Allocator) Self {
        return .{ .inner = a, .ext = &no_ext_vtable };
    }

    pub fn to_std(self: Self) std.mem.Allocator {
        return self.inner;
    }

    pub fn snapshot(self: Self) Snapshot {
        return self.ext.snapshot(self.inner.ptr);
    }

    pub fn restore(self: Self, s: Snapshot) void {
        self.ext.restore(self.inner.ptr, s);
    }

    pub fn alloc(self: Self, comptime T: type, n: usize) Error![]T {
        return self.inner.alloc(T, n);
    }

    pub fn alloc_sentinel(self: Self, comptime T: type, n: usize, comptime sentinel: T) Error![:sentinel]T {
        return self.inner.allocSentinel(T, n, sentinel);
    }

    pub fn free(self: Self, memory: anytype) void {
        self.inner.free(memory);
    }

    pub fn create(self: Self, comptime T: type) Error!*T {
        return self.inner.create(T);
    }

    pub fn destroy(self: Self, ptr: anytype) void {
        self.inner.destroy(ptr);
    }

    pub fn dupe(self: Self, comptime T: type, m: []const T) Error![]T {
        return self.inner.dupe(T, m);
    }

    pub fn dupeZ(self: Self, comptime T: type, m: []const T) Error![:0]T {
        return self.inner.dupeZ(T, m);
    }
};

const testing = @import("testing.zig");
const test_allocator = Allocator.from_std(testing.allocator);

test "alloc_sentinel initializes sentinel slot" {
    const slice = try test_allocator.alloc_sentinel(u8, 3, 0);
    defer test_allocator.free(slice);

    try testing.expect_equal(@as(usize, 3), slice.len);
    try testing.expect_equal(@as(u8, 0), slice[3]);
}
