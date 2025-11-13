const std = @import("std");
const PersistentBufferedPool = @import("persistent_buffered_pool.zig");
const MeshManager = @import("mesh_buffer_manager.zig").MeshManager;
const Mesh = @import("../3D/Mesh.zig");
const zmath = @import("zmath");
const Inlucere = @import("Inlucere");
const MaterialSystem = @import("material_system.zig");
const BufferView = @import("../graphics/buffer_view.zig").BufferView;

pub const MeshPipeline = @This();

pub const MeshInstance = extern struct {
    model_to_world: zmath.Mat,
    world_to_model: zmath.Mat,
    material_id: u32,
};

pub const MeshDrawOffset = u32;

pub const DrawElementsIndirectCommand = extern struct {
    count: u32,
    instanceCount: u32,
    firstIndex: u32,
    baseVertex: i32,
    baseInstance: u32,
};

pub const max_draw_calls: u32 = 128;
pub const max_instances: u32 = 4096;
pub const max_materials: u32 = 128;

program: Inlucere.Device.Program,

gpu_mesh_manager: *MeshManager(u32, Mesh.Vertex),
material_system: *MaterialSystem,
mesh_instances_pool: PersistentBufferedPool,
draw_offsets_pool: PersistentBufferedPool,
draw_commands_pool: PersistentBufferedPool,

current_mesh_instances_pool: BufferView,
current_draw_offsets_pool: BufferView,
current_draw_commands_pool: BufferView,

instance_lock: std.Thread.Mutex,
instances: std.AutoArrayHashMapUnmanaged(u32, std.array_list.Aligned(MeshInstance, null)),

fn read_file(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const size = try file.getEndPos();

    return try file.readToEndAlloc(allocator, size);
}

pub fn init(
    self: *MeshPipeline,
    allocator: std.mem.Allocator,
    gpu_mesh_manager: *MeshManager(u32, Mesh.Vertex),
    material_system: *MaterialSystem,
) !void {
    self.instance_lock = .{};
    self.gpu_mesh_manager = gpu_mesh_manager;
    self.material_system = material_system;
    self.current_mesh_instances_pool = undefined;
    self.current_draw_offsets_pool = undefined;
    self.current_draw_commands_pool = undefined;
    try self.mesh_instances_pool.init(allocator, @sizeOf(MeshInstance) * max_instances, 3);
    try self.draw_offsets_pool.init(allocator, @sizeOf(MeshDrawOffset) * max_draw_calls, 3);
    try self.draw_commands_pool.init(allocator, @sizeOf(DrawElementsIndirectCommand) * max_draw_calls, 3);
    self.instances = .empty;

    // const main_vertex_sources = try read_file(allocator, "./assets/shaders/instanced_mesh_standard.vs");
    // defer allocator.free(main_vertex_sources);

    // // const main_fragment_sources = try read_file(allocator, "./assets/shaders/material_color_multi_lights.fs");
    // const main_fragment_sources = try read_file(allocator, "./assets/shaders/test_frustum.fs");
    // defer allocator.free(main_fragment_sources);

    // try self.program.init(&.{
    //     .{ .stage = .Vertex, .source = main_vertex_sources },
    //     .{ .stage = .Fragment, .source = main_fragment_sources },
    // });

    Inlucere.gl.objectLabel(
        Inlucere.gl.BUFFER,
        self.mesh_instances_pool.buffer_handle,
        14,
        "mesh_instances",
    );
    Inlucere.gl.objectLabel(
        Inlucere.gl.BUFFER,
        self.draw_offsets_pool.buffer_handle,
        12,
        "draw_offsets",
    );
    Inlucere.gl.objectLabel(
        Inlucere.gl.BUFFER,
        self.draw_commands_pool.buffer_handle,
        13,
        "draw_commands",
    );
}

pub fn deinit(self: *MeshPipeline, allocator: std.mem.Allocator) void {
    self.mesh_instances_pool.deinit(allocator);
    self.draw_offsets_pool.deinit(allocator);
    self.draw_commands_pool.deinit(allocator);
    for (self.instances.values()) |*instances| {
        instances.deinit(allocator);
    }
    self.instances.deinit(allocator);
}

