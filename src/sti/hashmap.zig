const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn HashMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const Inner = std.AutoHashMapUnmanaged(K, V);

        pub const Entry = Inner.Entry;
        pub const KV = Inner.KV;
        pub const GetOrPutResult = Inner.GetOrPutResult;
        pub const Iterator = Inner.Iterator;
        pub const KeyIterator = Inner.KeyIterator;
        pub const ValueIterator = Inner.ValueIterator;

        inner: Inner = .{},

        /// Creates a new, empty HashMap. Does not allocate.
        pub fn init() Self {
            return .{};
        }

        /// Creates a new, empty HashMap with at least the specified capacity pre-allocated.
        pub fn with_capacity(allocator: Allocator, cap: u32) !Self {
            var self = Self{};
            try self.inner.ensureTotalCapacity(allocator, cap);
            return self;
        }

        /// Frees the memory associated with this HashMap.
        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.inner.deinit(allocator);
        }

        /// Returns the number of key-value pairs in the map.
        pub fn len(self: Self) usize {
            return self.inner.count();
        }

        /// Returns true if the map contains no elements.
        pub fn is_empty(self: Self) bool {
            return self.inner.count() == 0;
        }

        /// Returns a copy of the value associated with the key, or null if not present.
        pub fn get(self: Self, key: K) ?V {
            return self.inner.get(key);
        }

        /// Returns a pointer to the value associated with the key, or null if not present.
        pub fn get_ptr(self: Self, key: K) ?*V {
            return self.inner.getPtr(key);
        }

        /// Returns true if the map contains the given key.
        pub fn contains_key(self: Self, key: K) bool {
            return self.inner.contains(key);
        }

        /// Inserts or updates a key-value pair. Returns the old value if the key was already present.
        pub fn insert(self: *Self, allocator: Allocator, key: K, value: V) !?V {
            const result = try self.inner.fetchPut(allocator, key, value);
            return if (result) |kv| kv.value else null;
        }

        /// Removes the key from the map. Returns the value if the key was present.
        pub fn remove(self: *Self, key: K) ?V {
            const result = self.inner.fetchRemove(key);
            return if (result) |kv| kv.value else null;
        }

        /// Clears the map, removing all entries but retaining the allocated capacity.
        pub fn clear(self: *Self) void {
            self.inner.clearRetainingCapacity();
        }

        /// Returns a result that can be used to insert or update an entry in-place.
        /// `found_existing` indicates whether the key was already present.
        pub fn entry(self: *Self, allocator: Allocator, key: K) !GetOrPutResult {
            return self.inner.getOrPut(allocator, key);
        }

        /// Returns an iterator over all key-value entries.
        pub fn iter(self: *const Self) Iterator {
            return self.inner.iterator();
        }

        /// Returns an iterator over all keys.
        pub fn keys(self: Self) KeyIterator {
            return self.inner.keyIterator();
        }

        /// Returns an iterator over all values.
        pub fn values(self: Self) ValueIterator {
            return self.inner.valueIterator();
        }
    };
}

const testing = @import("testing.zig");

test "init creates empty map" {
    var map = HashMap(u32, u32).init();
    try testing.expect(map.is_empty());
    try testing.expect_equal(@as(usize, 0), map.len());
}

test "with_capacity" {
    var map = try HashMap(u32, u32).with_capacity(testing.allocator, 8);
    defer map.deinit(testing.allocator);
    try testing.expect(map.is_empty());
}

test "insert and get" {
    var map = HashMap(u32, u32).init();
    defer map.deinit(testing.allocator);
    _ = try map.insert(testing.allocator, 1, 100);
    _ = try map.insert(testing.allocator, 2, 200);
    try testing.expect_equal(@as(usize, 2), map.len());
    try testing.expect_equal(@as(?u32, 100), map.get(1));
    try testing.expect_equal(@as(?u32, 200), map.get(2));
    try testing.expect_equal(@as(?u32, null), map.get(3));
}

test "insert returns old value on update" {
    var map = HashMap(u32, u32).init();
    defer map.deinit(testing.allocator);
    const old1 = try map.insert(testing.allocator, 1, 100);
    try testing.expect_equal(@as(?u32, null), old1);
    const old2 = try map.insert(testing.allocator, 1, 999);
    try testing.expect_equal(@as(?u32, 100), old2);
    try testing.expect_equal(@as(?u32, 999), map.get(1));
}

test "get_ptr allows in-place mutation" {
    var map = HashMap(u32, u32).init();
    defer map.deinit(testing.allocator);
    _ = try map.insert(testing.allocator, 1, 10);
    const ptr = map.get_ptr(1).?;
    ptr.* = 42;
    try testing.expect_equal(@as(?u32, 42), map.get(1));
}

test "remove returns value" {
    var map = HashMap(u32, u32).init();
    defer map.deinit(testing.allocator);
    _ = try map.insert(testing.allocator, 1, 100);
    try testing.expect_equal(@as(?u32, 100), map.remove(1));
    try testing.expect_equal(@as(?u32, null), map.remove(1));
    try testing.expect(map.is_empty());
}

test "contains_key" {
    var map = HashMap(u32, u32).init();
    defer map.deinit(testing.allocator);
    _ = try map.insert(testing.allocator, 1, 100);
    try testing.expect(map.contains_key(1));
    try testing.expect(!map.contains_key(2));
}

test "clear retains capacity" {
    var map = HashMap(u32, u32).init();
    defer map.deinit(testing.allocator);
    _ = try map.insert(testing.allocator, 1, 1);
    _ = try map.insert(testing.allocator, 2, 2);
    map.clear();
    try testing.expect(map.is_empty());
    try testing.expect(!map.contains_key(1));
}

test "entry for insert and update" {
    var map = HashMap(u32, u32).init();
    defer map.deinit(testing.allocator);
    const result = try map.entry(testing.allocator, 42);
    try testing.expect(!result.found_existing);
    result.value_ptr.* = 100;
    const result2 = try map.entry(testing.allocator, 42);
    try testing.expect(result2.found_existing);
    try testing.expect_equal(@as(u32, 100), result2.value_ptr.*);
}

test "iter visits all entries" {
    var map = HashMap(u32, u32).init();
    defer map.deinit(testing.allocator);
    _ = try map.insert(testing.allocator, 1, 10);
    _ = try map.insert(testing.allocator, 2, 20);
    _ = try map.insert(testing.allocator, 3, 30);
    var count: usize = 0;
    var it = map.iter();
    while (it.next()) |_| count += 1;
    try testing.expect_equal(@as(usize, 3), count);
}
