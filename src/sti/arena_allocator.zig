const std = @import("std");

const sti = @import("sti");

const mem = std.mem;
const Alignment = std.mem.Alignment;
const Allocator = sti.Memory.Allocator;

///Mostly copied from the STD implementation of the arena allocator, except with the addition of the snapshot and restore
pub const ArenaAllocator = struct {
    child_allocator: Allocator,
    state: State,

    pub const State = struct {
        buffer_list: std.SinglyLinkedList = .{},
        end_index: usize = 0,

        pub fn promote(self: State, child_allocator: Allocator) ArenaAllocator {
            return .{
                .child_allocator = child_allocator,
                .state = self,
            };
        }
    };

    const BufNode = struct {
        data: usize,
        node: std.SinglyLinkedList.Node = .{},
    };
    const BufNode_alignment: Alignment = .of(BufNode);

    pub fn init(child_allocator: Allocator) ArenaAllocator {
        return (State{}).promote(child_allocator);
    }

    pub fn allocator(self: *ArenaAllocator) Allocator {
        return .{
            .inner = .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .remap = remap,
                    .free = free,
                },
            },
            .ext = &ext_vtable,
        };
    }

    const ext_vtable: Allocator.ExtVTable = .{
        .snapshot = snapshot,
        .restore = restore,
    };

    fn snapshot(ptr: *anyopaque) Allocator.Snapshot {
        const self: *ArenaAllocator = @ptrCast(@alignCast(ptr));
        return .{ .arena = .{
            .index = self.state.end_index,
            .node = if (self.state.buffer_list.first) |first| @ptrCast(first) else null,
        } };
    }

    fn restore(ptr: *anyopaque, snap: Allocator.Snapshot) void {
        const self: *ArenaAllocator = @ptrCast(@alignCast(ptr));
        const target_node: ?*std.SinglyLinkedList.Node = if (snap.arena.node) |n| @ptrCast(@alignCast(n)) else null;

        // Free all buffer nodes that were allocated after the snapshot
        var it = self.state.buffer_list.first;
        while (it) |node| {
            if (node == target_node) break;
            const next_it = node.next;
            const buf_node: *BufNode = @fieldParentPtr("node", node);
            const alloc_buf = @as([*]u8, @ptrCast(buf_node))[0..buf_node.data];
            self.child_allocator.inner.rawFree(alloc_buf, BufNode_alignment, @returnAddress());
            it = next_it;
        }

        self.state.buffer_list.first = target_node;
        self.state.end_index = snap.arena.index;
    }

    pub fn deinit(self: ArenaAllocator) void {
        var it = self.state.buffer_list.first;
        while (it) |node| {
            const next_it = node.next;
            const buf_node: *BufNode = @fieldParentPtr("node", node);
            const alloc_buf = @as([*]u8, @ptrCast(buf_node))[0..buf_node.data];
            self.child_allocator.inner.rawFree(alloc_buf, BufNode_alignment, @returnAddress());
            it = next_it;
        }
    }

    pub const ResetMode = union(enum) {
        free_all,
        retain_capacity,
        retain_with_limit: usize,
    };

    pub fn queryCapacity(self: ArenaAllocator) usize {
        var size: usize = 0;
        var it = self.state.buffer_list.first;
        while (it) |node| : (it = node.next) {
            const buf_node: *BufNode = @fieldParentPtr("node", node);
            size += buf_node.data - @sizeOf(BufNode);
        }
        return size;
    }

    pub fn reset(self: *ArenaAllocator, mode: ResetMode) bool {
        const requested_capacity = switch (mode) {
            .retain_capacity => self.queryCapacity(),
            .retain_with_limit => |limit| @min(limit, self.queryCapacity()),
            .free_all => 0,
        };
        if (requested_capacity == 0) {
            self.deinit();
            self.state = State{};
            return true;
        }
        const total_size = requested_capacity + @sizeOf(BufNode);
        var it = self.state.buffer_list.first;
        const maybe_first_node = while (it) |node| {
            const next_it = node.next;
            if (next_it == null)
                break node;
            const buf_node: *BufNode = @fieldParentPtr("node", node);
            const alloc_buf = @as([*]u8, @ptrCast(buf_node))[0..buf_node.data];
            self.child_allocator.inner.rawFree(alloc_buf, BufNode_alignment, @returnAddress());
            it = next_it;
        } else null;
        std.debug.assert(maybe_first_node == null or maybe_first_node.?.next == null);
        self.state.end_index = 0;
        if (maybe_first_node) |first_node| {
            self.state.buffer_list.first = first_node;
            const first_buf_node: *BufNode = @fieldParentPtr("node", first_node);
            if (first_buf_node.data == total_size)
                return true;
            const first_alloc_buf = @as([*]u8, @ptrCast(first_buf_node))[0..first_buf_node.data];
            if (self.child_allocator.inner.rawResize(first_alloc_buf, BufNode_alignment, total_size, @returnAddress())) {
                first_buf_node.data = total_size;
            } else {
                const new_ptr = self.child_allocator.inner.rawAlloc(total_size, BufNode_alignment, @returnAddress()) orelse {
                    return false;
                };
                self.child_allocator.inner.rawFree(first_alloc_buf, BufNode_alignment, @returnAddress());
                const buf_node: *BufNode = @ptrCast(@alignCast(new_ptr));
                buf_node.* = .{ .data = total_size };
                self.state.buffer_list.first = &buf_node.node;
            }
        }
        return true;
    }

    fn createNode(self: *ArenaAllocator, prev_len: usize, minimum_size: usize) ?*BufNode {
        const actual_min_size = minimum_size + (@sizeOf(BufNode) + 16);
        const big_enough_len = prev_len + actual_min_size;
        const len = big_enough_len + big_enough_len / 2;
        const ptr = self.child_allocator.inner.rawAlloc(len, BufNode_alignment, @returnAddress()) orelse
            return null;
        const buf_node: *BufNode = @ptrCast(@alignCast(ptr));
        buf_node.* = .{ .data = len };
        self.state.buffer_list.prepend(&buf_node.node);
        self.state.end_index = 0;
        return buf_node;
    }

    fn alloc(ctx: *anyopaque, n: usize, alignment: Alignment, ra: usize) ?[*]u8 {
        const self: *ArenaAllocator = @ptrCast(@alignCast(ctx));
        _ = ra;

        const ptr_align = alignment.toByteUnits();
        var cur_node: *BufNode = if (self.state.buffer_list.first) |first_node|
            @fieldParentPtr("node", first_node)
        else
            (self.createNode(0, n + ptr_align) orelse return null);
        while (true) {
            const cur_alloc_buf = @as([*]u8, @ptrCast(cur_node))[0..cur_node.data];
            const cur_buf = cur_alloc_buf[@sizeOf(BufNode)..];
            const addr = @intFromPtr(cur_buf.ptr) + self.state.end_index;
            const adjusted_addr = mem.alignForward(usize, addr, ptr_align);
            const adjusted_index = self.state.end_index + (adjusted_addr - addr);
            const new_end_index = adjusted_index + n;

            if (new_end_index <= cur_buf.len) {
                const result = cur_buf[adjusted_index..new_end_index];
                self.state.end_index = new_end_index;
                return result.ptr;
            }

            const bigger_buf_size = @sizeOf(BufNode) + new_end_index;
            if (self.child_allocator.inner.rawResize(cur_alloc_buf, BufNode_alignment, bigger_buf_size, @returnAddress())) {
                cur_node.data = bigger_buf_size;
            } else {
                cur_node = self.createNode(cur_buf.len, n + ptr_align) orelse return null;
            }
        }
    }

    fn resize(ctx: *anyopaque, buf: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *ArenaAllocator = @ptrCast(@alignCast(ctx));
        _ = alignment;
        _ = ret_addr;

        const cur_node = self.state.buffer_list.first orelse return false;
        const cur_buf_node: *BufNode = @fieldParentPtr("node", cur_node);
        const cur_buf = @as([*]u8, @ptrCast(cur_buf_node))[@sizeOf(BufNode)..cur_buf_node.data];
        if (@intFromPtr(cur_buf.ptr) + self.state.end_index != @intFromPtr(buf.ptr) + buf.len) {
            return new_len <= buf.len;
        }

        if (buf.len >= new_len) {
            self.state.end_index -= buf.len - new_len;
            return true;
        } else if (cur_buf.len - self.state.end_index >= new_len - buf.len) {
            self.state.end_index += new_len - buf.len;
            return true;
        } else {
            return false;
        }
    }

    fn remap(
        context: *anyopaque,
        memory: []u8,
        alignment: Alignment,
        new_len: usize,
        return_address: usize,
    ) ?[*]u8 {
        return if (resize(context, memory, alignment, new_len, return_address)) memory.ptr else null;
    }

    fn free(ctx: *anyopaque, buf: []u8, alignment: Alignment, ret_addr: usize) void {
        _ = alignment;
        _ = ret_addr;

        const self: *ArenaAllocator = @ptrCast(@alignCast(ctx));

        const cur_node = self.state.buffer_list.first orelse return;
        const cur_buf_node: *BufNode = @fieldParentPtr("node", cur_node);
        const cur_buf = @as([*]u8, @ptrCast(cur_buf_node))[@sizeOf(BufNode)..cur_buf_node.data];

        if (@intFromPtr(cur_buf.ptr) + self.state.end_index == @intFromPtr(buf.ptr) + buf.len) {
            self.state.end_index -= buf.len;
        }
    }
};

