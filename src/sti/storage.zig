const sti = @import("sti");
const debug = sti.debug;

const Allocator = sti.Memory.Allocator;

pub fn Array2D(comptime T: type, comptime size: anytype) type {
    return struct {
        const Self = @This();
        const PositionType = @TypeOf(size);
        const width = size.data[0];
        const height = size.data[1];

        storage: [width * height]T,

        pub fn init(val: T) Self {
            return Self{ .storage = [_]T{val} ** (width * height) };
        }

        pub fn get(self: *Self, pos: PositionType) *T {
            sti.assert(self.has_elem(pos));
            return &self.storage[to_linear_index(self, pos)];
        }
        pub fn read(self: *const Self, pos: PositionType) T {
            sti.assert(self.has_elem(pos));
            return self.storage[to_linear_index(self, pos)];
        }
        pub fn set(self: *Self, pos: PositionType, val: T) *T {
            const tile = self.get(pos);
            tile.* = val;
            return tile;
        }
        pub fn has_elem(_: anytype, pos: PositionType) bool {
            return pos.data[0] >= 0 and pos.data[0] < width and pos.data[1] >= 0 and pos.data[1] < height;
        }
        pub fn to_linear_index(_: anytype, pos: PositionType) usize {
            const x: usize = @intCast(pos.data[0]);
            const y: usize = @intCast(pos.data[1]);
            return x * height + y;
        }
        pub fn from_linear_index(_: anytype, i: usize) PositionType {
            const x = @divTrunc(@as(isize, @intCast(i)), height);
            const y = @rem(@as(isize, @intCast(i)), height);
            return .{ .data = .{ x, y } };
        }
        pub fn to_string(self: *const Self, allocator: sti.Memory.Allocator) ![]u8 {
            var buf = std.ArrayList(u8).init(allocator.to_std());
            errdefer buf.deinit();
            const writer = buf.writer();
            try writer.print("width:{d} height:{d}\n", .{ width, height });
            for (0..@intCast(width)) |x| {
                for (0..@intCast(height)) |y| {
                    const pos: PositionType = .{ .data = .{ @intCast(x), @intCast(y) } };
                    try writer.print("{any} ", .{self.read(pos)});
                }
                try writer.writeByte('\n');
            }
            return buf.toOwnedSlice();
        }
        pub const init_undefined: Self = .{ .storage = undefined };
    };
}

pub fn DynamicArray2D(comptime T: type, comptime PositionType: type) type {
    return struct {
        const Self = @This();

        storage: []T,
        width: usize,
        height: usize,

        pub fn init(allocator: Allocator, val: T, size: PositionType) Self {
            const w: usize = @intCast(size.data[0]);
            const h: usize = @intCast(size.data[1]);
            return init_split(allocator, val, w, h);
        }
        pub fn init_split(allocator: Allocator, val: T, width: usize, height: usize) Self {
            const data = allocator.alloc(T, width * height) catch
                debug.panic("cannot allocate DynamicArray2D backing store", .{});
            @memset(data, val);
            return Self{
                .storage = data,
                .width = width,
                .height = height,
            };
        }

        pub fn get(self: *Self, pos: PositionType) *T {
            sti.assert(self.has_elem(pos));
            return &self.storage[self.to_linear_index(pos)];
        }
        pub fn read(self: *const Self, pos: PositionType) T {
            sti.assert(self.has_elem(pos));
            return self.storage[self.to_linear_index(pos)];
        }
        pub fn set(self: *Self, pos: PositionType, val: T) *T {
            const tile = self.get(pos);
            tile.* = val;
            return tile;
        }
        pub fn has_elem(self: Self, pos: PositionType) bool {
            return pos.data[0] >= 0 and pos.data[0] < self.width and pos.data[1] >= 0 and pos.data[1] < self.height;
        }
        pub fn to_linear_index(self: Self, pos: PositionType) usize {
            const x: usize = @intCast(pos.data[0]);
            const y: usize = @intCast(pos.data[1]);
            return x * self.height + y;
        }
        pub fn from_linear_index(self: Self, i: usize) PositionType {
            const h: isize = @intCast(self.height);
            const x = @divTrunc(@as(isize, @intCast(i)), h);
            const y = @rem(@as(isize, @intCast(i)), h);
            return .{ .data = .{ x, y } };
        }
        pub fn to_string(self: *const Self, allocator: sti.Memory.Allocator) ![]u8 {
            var buf = std.ArrayList(u8).init(allocator.to_std());
            errdefer buf.deinit();
            const writer = buf.writer();
            try writer.print("width:{d} height:{d}\n", .{ self.width, self.height });
            for (0..self.width) |x| {
                for (0..self.height) |y| {
                    const pos: PositionType = .{ .data = .{ @intCast(x), @intCast(y) } };
                    try writer.print("{any} ", .{self.read(pos)});
                }
                try writer.writeByte('\n');
            }
            return buf.toOwnedSlice();
        }
    };
}

