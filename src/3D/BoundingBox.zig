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
