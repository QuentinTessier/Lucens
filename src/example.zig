const std = @import("std");
const Mesh = @import("3D/Mesh.zig");
const Inlucere = @import("Inlucere");
const StagingBuffer = @import("graphics/staging_buffer_manager.zig");
const MeshPipeline = @import("graphics/mesh_pipeline.zig");
const MeshManagerGeneric = @import("graphics/mesh_buffer_manager.zig").MeshManager;
const MeshManager = MeshManagerGeneric(u32, Mesh.Vertex);

pub fn upload_mesh(allocator: std.mem.Allocator, mesh_manager: *MeshManager, staging_buffer: *StagingBuffer, handle: u32, mesh: *const Mesh) !?MeshManager.MeshHandle {
    std.log.info("Uploading mesh {}", .{handle});
    var vertices: std.array_list.Aligned(Mesh.Vertex, null) = try .initCapacity(allocator, mesh.normals.len);
    defer vertices.deinit(allocator);
    for (mesh.positions, mesh.normals, mesh.tangents, mesh.texCoords) |pos, norm, tang, tex| {
        vertices.appendAssumeCapacity(.{
            .position = .{ pos[0], pos[1], pos[2], 1.0 },
            .normal = .{ norm[0], norm[1], norm[2], 1.0 },
            .tangent = .{ tang[0], tang[1], tang[2], 1.0 },
            .texCoord = .{ tex[0], tex[1] },
        });
    }

    return mesh_manager.alloc(
        allocator,
        handle,
        vertices.items,
        mesh.indices,
        staging_buffer,
    );
}

pub fn create_vertex_array() Inlucere.Device.VertexArrayObject {
    var vao: Inlucere.Device.VertexArrayObject = undefined;
    vao.init(&.{ .vertexAttributeDescription = &.{
        .{
            .location = 0,
            .binding = 0,
            .inputType = .vec4,
        },
        .{
            .location = 1,
            .binding = 0,
            .inputType = .vec4,
        },
        .{
            .location = 2,
            .binding = 0,
            .inputType = .vec4,
        },
        .{
            .location = 3,
            .binding = 0,
            .inputType = .vec2,
        },
    } });
    return vao;
}
