const std = @import("std");
const glfw = @import("zglfw");
const Observer = @import("../observer.zig").Observer;

pub const name = .window;

pub const Components = .{};
pub const Events = .{};

pub const KeyEvent = struct {};

// TODO: Mouse, Keys, ...
pub const ObserverEvents = union(enum) {
    resize: struct { width: u32, height: u32 },
    focus: bool,
};

pub const Extent = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

pub const Context = struct {
    window: *glfw.Window,
    extent: Extent,
    focus_state: bool,
    observer: Observer(ObserverEvents),

    fn resize_window_event(window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
        const self: *Context = window.getUserPointer(Context) orelse return;

        self.extent.width = @intCast(width);
        self.extent.height = @intCast(height);
        self.observer.dispatch(&.{ .resize = .{
            .width = @intCast(width),
            .height = @intCast(height),
        } });
    }

    fn focus_window_event(window: *glfw.Window, focus: glfw.Bool) callconv(.c) void {
        const self: *Context = window.getUserPointer(Context) orelse return;
        self.focus_state = focus == glfw.TRUE;
        self.observer.dispatch(&.{
            .focus = self.focus_state,
        });
    }

    pub fn init(self: *Context, _: std.mem.Allocator) !void {
        try glfw.init();

        // TODO: Find a way to pass custom data to modify the version or API (vulkan maybe ..)
        glfw.windowHint(.context_version_major, 4);
        glfw.windowHint(.context_version_minor, 6);
        glfw.windowHint(.opengl_profile, .opengl_core_profile);
        self.window = try glfw.createWindow(1280, 720, "lucens", null);
        self.extent.width = 1280;
        self.extent.height = 720;
        self.extent.x = 0;
        self.extent.y = 0;
        self.focus_state = true;
        self.observer.listeners = .empty;

        self.window.setUserPointer(self);
        _ = self.window.setFramebufferSizeCallback(resize_window_event);
        _ = self.window.setFocusCallback(focus_window_event);
        glfw.makeContextCurrent(self.window);
    }

    pub fn deinit(self: *Context, allocator: std.mem.Allocator) void {
        self.window.destroy();
        self.observer.listeners.deinit(allocator);
        glfw.terminate();
    }

    pub fn poll_events(_: *const Context) void {
        glfw.pollEvents();
    }

    pub fn swap_buffers(self: *const Context) void {
        glfw.swapBuffers(self.window);
    }
};
