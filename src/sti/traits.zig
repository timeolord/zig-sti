const std = @import("std");
const sti = @import("sti");

const Self: type = struct {
    __oogly_googly_my_boggles_are_boogly: i1,
};

const TraitFn = struct {
    name: [:0]const u8,
    F: type,
};

fn is_type_self(T: type) bool {
    return T == Self;
}

fn assert_type_equal(T: type, S: type) void {
    if (T != S) {
        @compileError("Type mismatch: expected " ++ @typeName(T) ++ ", found " ++ @typeName(S));
    }
}

fn assert_pointer_same(a: std.builtin.Type.Pointer, b: std.builtin.Type.Pointer) void {
    if (a.is_const and !b.is_const) {
        @compileError("Should be a const pointer");
    }
    if (a.size != b.size) {
        @compileError("Different pointer sizes");
    }
    if ((a.sentinel_ptr == null) != (b.sentinel_ptr == null)) {
        @compileError("Different pointer sentinelness");
    } else if (a.sentinel_ptr != null) {
        if (!sti.meta.eql(a.sentinel(), b.sentinel())) {
            @compileError("Different sentinel terminators");
        }
    }
}

// supports Self, *Self, and *const Self
fn assert_type_equal_mod_self(T: type, S: type, WouldBeSelf: type) void {
    const ti = @typeInfo(T);
    const si = @typeInfo(S);

    if (is_type_self(T)) {
        assert_type_equal(WouldBeSelf, S);
        return;
    }

    if (ti == .pointer and si == .pointer) {
        if (is_type_self(ti.pointer.child)) {
            assert_pointer_same(ti.pointer, si.pointer);
            assert_type_equal(WouldBeSelf, si.pointer.child);
            return;
        }
    }

    assert_type_equal(T, S);
}

pub const Trait = struct {
    name: [:0]const u8,
    required_functions: []const TraitFn,

    pub inline fn assert_impl(self: @This(), tp: anytype) void {
        comptime {
            const S = @TypeOf(tp);
            switch (@typeInfo(S)) {
                .@"enum", .@"union", .@"struct" => {},
                else => @compileError("expected a enum, union, or struct."),
            }

            if (!@hasDecl(S, "impl")) {
                @compileError(@typeName(S) ++ " does not impl any traits.");
            }

            for (S.impl) |impl| {
                if (std.mem.eql(u8, self.name, @tagName(impl))) {
                    break;
                }
            } else @compileError(@typeName(S) ++ " must declare it implements the trait " ++ self.name ++ ".");

            for (self.required_functions) |func| {
                if (!@hasDecl(S, func.name)) {
                    @compileError(@typeName(S) ++ " does not implement " ++ func.name ++ " (must be pub).");
                }

                const fi = @typeInfo(func.F).@"fn";
                const ii = @typeInfo(@TypeOf(@field(S, func.name))).@"fn";

                if (fi.params.len != ii.params.len) {
                    @compileError("Different argument count");
                }

                for (fi.params, ii.params) |fp, ip| {
                    if (fp.type == null and ip.type == null) {
                        continue;
                    }
                    assert_type_equal_mod_self(fp.type.?, ip.type.?, S);
                }
                if (fi.return_type != null or ii.return_type != null) {
                    if (fi.return_type == null or ii.return_type == null) {
                        @compileError("Only one function returns");
                    }
                    assert_type_equal_mod_self(fi.return_type.?, ii.return_type.?, S);
                }
            }
        }
    }
};

pub fn Indexable(T: type) Trait {
    return comptime Trait{
        .name = "indexable",
        .required_functions = &.{
            .{
                .name = "get",
                .F = fn (Self, usize) T,
            },
            .{
                .name = "get_mut",
                .F = fn (*Self, usize) *T,
            },
        },
    };
}
