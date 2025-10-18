const std = @import("std");
const zmath = @import("zmath");

pub const Frustum = @This();

pub const Plane = struct {
    normal: [3]f32,
    t: f32,

    pub fn init(data: [4]f32, normalize: bool) Plane {
        if (normalize) {
            const normalized = zmath.normalize4(data);
            return .{
                .normal = .{ normalized[0], normalized[1], normalized[2] },
                .t = normalized[3],
            };
        } else {
            return .{
                .normal = .{ data[0], data[1], data[2] },
                .t = data[3],
            };
        }
    }
};

left: Plane,
right: Plane,
bottom: Plane,
top: Plane,
near: Plane,
far: Plane,

pub fn init(view_proj: zmath.Mat, normalize: bool) Frustum {
    var left: [4]f32 = undefined;
    var right: [4]f32 = undefined;
    var bottom: [4]f32 = undefined;
    var top: [4]f32 = undefined;
    var near: [4]f32 = undefined;
    var far: [4]f32 = undefined;
    inline for (0..4) |i| {
        left[i] = view_proj[3][i] + view_proj[0][i];
        right[i] = view_proj[3][i] - view_proj[0][i];

        bottom[i] = view_proj[3][i] + view_proj[1][i];
        top[i] = view_proj[3][i] - view_proj[1][i];

        near[i] = view_proj[3][i] + view_proj[2][i];
        far[i] = view_proj[3][i] - view_proj[2][i];
    }

    return Frustum{
        .left = .init(left, normalize),
        .right = .init(right, normalize),
        .bottom = .init(bottom, normalize),
        .top = .init(top, normalize),
        .near = .init(near, normalize),
        .far = .init(far, normalize),
    };
}

pub const FrustumCorner = struct {
    pub const PointName = enum(u8) {
        near_top_left,
        near_top_right,
        near_bottom_left,
        near_bottom_right,
        far_top_left,
        far_top_right,
        far_bottom_left,
        far_bottom_right,
    };

    points: [8]@Vector(4, f32),

    const Arguments = struct {
        position: @Vector(4, f32),
        view_direction: @Vector(4, f32),
        up: @Vector(4, f32) = .{ 0, 1, 0, 0 },
        right: @Vector(4, f32) = .{ 1, 0, 0, 0 },
        near: f32 = 0.1,
        far: f32 = 100.0,
        fov: f32 = 45.0,
        aspect_ratio: f32 = 1280 / 720,
    };

    pub fn init(args: *const Arguments) FrustumCorner {
        const h_near = 2.0 * @tan(args.fov * 0.5) * args.near;
        const w_near = h_near * args.aspect_ratio;

        const h_far = 2.0 * @tan(args.fov * 0.5) * args.far;
        const w_far = h_far * args.aspect_ratio;

        const c_near = args.position + args.view_direction * @as(@Vector(4, f32), @splat(args.near));
        const c_far = args.position + args.view_direction * @as(@Vector(4, f32), @splat(args.far));

        var corners: FrustumCorner = undefined;

        const half_h_near: @Vector(4, f32) = @splat(h_near * 0.5);
        const half_w_near: @Vector(4, f32) = @splat(w_near * 0.5);
        const half_h_far: @Vector(4, f32) = @splat(h_far * 0.5);
        const half_w_far: @Vector(4, f32) = @splat(w_far * 0.5);
        corners.points[0] = c_near + (args.up * half_h_near) - (args.right * half_w_near);
        corners.points[1] = c_near + (args.up * half_h_near) + (args.right * half_w_near);
        corners.points[2] = c_near - (args.up * half_h_near) - (args.right * half_w_near);
        corners.points[3] = c_near - (args.up * half_h_near) + (args.right * half_w_near);

        corners.points[4] = c_far + (args.up * half_h_far) - (args.right * half_w_far);
        corners.points[5] = c_far + (args.up * half_h_far) + (args.right * half_w_far);
        corners.points[6] = c_far - (args.up * half_h_far) - (args.right * half_w_far);
        corners.points[7] = c_far - (args.up * half_h_far) + (args.right * half_w_far);

        return corners;
    }

    pub fn get_point(self: *const FrustumCorner, name: PointName) @Vector(4, f32) {
        return switch (name) {
            .near_top_left => self.points[0],
            .near_top_right => self.points[1],
            .near_bottom_left => self.points[2],
            .near_bottom_right => self.points[3],
            .far_top_left => self.points[4],
            .far_top_right => self.points[5],
            .far_bottom_left => self.points[6],
            .far_bottom_right => self.points[7],
        };
    }
};
