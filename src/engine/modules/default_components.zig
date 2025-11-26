const std = @import("std");
pub const WorldTransform = @import("../../components/world_transform.zig");

pub const name = .general_components;

pub const Components = .{
    WorldTransform,
};
pub const Events = .{};

pub fn Module(comptime _: type) type {
    return struct {
        pub fn Context() type {
            return .{};
        }

        pub fn Events() [2]type {
            return .{ u32, f32 };
        }
    };
}
