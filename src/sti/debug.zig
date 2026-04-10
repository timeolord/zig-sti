const time = @cImport({
    @cInclude("time.h");
});

const std = @import("std");

const constants = @import("constants");

var hooks: constants.DebugHooks = undefined;

pub fn load_hooks(debug_hooks: constants.DebugHooks) void {
    hooks = debug_hooks;
}

pub fn print(comptime format: []const u8, args: anytype) void {
    var buffer: [64]u8 = undefined;

    const output = hooks.lock_io(&buffer, buffer.len);
    defer hooks.unlock_io();

    const raw_time: time.time_t = time.time(null);
    const current_time = time.localtime(&raw_time);
    const buffer_len = comptime 9;
    var c_time_buffer: [buffer_len]u8 = undefined;
    const c_time_len = time.strftime(&c_time_buffer, buffer_len, "%T", current_time);

    nosuspend output.print("DEBUG [{s}]: ", .{c_time_buffer[0..c_time_len]}) catch {};
    nosuspend output.print(format, args) catch return;
}

pub fn panic(comptime format: []const u8, args: anytype) noreturn {
    print(format, args);
    @panic("");
}

pub inline fn todo() noreturn {
    print("Not implemented\n", .{});
    @panic("");
}

pub fn lock_stderr_writer(buffer: []u8) *std.io.Writer {
    return std.debug.lockStderrWriter(buffer);
}

pub fn unlock_stderr_writer() void {
    return std.debug.unlockStderrWriter();
}
