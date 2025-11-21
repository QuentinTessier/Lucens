const std = @import("std");
const builtin = @import("builtin");
const ecez = @import("ecez");
const zmath = @import("zmath");
const ModuleCollection = @import("engine/module_collection.zig").ModuleCollection;
const Application = @import("application.zig").Application;
const glfw = @import("zglfw");
const WindowModule = @import("engine/modules/window_module.zig");
const GraphicsModule = @import("engine/modules/graphics_module.zig");
const DefaultComponents = @import("engine/modules/default_components.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub const Modules = ModuleCollection(.{
    DefaultComponents,
    WindowModule,
    GraphicsModule,
});

const AllComponents = Modules.GatherAllComponents();
const Storage = Modules.StorageType(AllComponents);

const LucensApplication = Application(.{ DefaultComponents, WindowModule, GraphicsModule });

pub fn run(self: *LucensApplication) !void {
    const window_module: *WindowModule.Context = @field(self.modules, @tagName(WindowModule.name));
    try window_module.observer.add_listener(
        self.allocator,
        @field(self.modules, @tagName(GraphicsModule.name)),
        @ptrCast(&GraphicsModule.Context.on_window_event),
    );

    _ = try self.storage.createEntity(.{
        DefaultComponents.WorldTransform{ .matrix = zmath.identity() },
    });

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
