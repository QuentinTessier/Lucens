const std = @import("std");
const Light = @import("3D/Light.zig");
const zmath = @import("zmath");

pub fn generate_n_point_lights(allocator: std.mem.Allocator, rng: std.Random, n: usize, min: [3]f32, max: [3]f32) ![]Light.Light {
    var lights: std.array_list.Aligned(Light.Light, null) = try .initCapacity(allocator, n);

    for (0..n) |_| {
        const point: Light.PointLight = .{
            .color = .{ rng.float(f32), rng.float(f32), rng.float(f32) },
            .radius = 10.0,
            .intensity = 100.0,
            .position = .{
                min[0] + (max[0] - min[0]) * rng.float(f32),
                min[1] + (max[1] - min[1]) * rng.float(f32),
                min[2] + (max[2] - min[2]) * rng.float(f32),
            },
        };
        const l = point.toLight();
        lights.appendAssumeCapacity(l);
    }

    return lights.toOwnedSlice(allocator);
}
