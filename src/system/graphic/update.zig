const std = @import("std");
const ecez = @import("ecez");
const zmath = @import("zmath");
const Mesh = @import("../../3D/Mesh.zig");
const MeshPipeline = @import("../../graphics/mesh_pipeline.zig");
const MeshManager = @import("../../graphics/mesh_buffer_manager.zig").MeshManager(u32, Mesh.Vertex);

const Batch = @import("../../graphics/static_geometry_batch.zig");
const MaterialSystem = @import("../../graphics/material_system.zig");

const Components = @import("../../components.zig");

pub fn BatchBuildSystem(comptime _: type) type {
    return struct {
        pub const Arguments = struct {
            allocator: std.mem.Allocator,
            gpu_mesh_manager: *MeshManager,
            static_geometry_batches: *Batch.StaticGeometryBatches,
            draw_count: *u32, // TODO: Better integration
        };

        const BatchBuildSystemQuery = ecez.Query(
            struct {
                entity: ecez.Entity,
                transform: *Components.WorldTransform,
                renderer: *Components.StaticMeshRenderer,
            },
            .{},
            .{},
        );

        // Figure out how to make this system depend on the material update system but not the material gpu write.
        pub fn system(query: *BatchBuildSystemQuery, args: Arguments) !void {
            const static_geometry_batches = args.static_geometry_batches;

            std.log.info("Building batches", .{});
            while (query.next()) |iter| {
                const entity: ecez.Entity = iter.entity;
                const transform: *const Components.WorldTransform = iter.transform;
                const renderer: *const Components.StaticMeshRenderer = iter.renderer;

                // TODO: Better error handling
                const batch = static_geometry_batches.get_batch(renderer.mesh_id) orelse try static_geometry_batches.add_batch(args.allocator, renderer.mesh_id);
                try batch.add_instance(args.allocator, entity, .{
                    .model_to_world = transform.matrix,
                    .world_to_model = zmath.inverse(transform.matrix),
                    .material_id = 0, // TODO: Add proper material support
                });
            }
            std.log.info("Done building batches", .{});
        }
    };
}

pub fn InstanceUpdateSystem(comptime Storage: type) type {
    return struct {
        pub const Arguments = BatchBuildSystem(Storage).Arguments;

        const InstanceUpdateSystemQuery = ecez.Query(
            struct {
                entity: ecez.Entity,
                transform: *const Components.WorldTransform,
                renderer: *const Components.StaticMeshRenderer,
            },
            .{},
            .{},
        );

        pub fn system(_: *InstanceUpdateSystemQuery, args: Arguments) !void {
            const batches = args.static_geometry_batches.batches.values();
            var instances = args.static_geometry_batches.gpu_instances.memory;

            var current_offset: usize = 0;
            std.log.info("Starting to update Instances", .{});
            for (batches) |*batch| {
                if (batch.entities.len == 0) continue;
                const memory: []const Batch.Instance = batch.entities.items(.instance);

                @memcpy(instances[current_offset..batch.entities.len], memory);
                current_offset += batch.entities.len;
            }
            std.log.info("Done updating Instances", .{});
        }
    };
}

pub fn OffsetUpdateSystem(comptime Storage: type) type {
    return struct {
        pub const Arguments = BatchBuildSystem(Storage).Arguments;

        const OffsetUpdateSystemQuery = ecez.Query(
            struct {
                entity: ecez.Entity,
                transform: *const Components.WorldTransform,
                renderer: *const Components.StaticMeshRenderer,
            },
            .{},
            .{},
        );

        pub fn system(_: *OffsetUpdateSystemQuery, args: Arguments) !void {
            const batches = args.static_geometry_batches.batches.values();
            var offsets = args.static_geometry_batches.gpu_offsets.memory;

            var current_offset: usize = 0;
            for (batches, 0..) |*batch, i| {
                if (batch.entities.len == 0) continue;
                offsets[i] = @intCast(current_offset);
                current_offset += batch.entities.len;
            }
        }
    };
}

pub fn CommandUpdateSystem(comptime Storage: type) type {
    return struct {
        pub const Arguments = BatchBuildSystem(Storage).Arguments;

        const CommandUpdateSystemQuery = ecez.Query(
            struct {
                entity: ecez.Entity,
                transform: *const Components.WorldTransform,
                renderer: *const Components.StaticMeshRenderer,
            },
            .{},
            .{},
        );

        pub fn system(_: *CommandUpdateSystemQuery, args: Arguments) !void {
            std.log.info("Building commands", .{});
            const batches = args.static_geometry_batches.batches.values();
            var commands = args.static_geometry_batches.gpu_commands.memory;

            var current_offset: usize = 0;
            args.draw_count.* = @intCast(batches.len);
            for (batches, 0..) |*batch, i| {
                if (batch.entities.len == 0) continue;
                const binding_info = args.gpu_mesh_manager.allocation.get(batch.id) orelse continue;
                commands[i] = .{
                    .count = binding_info.index_count,
                    .firstIndex = binding_info.index_offset,
                    .instanceCount = @intCast(batch.entities.len),
                    .baseInstance = 0,
                    .baseVertex = @intCast(binding_info.vertex_offset),
                };
                current_offset += batch.entities.len;
            }
        }
    };
}
