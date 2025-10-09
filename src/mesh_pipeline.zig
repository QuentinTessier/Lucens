const std = @import("std");
const Inlucere = @import("Inlucere");
const zmath = @import("zmath");
const MeshManager = @import("3D/MeshManager.zig");
const Mesh = @import("3D/Mesh.zig");

pub const MeshPipeline = @This();

pub const Material = extern struct {
    color: [4]f32,
};

pub const MeshInstance = extern struct {
    model_to_world: zmath.Mat,
    world_to_model: zmath.Mat,
    material_id: u32,
};

pub const MeshInstanceRange = extern struct {
    index: u32,
    count: u32,
};

pub const DrawElementsIndirectCommand = extern struct {
    count: u32,
    instanceCount: u32,
    firstIndex: u32,
    baseVertex: i32,
    baseInstance: u32,
};

fn read_file(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const size = try file.getEndPos();

    return try file.readToEndAlloc(allocator, size);
}

program: Inlucere.Device.Program,

vertex_array: Inlucere.Device.VertexArrayObject,
vertex_buffer: Inlucere.Device.Buffer,
index_buffer: Inlucere.Device.Buffer,

scene_uniform_buffer: Inlucere.Device.Buffer,
light_buffer: Inlucere.Device.Buffer,

per_instance_buffer: Inlucere.Device.MappedBuffer,
current_instance: usize = 0,
instance_range_buffer: Inlucere.Device.MappedBuffer,

command_buffer: Inlucere.Device.MappedBuffer,

current_mesh: u32,
binding_info: MeshManager.BindingInfo,

dirty: bool = false,
mesh_instances: std.AutoArrayHashMapUnmanaged(u32, struct {
    bind_info: MeshManager.BindingInfo,
    instances: std.array_list.Aligned(AddMeshData, null),
}),

// TODO: Dynamic values
pub const MeshInstanceCount: u32 = 1000;
pub const MeshInstanceRangeCount: u32 = 100;

pub const UserData = struct {
    vertex_array: Inlucere.Device.VertexArrayObject,
    vertex_buffer: Inlucere.Device.Buffer,
    index_buffer: Inlucere.Device.Buffer,
    scene_uniform_buffer: Inlucere.Device.Buffer,
    light_buffer: Inlucere.Device.Buffer,
};

pub fn init(allocator: std.mem.Allocator, user_data: *const UserData) !MeshPipeline {
    var program: Inlucere.Device.Program = undefined;

    const main_vertex_sources = try read_file(allocator, "./assets/shaders/instanced_mesh_standard.vs");
    defer allocator.free(main_vertex_sources);

    const main_fragment_sources = try read_file(allocator, "./assets/shaders/material_color_multi_lights.fs");
    defer allocator.free(main_fragment_sources);

    try program.init(&.{
        .{ .stage = .Vertex, .source = main_vertex_sources },
        .{ .stage = .Fragment, .source = main_fragment_sources },
    });

    const per_instance_buffer: Inlucere.Device.MappedBuffer = try .initEmpty("mesh_instances", MeshInstance, @intCast(MeshInstanceCount), .ExplicitFlushed, .{});
    const instance_range_buffer: Inlucere.Device.MappedBuffer = try .initEmpty("mesh_ranges", MeshInstanceRange, @intCast(MeshInstanceRangeCount), .ExplicitFlushed, .{});
    const command_buffer: Inlucere.Device.MappedBuffer = try .initEmpty("commands", DrawElementsIndirectCommand, @intCast(MeshInstanceRangeCount), .ExplicitFlushed, .{});

    return MeshPipeline{
        .program = program,
        .vertex_array = user_data.vertex_array,
        .vertex_buffer = user_data.vertex_buffer,
        .index_buffer = user_data.index_buffer,
        .scene_uniform_buffer = user_data.scene_uniform_buffer,
        .light_buffer = user_data.light_buffer,
        .per_instance_buffer = per_instance_buffer,
        .instance_range_buffer = instance_range_buffer,
        .command_buffer = command_buffer,
        .current_mesh = 0,
        .binding_info = undefined,
        .mesh_instances = .empty,
    };
}

pub fn deinit(self: *MeshPipeline, allocator: std.mem.Allocator) void {
    Inlucere.gl.deleteProgram(self.program.handle);
    self.per_instance_buffer.deinit();
    self.instance_range_buffer.deinit();

    for (self.mesh_instances.values()) |*v| {
        v.instances.deinit(allocator);
    }
    self.mesh_instances.deinit(allocator);
}

pub const AddMeshData = struct {
    transform: zmath.Mat,
    material_id: u32,

    binding_info: MeshManager.BindingInfo,
};

