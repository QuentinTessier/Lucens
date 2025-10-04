const std = @import("std");
const Inlucere = @import("Inlucere");
const Mesh = @import("Mesh.zig");
const SinglePoolAllocator = @import("../graphics/SinglePoolAllocator.zig").GPUSinglePoolAllocator;
const AllocationHandle = @import("../graphics/SinglePoolAllocator.zig").AllocationHandle;

pub const MeshManager = @This();

allocator: std.mem.Allocator,
gpu_vertices_allocator: SinglePoolAllocator,
gpu_indices_allocator: SinglePoolAllocator,
current_mesh_id: u32,
cpu_meshes: std.AutoHashMapUnmanaged(u32, Mesh),
gpu_meshes: std.AutoHashMapUnmanaged(u32, struct {
    vertices: AllocationHandle,
    indices: AllocationHandle,
}),

pub fn init(allocator: std.mem.Allocator) !MeshManager {
    return MeshManager{
        .allocator = allocator,
        .gpu_vertices_allocator = try .init("mesh_vertices", allocator, @sizeOf(Mesh.Vertex) * 100_000),
        .gpu_indices_allocator = try .init("mesh_indices", allocator, @sizeOf(u32) * 50_000),
        .current_mesh_id = 0,
        .cpu_meshes = .empty,
        .gpu_meshes = .empty,
    };
}

pub fn deinit(self: *MeshManager) void {
    {
        var ite = self.gpu_meshes.iterator();
        while (ite.next()) |entry| {
            self.gpu_indices_allocator.free(entry.value_ptr.indices);
            self.gpu_vertices_allocator.free(entry.value_ptr.vertices);
        }
        self.gpu_indices_allocator.deinit();
        self.gpu_vertices_allocator.deinit();
    }

    {
        var ite = self.cpu_meshes.iterator();
        while (ite.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.cpu_meshes.deinit(self.allocator);
    }
    self.gpu_meshes.deinit(self.allocator);
}

pub fn loadObj(self: *MeshManager, path: []const u8) !u32 {
    const id = self.current_mesh_id;
    self.current_mesh_id += 1;

    const mesh = try Mesh.initFromObj(self.allocator, path);
    std.log.info("Inported mesh with {} indices and {} vertices", .{ mesh.indices.len, mesh.positions.len });

    try self.cpu_meshes.put(self.allocator, id, mesh);

    return id;
}

pub fn isGPUResident(self: *const MeshManager, mesh: u32) bool {
    return self.gpu_meshes.contains(mesh);
}

pub fn makeGPUResident(self: *MeshManager, id: u32) !bool {
    if (self.cpu_meshes.get(id)) |mesh| {
        const vertices = try self.gpu_vertices_allocator.alloc(@sizeOf(Mesh.Vertex) * mesh.positions.len);
        const indices = try self.gpu_indices_allocator.alloc(@sizeOf(u32) * mesh.indices.len);

        const local_vertices = vertices.cast(Mesh.Vertex);
        for (local_vertices, mesh.positions, mesh.normals, mesh.tangents, mesh.texCoords) |*vertex, position, normal, tangent, texCoord| {
            vertex.position = .{ position[0], position[1], position[2], 0.0 };
            vertex.normal = .{ normal[0], normal[1], normal[2], 0.0 };
            vertex.tangent = .{ tangent[0], tangent[1], tangent[2], 0.0 };
            vertex.texCoord = texCoord;
        }
        vertices.flush();

        const local_indices = indices.cast(u32);
        @memcpy(local_indices, mesh.indices);
        indices.flush();

        try self.gpu_meshes.put(self.allocator, id, .{
            .indices = indices,
            .vertices = vertices,
        });
        return true;
    } else {
        return false;
    }
}

pub fn removeGPUResident(self: *MeshManager, id: u32) !bool {
    if (self.gpu_meshes.get(id)) |mesh| {
        self.gpu_vertices_allocator.free(mesh.vertices);
        self.gpu_indices_allocator.free(mesh.indices);
        self.gpu_meshes.remove(id);
        return true;
    }
    return false;
}

pub const BindingInfo = struct {
    vertices_buffer: Inlucere.Device.Buffer,
    vertices_offset: u32,
    vertices_size: u32,

    indices_buffer: Inlucere.Device.Buffer,
    indices_offset: u32,
    indices_size: u32,
};

pub fn getBindingInfo(self: *MeshManager, id: u32) ?BindingInfo {
    return if (self.gpu_meshes.get(id)) |mesh| BindingInfo{
        .vertices_buffer = mesh.vertices.allocator.gpuMemory.toBuffer(),
        .vertices_offset = mesh.vertices.offset,
        .vertices_size = mesh.vertices.size,
        .indices_buffer = mesh.indices.allocator.gpuMemory.toBuffer(),
        .indices_offset = mesh.indices.offset,
        .indices_size = mesh.indices.size,
    } else null;
}
