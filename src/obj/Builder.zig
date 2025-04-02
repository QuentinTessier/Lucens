const std = @import("std");
const Vertex = @import("./MultiObjectParser.zig").Vertex;
const Triangle = @import("./MultiObjectParser.zig").Triangle;

pub const Builder = @This();

pub const BuildResult = struct {
    positions: [][3]f32,
    texCoords: [][2]f32,
    normals: [][3]f32,
    tangent: ?[][3]f32 = null,
    indices: []u32,
};

pub const BuildInput = struct {
    positions: []const [3]f32,
    texCoords: []const [2]f32,
    normals: []const [3]f32,
    triangles: []const Triangle,
};

pub fn build(allocator: std.mem.Allocator, input: BuildInput, buildTangent: bool) !BuildResult {
    // TODO: Add tangent computing
    _ = buildTangent;
    var vertexSet = std.AutoArrayHashMapUnmanaged(Vertex, void){};
    defer vertexSet.deinit(allocator);

    for (input.triangles) |triangle| {
        try vertexSet.put(allocator, triangle.vertices[0], void{});
        try vertexSet.put(allocator, triangle.vertices[1], void{});
        try vertexSet.put(allocator, triangle.vertices[2], void{});
    }

    var newPositions = try allocator.alloc([3]f32, vertexSet.count());
    var newTexCoords = try allocator.alloc([2]f32, vertexSet.count());
    var newNormals = try allocator.alloc([3]f32, vertexSet.count());

    for (vertexSet.keys(), 0..) |face, i| {
        newPositions[i] = input.positions[@as(usize, @intCast(face.position)) - 1];
        newTexCoords[i] = input.texCoords[@as(usize, @intCast(face.texCoords)) - 1];
        newNormals[i] = input.normals[@as(usize, @intCast(face.normal)) - 1];
    }

    var indices = try allocator.alloc(u32, input.triangles.len * 3);
    for (input.triangles, 0..) |triangle, i| {
        const index0 = vertexSet.getIndex(triangle.vertices[0]) orelse unreachable;
        const index1 = vertexSet.getIndex(triangle.vertices[1]) orelse unreachable;
        const index2 = vertexSet.getIndex(triangle.vertices[2]) orelse unreachable;

        indices[i * 3 + 0] = @intCast(index0);
        indices[i * 3 + 1] = @intCast(index1);
        indices[i * 3 + 2] = @intCast(index2);
    }

    const result: BuildResult = .{
        .positions = newPositions,
        .texCoords = newTexCoords,
        .normals = newNormals,
        .indices = indices,
    };
    return result;
}
