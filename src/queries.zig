const ecez = @import("ecez");
const Components = @import("components.zig");

pub const Queries = @This();

pub const QueryTransform = ecez.Query(struct {
    entity: ecez.Entity,
    transform: *Components.Transform,
}, .{}, .{});
