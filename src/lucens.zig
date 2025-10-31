const std = @import("std");
const builtin = @import("builtin");
const ecez = @import("ecez");
const zglfw = @import("zglfw");
const Inlucere = @import("Inlucere");

pub const LucensEngine = @This();

pub const Components = @import("components.zig").Components;
pub const Storage = @import("components.zig").Storage;
const Scheduler = ecez.CreateScheduler(Storage, .{});
const Events = @import("events.zig");

allocator: std.mem.Allocator,
storage: Storage,
scheduler: Scheduler,
window: *zglfw.Window,

pub const Options = struct {
    screen_width: u32 = 1280,
    screen_height: u32 = 720,
};

fn framebuffer_resize_callback(window: *zglfw.Window, w: c_int, h: c_int) callconv(.c) void {
    // const engine = zglfw.getWindowUserPointer(window, LucensEngine);
    // if (engine) |self| {
    //     self.scheduler.dispatchEvent(
    //         &self.storage,
    //         Events.EventScreenResize,
    //         Events.ScreenResize{
    //             .width = @intCast(w),
    //             .height = @intCast(h),
    //         },
    //     );
    // }
    _ = window;
    _ = w;
    _ = h;
}

pub fn init(self: *LucensEngine, allocator: std.mem.Allocator, options: Options) !void {
    try zglfw.init();

    zglfw.windowHint(.context_version_major, 4);
    zglfw.windowHint(.context_version_minor, 6);
    zglfw.windowHint(.opengl_profile, .opengl_core_profile);
    if (builtin.mode == .Debug) zglfw.windowHint(.opengl_debug_context, true);
    var scheduler: Scheduler = Scheduler.uninitialized;
    try scheduler.init(.{
        .pool_allocator = allocator,
        .query_submit_allocator = allocator,
    });
    self.* = LucensEngine{
        .allocator = allocator,
        .storage = try .init(allocator),
        .scheduler = scheduler,
        .window = try zglfw.createWindow(@intCast(options.screen_width), @intCast(options.screen_height), "Lucens", null),
    };
    zglfw.makeContextCurrent(self.window);
    try Inlucere.init(zglfw.getProcAddress);

    zglfw.setWindowUserPointer(self.window, self);
    _ = zglfw.setFramebufferSizeCallback(self.window, framebuffer_resize_callback);
}

pub fn deinit(self: *LucensEngine) void {
    Inlucere.deinit();
    self.storage.deinit();
    self.scheduler.deinit();
    self.window.destroy();
    zglfw.terminate();
}

pub fn run(self: *LucensEngine) !void {
    var time: f64 = 0.0;
    const fps_target: f64 = 0.0;
    var rendering_time: f64 = fps_target;
    zglfw.setTime(0.0);
    zglfw.swapInterval(0);
    while (!self.window.shouldClose()) {
        zglfw.pollEvents();

        const new_time = zglfw.getTime();
        const delta_time = new_time - time;
        time = new_time;

        rendering_time -= delta_time;

        if (rendering_time <= 0.0) {
            rendering_time = fps_target;
        }

        self.window.swapBuffers();
    }
}
