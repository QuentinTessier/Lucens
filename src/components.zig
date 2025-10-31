const std = @import("std");
const math = @import("zmath");
const TransformComponent = @import("3D/Transform.zig");
const ecez = @import("ecez");

pub const Components = struct {
    pub const MaterialID = struct {
        id: u32,
    };

    pub const MeshID = struct {
        id: u32,
    };

    pub const Transform = TransformComponent;
};

pub const Storage = ecez.CreateStorage(.{
    Components.MaterialID,
    Components.MeshID,
    Components.Transform,
});