const testing = @import("testing.zig");
const test_allocator = Allocator.from_std(testing.allocator);

test "basic allocation and free" {
    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const slice = try a.alloc(u8, 100);
    try testing.expect_equal(@as(usize, 100), slice.len);

    // allocate different types
    const int_slice = try a.alloc(u32, 10);
    try testing.expect_equal(@as(usize, 10), int_slice.len);

    const ptr = try a.create(u64);
    ptr.* = 42;
    try testing.expect_equal(@as(u64, 42), ptr.*);
}

test "reset with preheating" {
    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();
    var rng_src = std.Random.DefaultPrng.init(testing.random_seed);
    const random = rng_src.random();
    var rounds: usize = 25;
    while (rounds > 0) {
        rounds -= 1;
        _ = arena.reset(.retain_capacity);
        var alloced_bytes: usize = 0;
        const total_size: usize = random.intRangeAtMost(usize, 256, 16384);
        while (alloced_bytes < total_size) {
            const size = random.intRangeAtMost(usize, 16, 256);
            const alignment: Alignment = .@"32";
            const slice = try arena.allocator().to_std().alignedAlloc(u8, alignment, size);
            try testing.expect(alignment.check(@intFromPtr(slice.ptr)));
            try testing.expect_equal(size, slice.len);
            alloced_bytes += slice.len;
        }
    }
}

