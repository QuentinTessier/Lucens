const std = @import("std");
const builtin = @import("builtin");
const ecez = @import("ecez");
const LucensEngine = @import("lucens.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var engine: LucensEngine = undefined;
    try engine.init(allocator, .{});
    defer engine.deinit();

    try engine.run();
}
