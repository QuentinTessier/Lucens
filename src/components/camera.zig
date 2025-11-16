const std = @import("std");
const zmath = @import("zmath");

// TODO: The target could be a framebuffer
pub const Camera = @This();

local_transform: zmath.Mat,
fov: f32,
target_width: u32,
target_height: u32,
near: f32,
far: f32,

pub fn lookAt(self: *const Camera, world_transform: zmath.Mat) zmath.Mat {
    const local_orientation: @Vector(4, f32) = .{ 0, 0, 1, 0 };
    const transformed_local_orientation = zmath.mul(self.local_transform, local_orientation);
    const world_orientation = zmath.mul(world_transform, transformed_local_orientation);
    const world_position: @Vector(4, f32) = world_transform[3];
    return zmath.lookToRh(world_position, world_orientation, .{ 0, 1, 0, 0 });
}

pub fn projection(self: *const Camera) zmath.Mat {
    const aspect_ratio: f32 = @as(f32, @floatFromInt(self.target_height)) / @as(f32, @floatFromInt(self.target_width));
    return zmath.perspectiveFovRhGl(self.fov, aspect_ratio, self.near, self.far);
}
