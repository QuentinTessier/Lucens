const std = @import("std");
const math = @import("zmath");
const ecez = @import("ecez");
const zmath = @import("zmath");
pub const MeshID = @import("components/mesh_id.zig");
pub const WorldTransform = @import("components/world_transform.zig");

pub const Storage = ecez.CreateStorage(.{
    WorldTransform,
    MeshID,
});

pub const GraphicUpdateSystem = @import("./system/graphic/update.zig").GraphicUpdateSystem(Storage);

pub const RenderingUpdateEvent = ecez.Event("render_update", .{
    GraphicUpdateSystem.system,
}, .{
    .EventArgument = GraphicUpdateSystem.Arguments,
    .run_on_main_thread = true,
});
