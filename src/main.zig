const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("zglfw");
const Inlucere = @import("Inlucere");
const Mesh = @import("./3D/Mesh.zig");

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

    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.context_version_major, 4);
    glfw.windowHint(.context_version_minor, 6);
    const window = try glfw.Window.create(600, 600, "zig-gamedev: minimal_glfw_gl", null);
    glfw.makeContextCurrent(window);
    try Inlucere.init(glfw.getProcAddress);
    var device: Inlucere.Device = undefined;
    defer {
        device.deinit();
        Inlucere.deinit();
        window.destroy();
    }

    try device.init(allocator);

    var mesh = try Mesh.initFromObj(allocator, "./suzanne.obj");
    defer mesh.deinit(allocator);

    while (!window.shouldClose()) {
        glfw.pollEvents();

        window.swapBuffers();
    }
}
