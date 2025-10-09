const std = @import("std");
const Inlucere = @import("Inlucere");
pub const Light = @import("3D/Light.zig").Light;
pub const DirectionalLight = @import("3D/Light.zig").DirectionalLight;
pub const PointLight = @import("3D/Light.zig").PointLight;
pub const SpotLight = @import("3D/Light.zig").SpotLight;

pub const LightSystem = @This();

buffer: Inlucere.Device.MappedBuffer,
lights: std.array_list.Aligned(Light, null),

pub const max_light_per_scene: usize = 128;

pub fn init() !LightSystem {
    const buffer: Inlucere.Device.MappedBuffer = try .initEmptyGeneric("generic_lights", max_light_per_scene * @sizeOf(Light), .ExplicitFlushed, .{});

    return .{
        .buffer = buffer,
        .lights = .empty,
    };
}

pub fn deinit(self: *LightSystem, allocator: std.mem.Allocator) void {
    self.buffer.deinit();
    self.lights.deinit(allocator);
}

pub fn add_light(self: *LightSystem, allocator: std.mem.Allocator, light: anytype) !void {
    try self.lights.append(allocator, light.toLight());
}

pub fn upload(self: *const LightSystem) void {
    std.debug.assert(self.lights.items.len < max_light_per_scene);
    const size: u32 = @intCast(self.lights.items.len);
    const size_slice = self.buffer.cast(u32);
    size_slice[0] = size;

    const light_byte_ptr = self.buffer.ptr + @sizeOf(u32) * 4;
    const light_ptr: [*]Light = @ptrCast(@alignCast(light_byte_ptr));
    const light_slice = light_ptr[0..self.lights.items.len];

    @memcpy(light_slice, self.lights.items);
    self.buffer.flushRange(0, @intCast(@sizeOf(Light) * self.lights.items.len + @sizeOf(u32) * 4));
}
