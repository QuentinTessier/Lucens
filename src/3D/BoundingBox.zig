const std = @import("std");
const math = @import("zmath");

pub const BoundingBox = @This();

min: [3]f32,
max: [3]f32,

pub fn init(min: [3]f32, max: [3]f32) BoundingBox {
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

const FrustumPlane = enum {
    left,
    right,
    bottom,
    top,
    near,
    far,
};

const Frustum = std.EnumArray(FrustumPlane, @Vector(4, f32));

pub fn extractFrustumPlanes(projView: math.Mat) Frustum {
    var frustum: Frustum = .initFill(.{ 0, 0, 0, 1 });
    const rowX = projView[0];
    const rowY = projView[1];
    const rowZ = projView[2];
    const rowW = projView[3];

    frustum.set(.left, math.normalize4(rowW + rowX));
    frustum.set(.right, math.normalize4(rowW - rowX));
    frustum.set(.bottom, math.normalize4(rowW + rowY));
    frustum.set(.top, math.normalize4(rowW - rowY));
    frustum.set(.near, math.normalize4(rowW + rowZ));
    frustum.set(.far, math.normalize4(rowW - rowZ));

    return frustum;
}

const FrustumCorner = enum(u32) { near_bottom_left, near_bottom_right, near_top_right, near_top_left, far_bottom_left, far_bottom_right, far_top_right, far_top_left };

pub fn extractFrustumCorners(projView: math.Mat) std.EnumArray(FrustumCorner, @Vector(4, f32)) {
    const inv = math.inverse(projView);
    var corners: [8]@Vector(4, f32) = undefined;

    var i: u32 = 0;
    var z: usize = 0;
    var y: usize = 0;
    var x: usize = 0;
    while (z <= 1) : (z += 1) {
        const clipZ = @as(f32, @floatFromInt(z)) * 2.0 - 1.0;
        while (y <= 1) : (y += 1) {
            const clipY = @as(f32, @floatFromInt(y)) * 2.0 - 1.0;
            while (x <= 1) : (x += 1) {
                const clipX = @as(f32, @floatFromInt(x)) * 2.0 - 1.0;

                const cornerClip = @Vector(4, f32){ clipX, clipY, clipZ, 1.0 };
                const cornerWorld = math.mul(inv, cornerClip);
                corners[i] = @Vector(4, f32){
                    cornerWorld[0] / cornerWorld[3],
                    cornerWorld[1] / cornerWorld[3],
                    cornerWorld[2] / cornerWorld[3],
                    1.0,
                };
                i += 1;
            }
        }
    }

    return .init(.{
        .near_bottom_left = corners[0],
        .near_bottom_right = corners[1],
        .near_top_right = corners[3],
        .near_top_left = corners[2],
        .far_bottom_left = corners[4],
        .far_bottom_right = corners[5],
        .far_top_right = corners[7],
        .far_top_left = corners[6],
    });
}

pub fn isInsideFrustum(self: *const BoundingBox, frustum: Frustum) bool {
    for (frustum.values) |plane| {
        const normal: @Vector(3, f32) = .{ plane[0], plane[1], plane[2] };

        const positive: @Vector(3, f32) = undefined;
        positive[0] = if (normal.x >= 0) self.max[0] else self.min[0];
        positive[1] = if (normal.x >= 0) self.max[0] else self.min[0];
        positive[2] = if (normal.x >= 0) self.max[0] else self.min[0];

        const distance = math.dot3(
            @Vector(4, f32){ normal[0], normal[1], normal[2], 1.0 },
            @Vector(4, f32){ positive[0], positive[1], positive[2], 1.0 },
        )[0] + plane[3];

        if (distance < 0.0) {
            return false;
        }
    }
    return true;
}
