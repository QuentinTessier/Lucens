const std = @import("std");
const math = @import("zmath");

pub const BoundingBox = @This();

min: [4]f32,
max: [4]f32,

pub fn init(min: [4]f32, max: [4]f32) BoundingBox {
    return .{
        .min = min,
        .max = max,
    };
}

pub fn transform(self: *const BoundingBox, matrix: math.Mat) BoundingBox {
    return BoundingBox{
        .min = math.mul(matrix, @Vector(4, f32){ self.min[0], self.min[1], self.min[2], 1.0 }),
        .max = math.mul(matrix, @Vector(4, f32){ self.max[0], self.max[1], self.min[2], 1.0 }),
    };
}

pub fn sphere_collision_test(self: *const BoundingBox, center: [3]f32, radius: f32) bool {
    const simd_max: @Vector(4, f32) = self.max;
    const simd_min: @Vector(4, f32) = self.min;
    const simd_center: @Vector(4, f32) = .{ center[0], center[1], center[2], 1.0 };

    const xyz = @max(simd_min, @min(simd_center, simd_max));
    const distance = @sqrt((xyz[0] - center[0]) * (xyz[0] - center[0]) +
        (xyz[1] - center[1]) * (xyz[1] - center[1]) +
        (xyz[2] - center[2]) * (xyz[2] - center[2]));

    return distance < radius;
}
