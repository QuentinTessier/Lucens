const std = @import("std");
const Inlucere = @import("Inlucere");
const Lucens = @import("../lucens.zig");
const glfw = @import("zglfw");

pub const InlucereModule = @This();

base: Lucens.LucensModule,
device: Inlucere.Device,

pub const init_base: Lucens.LucensModule = .{
    .name = @typeName(@This()),
    .user_init = &InlucereModule.init,
    .user_deinit = &InlucereModule.deinit,
};

pub fn init(base: *Lucens.LucensModule, allocator: std.mem.Allocator) anyerror!void {
    const self = base.as(InlucereModule);

    try Inlucere.init(glfw.getProcAddress);
    try self.device.init(allocator); // TODO: Use zig 0.14.0 way to init struct since this doesn't even need an error...
}

pub fn deinit(base: *Lucens.LucensModule) void {
    const self = base.as(InlucereModule);
    self.device.deinit();

    Inlucere.deinit();
}

pub fn forceClearSwapchain(base: *Lucens.LucensModule) void {
    const self = base.as(InlucereModule);
    self.device.clearSwapchain(.{
        .clearColor = .{ 0, 0, 0, 1 },
        .colorLoadOp = .clear,
    });
}
