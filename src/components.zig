const std = @import("std");
const math = @import("zmath");
const ecez = @import("ecez");
const zmath = @import("zmath");
pub const WorldTransform = @import("components/world_transform.zig");
pub const Material = @import("components/Material.zig");
pub const StaticMeshRenderer = @import("components/static_mesh_renderer.zig");
pub const Camera = @import("components/camera.zig");

pub const Storage = ecez.CreateStorage(.{
    WorldTransform,
    StaticMeshRenderer,
    Material,
    Camera,
});

pub const GatherMaterialSystem = @import("./system/graphic/update.zig").GatherMaterialSystem(Storage);
pub const MaterialUpdateSystem = @import("./system/graphic/update.zig").MaterialUpdateSystem(Storage);
pub const BatchBuildSystem = @import("./system/graphic/update.zig").BatchBuildSystem(Storage);
pub const InstanceUpdateSystem = @import("./system/graphic/update.zig").InstanceUpdateSystem(Storage);
pub const OffsetUpdateSystem = @import("./system/graphic/update.zig").OffsetUpdateSystem(Storage);
pub const CommandUpdateSystem = @import("./system/graphic/update.zig").CommandUpdateSystem(Storage);

pub const RenderingUpdateEvent2 = ecez.Event("render_update2", .{
    GatherMaterialSystem.system,
    MaterialUpdateSystem.system,
    BatchBuildSystem.system,
    InstanceUpdateSystem.system,
    OffsetUpdateSystem.system,
    CommandUpdateSystem.system,
}, .{
    .EventArgument = BatchBuildSystem.Arguments,
    .run_on_main_thread = false,
});
