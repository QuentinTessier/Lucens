const std = @import("std");
const ecez = @import("ecez");
const SceneNode = @import("scene_module/scene_tree.zig").SceneNode;
const SceneTree = @import("scene_module/scene_tree.zig").SceneTree;

pub const name = .scene;

pub const Components = .{};

pub const Events = .{};

pub const Context = struct {
    scene_tree: SceneTree,
};
