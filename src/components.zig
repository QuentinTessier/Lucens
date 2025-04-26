const std = @import("std");
const math = @import("zmath");

const Components = @This();

pub const Transform = struct {
    position: [3]f32,
    rotation: [3]f32,
    scale: [3]f32,

    cached_matrix: math.Mat,

    pub fn computeMatrix(self: *Transform) math.Mat {
        const translation = math.translationV(math.Vec{ self.position[0], self.position[1], self.position[2], 1.0 });
        const rotation = math.matFromRollPitchYawV(math.Vec{ self.rotation[0], self.rotation[1], self.rotation[2], 1.0 });
        const scale = math.scalingV(math.Vec{ self.scale[0], self.scale[1], self.scale[2], 1.0 });

        const matrix = math.mul(translation, math.mul(rotation, scale));
        self.cached_matrix = matrix;
        return self.cached_matrix;
    }

    pub fn getMatrix(self: *Transform) math.Mat {
        return self.cached_matrix;
    }
};

pub const Material = struct {
    base_color: [4]f32,
};

pub const MeshID = struct {
    id: u32,
};
