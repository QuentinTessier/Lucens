const std = @import("std");
const builtin = @import("builtin");
const ecez = @import("ecez");
const Application = @import("application.zig").Application;
const glfw = @import("zglfw");
const WindowModule = @import("engine/modules/window_module.zig");
const GraphicsModule = @import("engine/modules/graphics_module.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

const LucensApplication = Application(.{ WindowModule, GraphicsModule });

pub fn run(self: *LucensApplication) !void {
    const window_module: *WindowModule.Context = @field(self.modules, @tagName(WindowModule.name));
    try window_module.observer.add_listener(
        self.allocator,
        @field(self.modules, @tagName(GraphicsModule.name)),
        @ptrCast(&GraphicsModule.Context.on_window_event),
    );

    GraphicsModule.gl.clearColor(1.0, 0.0, 0.0, 1.0);
    while (!window_module.window.shouldClose()) {
        window_module.poll_events();

        GraphicsModule.gl.clear(GraphicsModule.gl.COLOR_BUFFER_BIT);
        window_module.swap_buffers();
    }
}

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

    var app: LucensApplication = undefined;
    try app.init(allocator, run, .{
        .{&.{
            .title = "lucens test application",
            .width = 600,
            .height = 600,
        }},
        .{},
    });
    defer app.deinit();

    try app.run();
}
