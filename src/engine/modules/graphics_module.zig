const std = @import("std");
const Inlucere = @import("Inlucere");
pub const gl = Inlucere.gl;
const glfw = @import("zglfw");
const WindowPayload = @import("./window_module.zig").ObserverEvents;
pub const C1 = struct { a: u32 };

pub const components = [_]type{};

pub const name = .graphics;

pub fn Module(comptime _: type) type {
    return struct {
        pub const Context = struct {
            value: u32,

            pub const empty = @This(){ .value = 0 };
        };
    };
}

pub const Context = struct {
    pub fn on_window_event(_: *Context, payload: *const WindowPayload) void {
        switch (payload.*) {
            .resize => |resize| {
                Inlucere.gl.viewport(0, 0, @intCast(resize.width), @intCast(resize.height));
            },
            else => {},
        }
    }

    pub fn init(_: *Context, _: std.mem.Allocator) !void {
        try Inlucere.init(glfw.getProcAddress);
    }

    pub fn deinit(_: *Context, _: std.mem.Allocator) void {
        Inlucere.deinit();
    }
};
