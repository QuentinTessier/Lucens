const std = @import("std");
const math = @import("zmath");

pub const Camera = @This();

position: @Vector(3, f32) = .{ 0, 0, 0 },
psi: f32 = 0.0,
theta: f32 = 0.0,

pub fn getView(self: *const Camera) math.Mat {
    const eye: @Vector(4, f32) = .{ self.position[0], self.position[1], self.position[2], 1.0 };
    const focus: @Vector(4, f32) = .{
        self.position[0] + math.sin(self.theta) * math.sin(self.psi),
        self.position[1] + math.cos(self.psi),
        self.position[2] + math.cos(self.theta) * math.sin(self.psi),
    };
    const up: @Vector(4, f32) = .{ 0, 1, 0, 0 };
    return math.lookAtRh(eye, focus, up);
}

pub fn getProjection(_: *const Camera, width: f32, height: f32, fov: f32) math.Mat {
    return math.perspectiveFovRhGl(fov, width / height, 0.1, 100);
}