pub fn Chunks(comptime key: type, comptime value: type) type {
    return struct {
        const Self = @This();
        data: sti.HashMap(key, value) = .{},

        pub fn init() Self {
            return .{};
        }

        pub fn init_2d(allocator: Allocator, size: key, val: value) !Self {
            var self = Self{};
            const w: usize = @intCast(size.data[0]);
            const h: usize = @intCast(size.data[1]);
            for (0..w) |x| {
                for (0..h) |y| {
                    const pos: key = .{ .data = .{ @intCast(x), @intCast(y) } };
                    _ = try self.data.insert(allocator, pos, val);
                }
            }
            return self;
        }

        pub fn put(self: *Self, allocator: Allocator, k: key, v: value) !void {
            _ = try self.data.insert(allocator.to_std(), k, v);
        }
    };
}

const std = @import("std");
const testing = @import("testing.zig");

const TestPos = struct { data: [2]isize };
const test_allocator = Allocator.from_std(testing.allocator);

test "Array2D: init fills all cells" {
    const size = TestPos{ .data = .{ 4, 3 } };
    const Grid = Array2D(i32, size);
    const grid = Grid.init(7);
    for (grid.storage) |v| try testing.expect_equal(@as(i32, 7), v);
}

test "Array2D: set / get / read" {
    const size = TestPos{ .data = .{ 4, 3 } };
    const Grid = Array2D(i32, size);
    var grid = Grid.init(0);
    const pos = TestPos{ .data = .{ 2, 1 } };
    _ = grid.set(pos, 42);
    try testing.expect_equal(@as(i32, 42), grid.read(pos));
    try testing.expect_equal(@as(i32, 42), grid.get(pos).*);
}

test "Array2D: set does not clobber neighbours" {
    const size = TestPos{ .data = .{ 4, 3 } };
    const Grid = Array2D(i32, size);
    var grid = Grid.init(0);
    _ = grid.set(TestPos{ .data = .{ 1, 1 } }, 99);
    try testing.expect_equal(@as(i32, 0), grid.read(TestPos{ .data = .{ 1, 0 } }));
    try testing.expect_equal(@as(i32, 0), grid.read(TestPos{ .data = .{ 1, 2 } }));
    try testing.expect_equal(@as(i32, 0), grid.read(TestPos{ .data = .{ 0, 1 } }));
    try testing.expect_equal(@as(i32, 0), grid.read(TestPos{ .data = .{ 2, 1 } }));
}

test "Array2D: has_elem" {
    const size = TestPos{ .data = .{ 4, 3 } };
    const Grid = Array2D(i32, size);
    var grid = Grid.init(0);
    try testing.expect(grid.has_elem(TestPos{ .data = .{ 0, 0 } }));
    try testing.expect(grid.has_elem(TestPos{ .data = .{ 3, 2 } }));
    try testing.expect(!grid.has_elem(TestPos{ .data = .{ 4, 0 } }));
    try testing.expect(!grid.has_elem(TestPos{ .data = .{ 0, 3 } }));
    try testing.expect(!grid.has_elem(TestPos{ .data = .{ -1, 0 } }));
    try testing.expect(!grid.has_elem(TestPos{ .data = .{ 0, -1 } }));
}

