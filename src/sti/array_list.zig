const std = @import("std");

const sti = @import("sti");

const Allocator = sti.Memory.Allocator;

pub fn ArrayList(comptime T: type) type {
    return struct {
        const Self = @This();
        inner: std.ArrayList(T) = .{},

        /// Creates a new, empty ArrayList. Does not allocate.
        pub fn init() Self {
            return .{};
        }

        /// Creates a new, empty ArrayList with at least the specified capacity pre-allocated.
        pub fn with_capacity(allocator: Allocator, cap: usize) !Self {
            return .{ .inner = try std.ArrayList(T).initCapacity(allocator.to_std(), cap) };
        }

        /// Frees the memory associated with this ArrayList.
        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.inner.clearAndFree(allocator.to_std());
        }

        /// Returns a shallow copy of the ArrayList.
        pub fn clone(self: Self, allocator: Allocator) !Self {
            return .{ .inner = try self.inner.clone(allocator.to_std()) };
        }

        /// Returns the number of elements in the ArrayList.
        pub fn len(self: Self) usize {
            return self.inner.items.len;
        }

        /// Returns the total number of elements the ArrayList can hold without reallocating.
        pub fn capacity(self: Self) usize {
            return self.inner.capacity;
        }

        /// Returns true if the ArrayList contains no elements.
        pub fn is_empty(self: Self) bool {
            return self.inner.items.len == 0;
        }

        /// Returns the element at index, or null if out of bounds.
        pub fn get(self: Self, index: usize) ?T {
            if (index >= self.inner.items.len) return null;
            return self.inner.items[index];
        }

        /// Returns a slice of all elements.
        pub fn as_slice(self: Self) []T {
            return self.inner.items;
        }

        /// Appends an element to the back of the ArrayList.
        pub fn push(self: *Self, allocator: Allocator, item: T) !void {
            try self.inner.append(allocator.to_std(), item);
        }

        /// Removes the last element and returns it, or null if empty.
        pub fn pop(self: *Self) ?T {
            return self.inner.pop();
        }

        /// Inserts an element at the given index, shifting all elements after it to the right.
        pub fn insert(self: *Self, allocator: Allocator, index: usize, item: T) !void {
            try self.inner.insert(allocator.to_std(), index, item);
        }

        /// Removes and returns the element at index, shifting all elements after it to the left.
        pub fn remove(self: *Self, index: usize) T {
            return self.inner.orderedRemove(index);
        }

        /// Removes and returns the element at index by swapping it with the last element.
        /// Does not preserve ordering but is O(1).
        pub fn swap_remove(self: *Self, index: usize) T {
            return self.inner.swapRemove(index);
        }

        /// Clears the ArrayList, removing all elements, but retaining the allocated capacity.
        pub fn clear(self: *Self) void {
            self.inner.clearRetainingCapacity();
        }

        /// Shortens the ArrayList to at most new_len elements, retaining allocated capacity.
        pub fn truncate(self: *Self, new_len: usize) void {
            self.inner.shrinkRetainingCapacity(new_len);
        }

        /// Moves all elements of other into self, leaving other empty, but maintaining its capacity.
        pub fn append(self: *Self, allocator: Allocator, other: *Self) !void {
            try self.inner.appendSlice(allocator.to_std(), other.inner.items);
            other.inner.clearRetainingCapacity();
        }

        /// Extends the ArrayList by appending all elements from the slice.
        pub fn extend_from_slice(self: *Self, allocator: Allocator, slice: []const T) !void {
            try self.inner.appendSlice(allocator.to_std(), slice);
        }

        /// Returns true if the ArrayList contains the given element.
        /// Requires T to support == comparison.
        pub fn contains(self: Self, item: T) bool {
            for (self.inner.items) |x| {
                if (x == item) return true;
            }
            return false;
        }
    };
}

const testing = @import("testing.zig");
const test_allocator = sti.Memory.Allocator.from_std(testing.allocator);

test "init creates empty list" {
    var list = ArrayList(i32).init();
    try testing.expect(list.is_empty());
    try testing.expect_equal(@as(usize, 0), list.len());
}

test "with_capacity" {
    var list = try ArrayList(i32).with_capacity(test_allocator, 8);
    defer list.deinit(test_allocator);
    try testing.expect(list.is_empty());
    try testing.expect(list.capacity() >= 8);
}

test "push and len" {
    var list = ArrayList(i32).init();
    defer list.deinit(test_allocator);
    try list.push(test_allocator, 1);
    try list.push(test_allocator, 2);
    try list.push(test_allocator, 3);
    try testing.expect_equal(@as(usize, 3), list.len());
}

test "pop returns last element" {
    var list = ArrayList(i32).init();
    defer list.deinit(test_allocator);
    try list.push(test_allocator, 10);
    try list.push(test_allocator, 20);
    try testing.expect_equal(@as(?i32, 20), list.pop());
    try testing.expect_equal(@as(?i32, 10), list.pop());
    try testing.expect_equal(@as(?i32, null), list.pop());
}

