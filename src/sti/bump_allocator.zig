const std = @import("std");

pub const BumpAllocator = struct {
    const Self = @This();

    pub const Snapshot = struct { index: usize };

    inner: std.heap.FixedBufferAllocator,

    pub fn init(buffer: []u8) Self {
        return .{ .inner = std.heap.FixedBufferAllocator.init(buffer) };
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return self.inner.allocator();
    }

    pub fn snapshot(self: *const Self) Snapshot {
        return .{ .index = self.inner.end_index };
    }

    pub fn restore(self: *Self, point: Snapshot) void {
        self.inner.end_index = point.index;
    }

    pub fn reset(self: *Self) void {
        self.inner.reset();
    }
};
