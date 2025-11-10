const std = @import("std");
const zmath = @import("zmath");

pub const WorldTransform = @This();

matrix: zmath.Mat,

pub fn identity() WorldTransform {
    return .{
        .matrix = zmath.identity(),
    };
}

pub fn init(translation: [3]f32, rotation: [3]f32, scale: [3]f32) WorldTransform {
    const scaling = zmath.scaling(scale[0], scale[1], scale[2]);
    const rotate = zmath.mul(
        zmath.rotationX(rotation[0]),
        zmath.mul(
            zmath.rotationX(rotation[1]),
            zmath.rotationX(rotation[2]),
        ),
    );
    const translate = zmath.translation(translation[0], translation[1], translation[2]);

    return zmath.mul(rotate, zmath.mul(scaling, translate));
}
