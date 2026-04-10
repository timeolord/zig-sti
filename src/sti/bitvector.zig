const std = @import("std");

pub fn EnumVector(comptime OuterEnum: type, comptime InnerType: type, comptime default: InnerType) type {
    const enum_fields = switch (@typeInfo(OuterEnum)) {
        .@"enum" => |e| e.fields,
        .@"union" => |u| @typeInfo(u.tag_type orelse @compileError("union must be tagged")).@"enum".fields,
        else => @compileError("should be enum or union"),
    };
    for (enum_fields, 0..) |f, i| {
        if (f.value != i)
            @compileError("cannot create enum bitvector with out of order tags");
    }

    const CreateTagType = blk: {
        // @compileLog("doing now the " ++ @typeName(InnerType));
        var fields = [_]std.builtin.Type.StructField{undefined} ** enum_fields.len;

        for (&fields, 0..) |*f, i| {
            f.* = .{
                .name = enum_fields[i].name,
                .type = InnerType,
                .default_value_ptr = &default,
                .is_comptime = false,
                .alignment = @alignOf(InnerType),
            };
            // @compileLog("index at " ++ enum_fields[i].name);
        }

        break :blk @Type(.{ .@"struct" = .{
            .layout = .auto,
            .decls = &[_]std.builtin.Type.Declaration{},
            .fields = &fields,
            .is_tuple = false,
        } });
    };

    return struct {
        const Self = @This();
        inners: [enum_fields.len]InnerType,

        pub inline fn get(self: Self, tag: OuterEnum) InnerType {
            const index: usize = @intFromEnum(tag);
            return self.inners[index];
        }

        pub inline fn set(self: *Self, tag: OuterEnum, val: InnerType) void {
            const index: usize = @intFromEnum(tag);
            self.inners[index] = val;
        }

        pub inline fn create(tags: CreateTagType) Self {
            const fields = @typeInfo(@TypeOf(tags)).@"struct".fields;

            var me = Self{
                .inners = [_]InnerType{default} ** enum_fields.len,
            };

            inline for (fields) |f| {
                const index: usize = @intFromEnum(@field(OuterEnum, f.name));
                me.inners[index] = @as(InnerType, @field(tags, f.name));
            }

            return me;
        }
    };
}

pub fn EnumBitvector(comptime T: type) type {
    const enum_fields = @typeInfo(T).@"enum".fields;
    for (enum_fields, 0..) |f, i| {
        if (f.value != i)
            @compileError("cannot create enum bitvector with out of order tags");
    }

    const Bv: type = @Type(.{ .int = .{
        .signedness = .unsigned,
        .bits = enum_fields.len,
    } });

    return packed struct {
        const Self = @This();
        bv: Bv,

        pub const none = Self{ .bv = 0 };
        pub const all = Self{ .bv = ~@as(Bv, 0) };

        pub inline fn has_tag(bits: Self, tag: T) bool {
            const mask: Bv = @as(Bv, 1) << @intFromEnum(tag);
            return bits.bv & mask == mask;
            // _ = bits;
            // _ = tag;
            // return true;
        }

        pub inline fn has_tags(bits: Self, tags: anytype) bool {
            const mask = comptime blk: {
                const fields = @typeInfo(@TypeOf(tags)).@"struct".fields;

                var mask: Bv = 0;
                for (fields) |f| {
                    mask |= @as(Bv, 1) << @intFromEnum(@as(T, @field(tags, f.name)));
                }
                break :blk mask;
            };

            return bits.bv & mask == mask;
        }

        pub inline fn create(tags: anytype) Self {
            switch (@typeInfo(@TypeOf(tags))) {
                .@"struct" => |s| {
                    const fields = s.fields;

                    var mask: Bv = 0;
                    inline for (fields) |f| {
                        mask |= @as(Bv, 1) << @intFromEnum(@as(T, @field(tags, f.name)));
                    }
                    return .{ .bv = mask };
                },
                .enum_literal => {
                    return .{ .bv = @as(Bv, 1) << @intFromEnum(@as(T, tags)) };
                },
                else => @compileError("can't create a bitvector like that big dawg"),
            }
        }

        pub inline fn create_not(tags: anytype) Self {
            return .{
                .bv = ~Self.create(tags).bv,
            };
        }

        pub inline fn set(bits: *Self, tag: T, value: bool) void {
            const mask: Bv = @as(Bv, 1) << @intFromEnum(tag);
            if (value) {
                bits.bv |= mask;
            } else {
                bits.bv &= ~mask;
            }
        }

        pub inline fn not(self: Self) Self {
            return .{ .bv = ~self.bv };
        }

        pub inline fn has_all(self: Self) bool {
            return ~self.bv == 0;
        }
    };
}