test "reset while retaining a buffer" {
    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    _ = try a.alloc(u8, 1);
    _ = try a.alloc(u8, 1000);

    try testing.expect(arena.state.buffer_list.first.?.next != null);
    try testing.expect(arena.reset(.{ .retain_with_limit = 1 }));
}

test "snapshot and restore basic" {
    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // allocate some initial data
    const before = try a.alloc(u8, 64);
    @memset(before, 0xAA);

    // take a snapshot
    const snap = a.snapshot();

    // allocate more data after snapshot
    const after1 = try a.alloc(u8, 128);
    @memset(after1, 0xBB);
    const after2 = try a.alloc(u8, 256);
    @memset(after2, 0xCC);

    // restore to snapshot, frees after1 and after2
    a.restore(snap);

    // the end_index should be back to where it was at snapshot time
    try testing.expect_equal(snap.arena.index, arena.state.end_index);
}

test "snapshot and restore preserves pre-snapshot data" {
    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const data = try a.alloc(u8, 100);
    @memset(data, 0x42);

    const snap = a.snapshot();

    // allocate and write after snapshot
    _ = try a.alloc(u8, 500);

    a.restore(snap);

    // pre-snapshot data should still be intact
    for (data) |byte| {
        try testing.expect_equal(@as(u8, 0x42), byte);
    }
}

test "snapshot and restore with multiple buffer nodes" {
    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // force creation of at least one buffer node
    _ = try a.alloc(u8, 1);

    const snap = a.snapshot();

    // allocate enough to force new buffer nodes
    for (0..50) |_| {
        _ = try a.alloc(u8, 4096);
    }

    // should have multiple buffer nodes now
    try testing.expect(arena.state.buffer_list.first.?.next != null);

    // restore should free all the extra nodes
    a.restore(snap);

    try testing.expect_equal(snap.arena.index, arena.state.end_index);
}

test "multiple snapshot restore cycles" {
    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    for (0..10) |_| {
        const snap = a.snapshot();

        _ = try a.alloc(u8, 256);
        _ = try a.alloc(u32, 64);
        _ = try a.alloc(u8, 1024);

        a.restore(snap);
    }

    // after all cycles, arena should be in a similar state to the start
    // (the end_index resets each time)
    try testing.expect_equal(@as(usize, 0), arena.state.end_index);
}

test "snapshot on empty arena" {
    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const snap = a.snapshot();
    try testing.expect_equal(@as(usize, 0), snap.arena.index);
    try testing.expect_equal(@as(?*anyopaque, null), snap.arena.node);

    _ = try a.alloc(u8, 100);

    a.restore(snap);

    // arena should be back to empty state
    try testing.expect_equal(@as(usize, 0), arena.state.end_index);
    try testing.expect_equal(@as(?*std.SinglyLinkedList.Node, null), arena.state.buffer_list.first);
}

test "nested snapshots" {
    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    _ = try a.alloc(u8, 64);
    const snap_outer = a.snapshot();

    _ = try a.alloc(u8, 128);
    const snap_inner = a.snapshot();

    _ = try a.alloc(u8, 256);

    // restore inner first
    a.restore(snap_inner);
    try testing.expect_equal(snap_inner.arena.index, arena.state.end_index);

    // can still allocate after inner restore
    _ = try a.alloc(u8, 32);

    // restore outer rolls back everything after outer snapshot
    a.restore(snap_outer);
    try testing.expect_equal(snap_outer.arena.index, arena.state.end_index);
}