test "Array2D: to_linear_index / from_linear_index roundtrip" {
    const size = TestPos{ .data = .{ 4, 3 } };
    const Grid = Array2D(i32, size);
    var grid = Grid.init(0);
    const pos = TestPos{ .data = .{ 2, 1 } };
    const idx = grid.to_linear_index(pos);
    const recovered = grid.from_linear_index(idx);
    try testing.expect_equal(pos.data[0], recovered.data[0]);
    try testing.expect_equal(pos.data[1], recovered.data[1]);
}

test "DynamicArray2D: init fills all cells" {
    const Grid = DynamicArray2D(i32, TestPos);
    const grid = Grid.init(test_allocator, 5, TestPos{ .data = .{ 4, 3 } });
    defer test_allocator.free(grid.storage);
    for (grid.storage) |v| try testing.expect_equal(@as(i32, 5), v);
}

test "DynamicArray2D: set / get / read" {
    const Grid = DynamicArray2D(i32, TestPos);
    var grid = Grid.init(test_allocator, 0, TestPos{ .data = .{ 4, 3 } });
    defer test_allocator.free(grid.storage);
    const pos = TestPos{ .data = .{ 2, 1 } };
    _ = grid.set(pos, 42);
    try testing.expect_equal(@as(i32, 42), grid.read(pos));
    try testing.expect_equal(@as(i32, 42), grid.get(pos).*);
}

test "DynamicArray2D: set does not clobber neighbours" {
    const Grid = DynamicArray2D(i32, TestPos);
    var grid = Grid.init(test_allocator, 0, TestPos{ .data = .{ 4, 3 } });
    defer test_allocator.free(grid.storage);
    _ = grid.set(TestPos{ .data = .{ 1, 1 } }, 99);
    try testing.expect_equal(@as(i32, 0), grid.read(TestPos{ .data = .{ 1, 0 } }));
    try testing.expect_equal(@as(i32, 0), grid.read(TestPos{ .data = .{ 1, 2 } }));
    try testing.expect_equal(@as(i32, 0), grid.read(TestPos{ .data = .{ 0, 1 } }));
    try testing.expect_equal(@as(i32, 0), grid.read(TestPos{ .data = .{ 2, 1 } }));
}

test "DynamicArray2D: has_elem" {
    const Grid = DynamicArray2D(i32, TestPos);
    var grid = Grid.init(test_allocator, 0, TestPos{ .data = .{ 4, 3 } });
    defer test_allocator.free(grid.storage);
    try testing.expect(grid.has_elem(TestPos{ .data = .{ 0, 0 } }));
    try testing.expect(grid.has_elem(TestPos{ .data = .{ 3, 2 } }));
    try testing.expect(!grid.has_elem(TestPos{ .data = .{ 4, 0 } }));
    try testing.expect(!grid.has_elem(TestPos{ .data = .{ 0, 3 } }));
    try testing.expect(!grid.has_elem(TestPos{ .data = .{ -1, 0 } }));
    try testing.expect(!grid.has_elem(TestPos{ .data = .{ 0, -1 } }));
}

test "DynamicArray2D: to_linear_index / from_linear_index roundtrip" {
    const Grid = DynamicArray2D(i32, TestPos);
    var grid = Grid.init(test_allocator, 0, TestPos{ .data = .{ 4, 3 } });
    defer test_allocator.free(grid.storage);
    const pos = TestPos{ .data = .{ 2, 1 } };
    const idx = grid.to_linear_index(pos);
    const recovered = grid.from_linear_index(idx);
    try testing.expect_equal(pos.data[0], recovered.data[0]);
    try testing.expect_equal(pos.data[1], recovered.data[1]);
}
