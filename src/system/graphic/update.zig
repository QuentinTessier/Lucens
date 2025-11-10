const std = @import("std");
const ecez = @import("ecez");
const MeshPipeline = @import("../../graphics/mesh_pipeline.zig");

const Components = @import("../../components.zig");

pub fn GraphicUpdateSystem(comptime Storage: type) type {
    return struct {
        pub const Arguments = struct {
            mesh_pipeline: *MeshPipeline,
            allocator: std.mem.Allocator,
        };

        const MeshInstanceUpdateSubset = Storage.Subset(.{
            Components.WorldTransform,
            Components.MeshID,
        });

        const MeshInstanceUpdateQuery = ecez.Query(
            struct {
                transform: Components.WorldTransform,
                mesh_id: Components.MeshID,
            },
            .{},
            .{},
        );

        pub fn system(query: *MeshInstanceUpdateQuery, _: *MeshInstanceUpdateSubset, args: Arguments) !void {
            const mesh_pipeline = args.mesh_pipeline;
            while (query.next()) |entity| {
                const transform: Components.WorldTransform = entity.transform;
                const mesh_id: Components.MeshID = entity.mesh_id;

                //std.log.info("Adding instance of mesh {}", .{mesh_id.id});
                try mesh_pipeline.draw_instance(args.allocator, mesh_id.id, transform.matrix, 0);
            }
        }
    };
}
