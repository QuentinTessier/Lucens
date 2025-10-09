const std = @import("std");

// TODO: Area light
pub const LigthType = enum(u32) {
    directional,
    point,
    spot,
};

pub const Light = extern struct {
    color: [3]f32,
    type: LigthType,
    direction: [3]f32,
    intensity: f32,
    position: [3]f32,
    radius: f32,
    inner_cone: f32,
    outer_cone: f32,
    pad0: f32,
    pad1: f32,
};

pub const LightBuffer = extern struct {
    light_count: u32,
    lights: [*]align(16) Light,
};

pub const DirectionalLight = extern struct {
    color: [3]f32,
    intensity: f32,
    direction: [3]f32,

    pub fn toLight(self: *const DirectionalLight) Light {
        return std.mem.zeroInit(Light, .{
            .type = .directional,
            .color = self.color,
            .intensity = self.intensity,
            .direction = self.direction,
        });
    }
};

pub const PointLight = extern struct {
    color: [3]f32,
    intensity: f32,
    position: [3]f32,
    radius: f32,

    pub fn toLight(self: *const PointLight) Light {
        return std.mem.zeroInit(Light, .{
            .type = .point,
            .color = self.color,
            .intensity = self.intensity,
            .position = self.position,
            .radius = self.radius,
        });
    }
};

pub const SpotLight = extern struct {
    color: [3]f32,
    intensity: f32,
    position: [3]f32,
    direction: [3]f32,
    radius: f32,
    inner_cone: f32,
    outer_cone: f32,

    pub fn toLight(self: *const SpotLight) Light {
        return std.mem.zeroInit(Light, .{
            .type = .spot,
            .color = self.color,
            .intensity = self.intensity,
            .position = self.position,
            .direction = self.direction,
            .radius = self.radius,
            .inner_cone = self.inner_cone,
            .outer_cone = self.outer_cone,
        });
    }
};
