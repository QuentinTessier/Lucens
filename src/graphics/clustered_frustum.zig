const std = @import("std");
const zmath = @import("zmath");
const FrustumCorner = @import("../3D/Frustum.zig").FrustumCorner;
const BoundingBox = @import("../3D/BoundingBox.zig");

pub const ClusteredFrustum = @This();

pub const Frustum = struct {
    near: f32,
    far: f32,
    fov: f32,
    aspect: f32,
};

pub const Cluster = struct {
    bounds: BoundingBox,
};

grid_size: [3]u32,
clusters: std.MultiArrayList(Cluster),

pub fn init(
    allocator: std.mem.Allocator,
    frustum: *const Frustum,
    grid_size: [3]u32,
) !ClusteredFrustum {
    const total_size: usize = @intCast(@reduce(.Mul, grid_size));
    var clusters: std.MultiArrayList(Cluster) = .empty;
    clusters.ensureUnusedCapacity(allocator, total_size);

    for (0..@intCast(grid_size[2])) |z| {
        const t0 = @as(f32, @intFromFloat(z)) / @as(f32, @intFromFloat(grid_size[3]));
        const t1 = @as(f32, @intFromFloat(z + 1)) / @as(f32, @intFromFloat(grid_size[3]));

        const near = frustum.near * std.math.pow(f32, frustum.far / frustum.near, t0);
        const far = frustum.near * std.math.pow(f32, frustum.far / frustum.near, t1);

        const near_h = 2.0 * @tan(frustum.fov * 0.5) * near;
        const near_w = near_h * frustum.aspect;
        const far_h = 2.0 * @tan(frustum.fov * 0.5) * far;
        const far_w = far_h * frustum.aspect;

        for (0..@intCast(grid_size[1])) |y| {
            const yMin0 = -near_h * 0.5 + near_h * (@as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(grid_size[1])));
            const yMax0 = -near_h * 0.5 + near_h * (@as(f32, @floatFromInt(y + 1)) / @as(f32, @floatFromInt(grid_size[1])));
            const yMin1 = -far_h * 0.5 + far_h * (@as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(grid_size[1])));
            const yMax1 = -far_h * 0.5 + far_h * (@as(f32, @floatFromInt(y + 1)) / @as(f32, @floatFromInt(grid_size[1])));

            for (0..@intCast(grid_size[0])) |x| {
                const xMin0 = -near_w * 0.5 + near_w * (@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(grid_size[0])));
                const xMax0 = -near_w * 0.5 + near_w * (@as(f32, @floatFromInt(x + 1)) / @as(f32, @floatFromInt(grid_size[0])));
                const xMin1 = -far_w * 0.5 + far_w * (@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(grid_size[0])));
                const xMax1 = -far_w * 0.5 + far_w * (@as(f32, @floatFromInt(x + 1)) / @as(f32, @floatFromInt(grid_size[0])));

                try clusters.append(allocator, .{ .bounds = .{ .min = .{
                    @min(xMin0, xMin1),
                    @min(yMin0, yMin1),
                    near,
                }, .max = .{
                    @max(xMax0, xMax1),
                    @max(yMax0, yMax1),
                    far,
                } } });
            }
        }
    }

    return .{
        .grid_size = grid_size,
        .clusters = clusters,
    };
}
