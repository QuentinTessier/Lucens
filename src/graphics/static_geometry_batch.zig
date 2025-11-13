const std = @import("std");
const ecez = @import("ecez");
const zmath = @import("zmath");
const TypedBufferView = @import("../graphics/buffer_view.zig").TypedBufferView;

pub const Instance = extern struct {
    model_to_world: zmath.Mat,
    world_to_model: zmath.Mat,
    material_id: u32,
};

pub const DrawElementsIndirectCommand = extern struct {
    count: u32,
    instanceCount: u32,
    firstIndex: u32,
    baseVertex: i32,
    baseInstance: u32,
};

pub const StaticGeometryBatch = struct {
    id: u32,
    entities: std.MultiArrayList(struct {
        entity: ecez.Entity,
        instance: Instance,
    }),

    pub fn add_instance(self: *StaticGeometryBatch, allocator: std.mem.Allocator, entity: ecez.Entity, instance_data: Instance) !void {
        return self.entities.append(allocator, .{
            .entity = entity,
            .instance = instance_data,
        });
    }
};

pub const StaticGeometryBatches = struct {
    batches: std.AutoArrayHashMapUnmanaged(u32, StaticGeometryBatch),

    gpu_instances: TypedBufferView(Instance),
    gpu_offsets: TypedBufferView(u32),
    gpu_commands: TypedBufferView(DrawElementsIndirectCommand),

    pub fn init() StaticGeometryBatches {
        return .{
            .batches = .empty,
            .gpu_instances = undefined,
            .gpu_offsets = undefined,
            .gpu_commands = undefined,
        };
    }

    pub fn deinit(self: *StaticGeometryBatches, allocator: std.mem.Allocator) void {
        for (self.batches.values()) |*batch| {
            batch.entities.deinit(allocator);
        }
        self.batches.deinit(allocator);
    }

    pub fn add_batch(self: *StaticGeometryBatches, allocator: std.mem.Allocator, mesh_id: u32) !*StaticGeometryBatch {
        const entry = try self.batches.getOrPut(allocator, mesh_id);
        if (entry.found_existing) {
            return entry.value_ptr;
        } else {
            entry.value_ptr.* = StaticGeometryBatch{
                .id = mesh_id,
                .entities = .empty,
            };
            return entry.value_ptr;
        }
    }

    pub fn get_batch(self: *StaticGeometryBatches, mesh_id: u32) ?*StaticGeometryBatch {
        return self.batches.getPtr(mesh_id);
    }
};
