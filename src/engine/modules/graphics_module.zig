const std = @import("std");
const Inlucere = @import("Inlucere");
pub const gl = Inlucere.gl;
const glfw = @import("zglfw");
const WindowPayload = @import("./window_module.zig").ObserverEvents;

pub const name = .graphics;

pub const Components = .{};

pub fn Module(comptime Storage: type) type {
    return struct {
        pub fn Context() type {
            return void;
        }

        pub fn Events() type {
            // return .{ Event1, Event2, Event3 };
            return .{};
        }
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