test "pop on empty returns null" {
    var list = ArrayList(i32).init();
    try testing.expect_equal(@as(?i32, null), list.pop());
}

test "get returns element or null" {
    var list = ArrayList(i32).init();
    defer list.deinit(test_allocator);
    try list.push(test_allocator, 10);
    try list.push(test_allocator, 20);
    try testing.expect_equal(@as(?i32, 10), list.get(0));
    try testing.expect_equal(@as(?i32, 20), list.get(1));
    try testing.expect_equal(@as(?i32, null), list.get(2));
}

test "as_slice" {
    var list = ArrayList(i32).init();
    defer list.deinit(test_allocator);
    try list.push(test_allocator, 10);
    try list.push(test_allocator, 20);
    const s = list.as_slice();
    try testing.expect_equal(@as(usize, 2), s.len);
    try testing.expect_equal(@as(i32, 10), s[0]);
    try testing.expect_equal(@as(i32, 20), s[1]);
}

test "insert shifts elements right" {
    var list = ArrayList(i32).init();
    defer list.deinit(test_allocator);
    try list.push(test_allocator, 1);
    try list.push(test_allocator, 3);
    try list.insert(test_allocator, 1, 2);
    try testing.expect_equal(@as(?i32, 1), list.get(0));
    try testing.expect_equal(@as(?i32, 2), list.get(1));
    try testing.expect_equal(@as(?i32, 3), list.get(2));
}

test "remove shifts elements left" {
    var list = ArrayList(i32).init();
    defer list.deinit(test_allocator);
    try list.push(test_allocator, 1);
    try list.push(test_allocator, 2);
    try list.push(test_allocator, 3);
    try testing.expect_equal(@as(i32, 2), list.remove(1));
    try testing.expect_equal(@as(usize, 2), list.len());
    try testing.expect_equal(@as(?i32, 3), list.get(1));
}

test "swap_remove replaces with last element" {
    var list = ArrayList(i32).init();
    defer list.deinit(test_allocator);
    try list.push(test_allocator, 1);
    try list.push(test_allocator, 2);
    try list.push(test_allocator, 3);
    try testing.expect_equal(@as(i32, 1), list.swap_remove(0));
    try testing.expect_equal(@as(usize, 2), list.len());
    try testing.expect_equal(@as(?i32, 3), list.get(0));
}

test "clear retains capacity" {
    var list = ArrayList(i32).init();
    defer list.deinit(test_allocator);
    try list.push(test_allocator, 1);
    try list.push(test_allocator, 2);
    const cap = list.capacity();
    list.clear();
    try testing.expect(list.is_empty());
    try testing.expect_equal(cap, list.capacity());
}

test "truncate shortens list" {
    var list = ArrayList(i32).init();
    defer list.deinit(test_allocator);
    try list.push(test_allocator, 1);
    try list.push(test_allocator, 2);
    try list.push(test_allocator, 3);
    list.truncate(1);
    try testing.expect_equal(@as(usize, 1), list.len());
    try testing.expect_equal(@as(?i32, 1), list.get(0));
}

test "append moves elements leaving other empty" {
    var a = ArrayList(i32).init();
    defer a.deinit(test_allocator);
    var b = ArrayList(i32).init();
    defer b.deinit(test_allocator);
    try a.push(test_allocator, 1);
    try b.push(test_allocator, 2);
    try b.push(test_allocator, 3);
    try a.append(test_allocator, &b);
    try testing.expect_equal(@as(usize, 3), a.len());
    try testing.expect(b.is_empty());
    try testing.expect_equal(@as(?i32, 2), a.get(1));
    try testing.expect_equal(@as(?i32, 3), a.get(2));
}

test "extend_from_slice" {
    var list = ArrayList(i32).init();
    defer list.deinit(test_allocator);
    try list.extend_from_slice(test_allocator, &[_]i32{ 1, 2, 3 });
    try testing.expect_equal(@as(usize, 3), list.len());
    try testing.expect_equal(@as(?i32, 1), list.get(0));
    try testing.expect_equal(@as(?i32, 2), list.get(1));
    try testing.expect_equal(@as(?i32, 3), list.get(2));
}

test "contains" {
    var list = ArrayList(i32).init();
    defer list.deinit(test_allocator);
    try list.push(test_allocator, 1);
    try list.push(test_allocator, 2);
    try testing.expect(list.contains(1));
    try testing.expect(list.contains(2));
    try testing.expect(!list.contains(3));
}

test "clone is independent copy" {
    var list = ArrayList(i32).init();
    defer list.deinit(test_allocator);
    try list.push(test_allocator, 1);
    try list.push(test_allocator, 2);
    var cloned = try list.clone(test_allocator);
    defer cloned.deinit(test_allocator);
    try testing.expect_equal(list.len(), cloned.len());
    try testing.expect_equal(list.get(0), cloned.get(0));
    try testing.expect_equal(list.get(1), cloned.get(1));
    try list.push(test_allocator, 3);
    try testing.expect_equal(@as(usize, 2), cloned.len());
}