pub fn add_mesh(self: *MeshPipeline, mesh_id: u32, data: *const AddMeshData) void {
    if (self.current_mesh == 0) {
        self.current_mesh = mesh_id;
        self.instance_range_buffer.cast(MeshInstanceRange)[0] = .{
            .index = 0,
            .count = 0,
        };
        self.binding_info = data.binding_info;
    } else if (self.current_mesh != mesh_id) {
        @panic("WIP: Doesn't support rendering different meshes for now !");
    }

    const model_to_world = data.transform;
    const world_to_model = zmath.transpose(zmath.inverse(model_to_world));

    self.per_instance_buffer.cast(MeshInstance)[self.current_instance] = .{
        .model_to_world = model_to_world,
        .world_to_model = world_to_model,
        .material_id = data.material_id,
    };
    self.instance_range_buffer.cast(MeshInstanceRange)[0].count += 1;
    self.current_instance += 1;
}

// TODO: Add a way to identify instances
pub fn add_instance(self: *MeshPipeline, allocator: std.mem.Allocator, mesh_id: u32, data: *const AddMeshData) !void {
    self.dirty = true;
    self.binding_info = data.binding_info;
    const entry = try self.mesh_instances.getOrPut(allocator, mesh_id);
    if (entry.found_existing) {
        try entry.value_ptr.instances.append(allocator, data.*);
    } else {
        std.log.info("New mesh to draw {}, at {}", .{ mesh_id, data.binding_info.indices_offset });
        entry.value_ptr.* = .{
            .bind_info = data.binding_info,
            .instances = .empty,
        };
        try entry.value_ptr.instances.append(allocator, data.*);
    }
}

pub fn bind(self: *const MeshPipeline) void {
    Inlucere.gl.useProgram(self.program.handle);
    Inlucere.gl.bindVertexArray(self.vertex_array.handle);
    Inlucere.gl.vertexArrayVertexBuffer(
        self.vertex_array.handle,
        0,
        self.binding_info.vertices_buffer.handle,
        0,
        @sizeOf(Mesh.Vertex),
    );
    Inlucere.gl.vertexArrayElementBuffer(self.vertex_array.handle, self.binding_info.indices_buffer.handle);
    Inlucere.gl.bindBufferBase(Inlucere.gl.UNIFORM_BUFFER, 0, self.scene_uniform_buffer.handle);
    Inlucere.gl.bindBufferBase(Inlucere.gl.SHADER_STORAGE_BUFFER, 1, self.per_instance_buffer.handle);
    Inlucere.gl.bindBufferBase(Inlucere.gl.SHADER_STORAGE_BUFFER, 2, self.instance_range_buffer.handle);
    //Inlucere.gl.bindBufferBase(Inlucere.gl.SHADER_STORAGE_BUFFER, 3, self.light_buffer.handle);
    Inlucere.gl.bindBuffer(Inlucere.gl.DRAW_INDIRECT_BUFFER, self.command_buffer.handle);
}

pub fn draw(self: *MeshPipeline) void {
    if (self.mesh_instances.count() == 0) {
        return;
    }

    if (self.dirty) {
        self.dirty = false;

        var instance_count: u32 = 0;
        var command_count: u32 = 0;
        const per_instance_slice = self.per_instance_buffer.cast(MeshInstance);
        const instance_range_slice = self.instance_range_buffer.cast(MeshInstanceRange);
        const command_slice = self.command_buffer.cast(DrawElementsIndirectCommand);
        var current_index: u32 = 0;
        for (self.mesh_instances.keys(), self.mesh_instances.values(), 0..) |mesh_id, mesh_data, index| {
            std.log.info("Draw {} first", .{mesh_id});
            command_slice[index] = DrawElementsIndirectCommand{
                .count = @intCast(@divExact(mesh_data.bind_info.indices_size, @sizeOf(u32))),
                .firstIndex = @intCast(@divExact(mesh_data.bind_info.indices_offset, @sizeOf(u32))),
                .instanceCount = @intCast(mesh_data.instances.items.len),
                .baseVertex = @intCast(@divExact(mesh_data.bind_info.vertices_offset, @sizeOf(Mesh.Vertex))),
                .baseInstance = 0,
            };
            instance_range_slice[index] = MeshInstanceRange{ .index = current_index, .count = @intCast(mesh_data.instances.items.len) };
            for (mesh_data.instances.items, 0..) |instance, i| {
                per_instance_slice[@as(usize, @intCast(current_index)) + i] = MeshInstance{
                    .model_to_world = instance.transform,
                    .world_to_model = zmath.transpose(zmath.inverse(instance.transform)),
                    .material_id = instance.material_id,
                };
                instance_count += 1;
            }
            current_index += @intCast(mesh_data.instances.items.len);
            command_count += 1;
        }
        self.per_instance_buffer.flushRange(0, @sizeOf(MeshInstance) * instance_count);
        self.instance_range_buffer.flushRange(0, @sizeOf(MeshInstanceRange) * command_count);
        Inlucere.gl.memoryBarrier(Inlucere.gl.BUFFER_UPDATE_BARRIER_BIT);
    }

    Inlucere.gl.multiDrawElementsIndirect(Inlucere.gl.TRIANGLES, Inlucere.gl.UNSIGNED_INT, null, @intCast(self.mesh_instances.count()), @sizeOf(DrawElementsIndirectCommand));
}
