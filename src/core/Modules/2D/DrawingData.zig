const std = @import("std");
const Lucens = @import("../../lucens.zig");
const zmath = @import("zmath");

pub const DrawingData = @This();

pub const Sprite = struct {
    position: @Vector(2, f32),
    scale: @Vector(2, f32),
    rotation: @Vector(2, f32),
};

base: Lucens.LucensModule,

sprites: std.ArrayListUnmanaged(Sprite) = .empty,
