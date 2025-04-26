const std = @import("std");
const zmath = @import("zmath");
const OBJ = @import("../obj/root.zig");
const BoundingBox = @import("BoundingBox.zig");

pub const Mesh = @This();

positions: [][3]f32,
normals: [][3]f32,
tangents: [][3]f32,
texCoords: [][2]f32,
indices: []u32,
bounds: BoundingBox,

pub const Vertex = extern struct {
    position: [4]f32,
    normal: [4]f32,
    tangent: [4]f32,
    texCoord: [2]f32,
};

// Takes ownership of the given arrays
pub fn init(indices: []u32, vertices: struct {
    positions: [][3]f32,
    normals: [][3]f32,
    tangents: [][3]f32,
    texCoords: [][2]f32,
}) Mesh {
    return Mesh{
        .positions = vertices.positions,
        .normals = vertices.normals,
        .tangents = vertices.tangents,
        .texCoords = vertices.texCoords,
        .indices = indices,
    };
}

pub fn deinit(self: *Mesh, allocator: std.mem.Allocator) void {
    allocator.free(self.positions);
    allocator.free(self.normals);
    allocator.free(self.tangents);
    allocator.free(self.texCoords);
    allocator.free(self.indices);
}

pub fn initFromObj(allocator: std.mem.Allocator, path: []const u8) !Mesh {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const size = try file.getEndPos();

    const content = try file.readToEndAlloc(allocator, size);
    defer allocator.free(content);

    var res = try OBJ.MultiObjectParser.parse(allocator, content);
    defer res.deinit(allocator);

    if (res.objects.len == 0) {
        return error.FailedToParseMesh;
    }

    const built = try OBJ.Buidler.build(allocator, .{
        .normals = res.normals,
        .positions = res.positions,
        .texCoords = res.texcoords,
        .triangles = res.objects[0].triangles,
    }, false);
    return Mesh{
        .positions = built.positions,
        .normals = built.normals,
        .texCoords = built.texCoords,
        .indices = built.indices,
        .tangents = try buildTangents(allocator, built.positions, built.texCoords, built.indices),
        .bounds = computeBounds(built.positions),
    };
}

fn computeTangent(positions: [][3]f32, texCoords: [][2]f32, indices: []u32, targetVertex: u32) [3]f32 {
    var tangent: @Vector(3, f32) = .{ 0, 0, 0 };
    var triangleIncluded: u32 = 0;

    var index: usize = 0;
    while (index < indices.len) : (index += 3) {
        const index0 = indices[index + 0];
        const index1 = indices[index + 1];
        const index2 = indices[index + 2];

        if (index0 == targetVertex or index1 == targetVertex or index2 == targetVertex) {
            const pos0: @Vector(3, f32) = positions[@intCast(index0)];
            const pos1: @Vector(3, f32) = positions[@intCast(index1)];
            const pos2: @Vector(3, f32) = positions[@intCast(index2)];

            const uv0: @Vector(2, f32) = texCoords[@intCast(index0)];
            const uv1: @Vector(2, f32) = texCoords[@intCast(index1)];
            const uv2: @Vector(2, f32) = texCoords[@intCast(index2)];

            const delta_pos1 = pos1 - pos0;
            const delta_pos2 = pos2 - pos0;

            const delta_uv1 = uv1 - uv0;
            const delta_uv2 = uv2 - uv0;

            const r: @Vector(3, f32) = @splat(1.0 / (delta_uv1[0] * delta_uv2[1] - delta_uv1[1] * delta_uv2[0]));
            tangent += (delta_pos1 * @as(@Vector(3, f32), @splat(delta_uv2[1])) - delta_pos2 * @as(@Vector(3, f32), @splat(delta_uv1[1]))) * r;
            triangleIncluded += 1;
        }
    }

    if (triangleIncluded > 0) {
        const fTriangleInclude: f32 = @floatFromInt(triangleIncluded);
        tangent /= @as(@Vector(3, f32), @splat(fTriangleInclude));
        const tangent4 = zmath.normalize3(.{ tangent[0], tangent[1], tangent[2], 0 });
        tangent = .{ tangent4[0], tangent4[1], tangent4[2] };
    }

    return tangent;
}

pub fn buildTangents(allocator: std.mem.Allocator, positions: [][3]f32, texCoords: [][2]f32, indices: []u32) ![][3]f32 {
    var tangents = try allocator.alloc([3]f32, positions.len);

    for (indices) |index| {
        tangents[@intCast(index)] = computeTangent(positions, texCoords, indices, index);
    }

    return tangents;
}

fn computeBounds(positions: []const [3]f32) BoundingBox {
    var min: @Vector(3, f32) = .{ std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32) };
    var max: @Vector(3, f32) = .{ std.math.floatMin(f32), std.math.floatMin(f32), std.math.floatMin(f32) };

    for (positions) |position| {
        min = @min(min, @as(@Vector(3, f32), position));
        max = @max(max, @as(@Vector(3, f32), position));
    }

    return .init(min, max);
}

pub fn getBounds(self: *const Mesh) BoundingBox {
    return self.bounds;
}
