const std = @import("std");
const zmath = @import("zmath");

pub const Transform = @This();

position: [3]f32,
scale: [3]f32,
rotation: zmath.Quat,

pub const identity: Transform = .{
    .position = .{ 0, 0, 0 },
    .scale = .{ 1, 1, 1 },
    .rotation = zmath.qidentity(),
};

pub fn to_matrix(self: *const Transform, matrix: *zmath.Mat) void {
    const rotation = zmath.quatToMat(self.rotation);
    const scale = zmath.scaling(self.scale[0], self.scale[1], self.scale[2]);
    const translation = zmath.translation(self.position[0], self.position[1], self.position[2]);

    matrix.* = zmath.mul(zmath.mul(rotation, scale), translation);
}
