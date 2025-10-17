const ecez = @import("ecez");
const Components = @import("components.zig").Components;

pub const Queries = @This();

pub const QueryTransform = ecez.Query(struct {
    entity: ecez.Entity,
    transform: *Components.Transform,
}, .{}, .{});

pub const QueryTransfromAndGPUInstance = ecez.Query(struct {
    entity: ecez.Entity,
    transform: *Components.Transform,
    instance: *Components.InstanceSlot,
}, .{}, .{});
