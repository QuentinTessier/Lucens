const std = @import("std");
const ecez = @import("ecez");

const Components = @import("../../components.zig").Components;

pub fn GraphicUpdateSystem(comptime Storage: type) type {
    return struct {
        const MeshInstanceUpdateSubset = Storage.Subset(.{
            Components.Transform,
            *Components.InstanceSlot,
        });
        const MeshInstanceUpdateQuery = ecez.Query(
            struct {
                transform: Components.Transform,
                instance: *Components.InstanceSlot,
            },
            .{},
            .{},
        );
    };
}
