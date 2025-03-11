const std = @import("std");
const glfw = @import("zglfw");
const Lucens = @import("../lucens.zig");

pub const WindowingModule = @This();

base: Lucens.LucensModule,
window: *glfw.Window,

pub const init_base: Lucens.LucensModule = .{
    .name = @typeName(@This()),
    .user_init = &WindowingModule.init,
    .user_deinit = &WindowingModule.deinit,
};

pub fn init(base: *Lucens.LucensModule, _: std.mem.Allocator) anyerror!void {
    const self = base.as(WindowingModule);
    try glfw.init();

    glfw.windowHint(.context_version_major, 4);
    glfw.windowHint(.context_version_minor, 6);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    self.window = try glfw.Window.create(1280, 720, "Lucens - No Customization", null);
    glfw.makeContextCurrent(self.window);
}

pub fn deinit(base: *Lucens.LucensModule) void {
    const self = base.as(WindowingModule);
    self.window.destroy();
    glfw.terminate();
}

pub fn onFrameStart(base: *Lucens.LucensModule) void {
    const self = base.as(WindowingModule);
    if (self.window.shouldClose()) {
        Lucens.LucensEngineStop();
    }

    glfw.pollEvents();
}

pub fn onFrameEnd(base: *Lucens.LucensModule) void {
    const self = base.as(WindowingModule);
    glfw.swapBuffers(self.window);
}