pub fn begin(self: *MeshPipeline) void {
    self.current_mesh_instances_pool = self.mesh_instances_pool.acquire_pool_or_wait();
    self.current_draw_offsets_pool = self.draw_offsets_pool.acquire_pool_or_wait();
    self.current_draw_commands_pool = self.draw_commands_pool.acquire_pool_or_wait();
}

pub fn draw_instance(self: *MeshPipeline, allocator: std.mem.Allocator, id: u32, model_to_world: zmath.Mat, material_slot: u32) !void {
    self.instance_lock.lock();
    const entry = try self.instances.getOrPut(allocator, id);
    self.instance_lock.unlock();
    if (entry.found_existing) {
        try entry.value_ptr.append(allocator, .{
            .model_to_world = model_to_world,
            .world_to_model = zmath.inverse(zmath.transpose(model_to_world)),
            .material_id = self.material_system.get_slot(material_slot),
        });
    } else {
        entry.value_ptr.* = .empty;
        try entry.value_ptr.append(allocator, .{
            .model_to_world = model_to_world,
            .world_to_model = zmath.inverse(zmath.transpose(model_to_world)),
            .material_id = self.material_system.get_slot(material_slot),
        });
    }
}

pub fn end(self: *MeshPipeline) void {
    // var commands: std.array_list.Aligned(DrawElementsIndirectCommand, null) = .initBuffer(@ptrCast(@alignCast(self.current_draw_commands_pool.memory)));
    // var offset: std.array_list.Aligned(u32, null) = .initBuffer(@ptrCast(@alignCast(self.current_draw_offsets_pool.memory)));
    // var instances_array: std.array_list.Aligned(MeshInstance, null) = .initBuffer(@ptrCast(@alignCast(self.current_mesh_instances_pool.memory)));
    // var current_offset: u32 = 0;
    // self.instance_lock.lock();
    // for (self.instances.keys(), self.instances.values()) |mesh_id, *instances| {
    //     const binding_info = self.gpu_mesh_manager.allocation.get(mesh_id) orelse continue;
    //     commands.appendBounded(.{
    //         .count = binding_info.index_count,
    //         .firstIndex = binding_info.index_offset,
    //         .instanceCount = @intCast(instances.items.len),
    //         .baseInstance = 0,
    //         .baseVertex = @intCast(binding_info.vertex_offset),
    //     }) catch {
    //         std.log.err("GPU Buffer (Command Buffer) doesn't have enought size", .{});
    //         return;
    //     };

    //     offset.appendBounded(current_offset) catch {
    //         std.log.err("GPU Buffer (Offsets) doesn't have enought size", .{});
    //         return;
    //     };
    //     current_offset += @intCast(instances.items.len);
    //     instances_array.appendSliceBounded(instances.items) catch {
    //         std.log.err("GPU Buffer (Instances) doesn't have enought size", .{});
    //         return;
    //     };
    //     instances.clearRetainingCapacity();
    // }
    // self.instance_lock.unlock();

    self.mesh_instances_pool.release_pool();
    Inlucere.gl.bindBufferRange(
        Inlucere.gl.SHADER_STORAGE_BUFFER,
        1,
        self.mesh_instances_pool.buffer_handle,
        self.current_mesh_instances_pool.offset,
        @intCast(self.current_mesh_instances_pool.memory.len),
    );
    self.draw_offsets_pool.release_pool();
    Inlucere.gl.bindBufferRange(
        Inlucere.gl.SHADER_STORAGE_BUFFER,
        2,
        self.draw_offsets_pool.buffer_handle,
        self.current_draw_offsets_pool.offset,
        @intCast(self.current_draw_offsets_pool.memory.len),
    );
    self.draw_commands_pool.release_pool();
    Inlucere.gl.bindBuffer(
        Inlucere.gl.DRAW_INDIRECT_BUFFER,
        self.draw_commands_pool.buffer_handle,
    );
}

pub fn draw(self: *MeshPipeline, draw_count: u32) void {
    if (draw_count == 0) {
        return;
    }

    Inlucere.gl.useProgram(self.program.handle);
    Inlucere.gl.bindVertexArray(self.gpu_mesh_manager.vertex_array_object);
    Inlucere.gl.multiDrawElementsIndirect(
        Inlucere.gl.TRIANGLES,
        Inlucere.gl.UNSIGNED_INT,
        @ptrFromInt(self.current_draw_commands_pool.offset),
        @intCast(draw_count),
        @sizeOf(DrawElementsIndirectCommand),
    );
}
