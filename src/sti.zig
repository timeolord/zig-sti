const std = @import("std");

pub const Memory = @import("sti/memory.zig");
pub const ArrayList = @import("sti/array_list.zig").ArrayList;
pub const HashMap = @import("sti/hashmap.zig").HashMap;
pub const EnumVector = @import("sti/bitvector.zig").EnumVector;
pub const EnumBitVector = @import("sti/bitvector.zig").EnumBitvector;
pub const Array2D = @import("sti/storage.zig").Array2D;
pub const DynamicArray2D = @import("sti/storage.zig").DynamicArray2D;
pub const Chunks = @import("sti/storage.zig").Chunks;
pub const serialize = @import("sti/serialize.zig");
pub const traits = @import("sti/traits.zig");
pub const debug = @import("sti/debug.zig");
pub const format = @import("sti/format.zig");
pub const meta = @import("sti/meta.zig");
pub const testing = @import("sti/testing.zig");

const Allocator = Memory.Allocator;

pub const assert = std.debug.assert;
pub const Timer = std.time.Timer;
pub const Random = std.Random;
pub const AutoArrayHashMap = std.AutoArrayHashMap;
pub const DynLib = std.DynLib;

pub fn append_fmt(allocator: Allocator, string: *ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const s = try fmt.allocPrint(allocator.to_std(), format, args);
    defer allocator.free(s);
    try string.extend_from_slice(allocator, s);
}

pub const log = std.log;
pub const fs = std.fs;
pub const math = std.math;
pub const io = std.io;
