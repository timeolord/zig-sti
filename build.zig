const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sti = b.addModule("sti", .{
        .root_source_file = b.path("src/sti.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sti.addImport("sti", sti);

    const lib = b.addLibrary(.{
        .name = "sti",
        .root_module = sti,
    });
    b.installArtifact(lib);

    const sti_tests = b.addTest(.{
        .name = "sti-tests",
        .root_module = sti,
    });
    const run_sti_tests = b.addRunArtifact(sti_tests);

    const test_step = b.step("test", "run unit tests");
    test_step.dependOn(&run_sti_tests.step);

    const check_step = b.step("check", "check that sti compiles");
    check_step.dependOn(&lib.step);
    check_step.dependOn(&sti_tests.step);
}
