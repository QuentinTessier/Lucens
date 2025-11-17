const std = @import("std");
pub const WorldTransform = @import("../../components/world_transform.zig");

pub const name = .general_components;

pub const Components = .{
    WorldTransform,
};
pub const Events = .{};
