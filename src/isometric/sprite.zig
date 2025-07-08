const std = @import("std");

pub const Size = struct {
    x: f32,
    y: f32,
};

pub const Position = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn toVec3(self: Position) @Vector(3, f32) {
        return .{ self.x, self.y, self.z };
    }

    pub fn toVec4(self: Position) @Vector(4, f32) {
        return .{ self.x, self.y, self.z, 0.0 };
    }
};
