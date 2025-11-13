const std = @import("std");
const PersistentBufferedPool = @import("persistent_buffered_pool.zig");
const Inlucere = @import("Inlucere");
const BufferView = @import("buffer_view.zig").BufferView;

pub const MaterialSystem = @This();

pub const Material = extern struct {
    color: [4]f32,
};

material_pool: PersistentBufferedPool,
current_pool: BufferView,
materials: std.AutoArrayHashMapUnmanaged(u32, Material),

pub fn init(self: *MaterialSystem, allocator: std.mem.Allocator) !void {
    try self.material_pool.init(allocator, @sizeOf(Material) * 64, 3);
    self.current_pool = undefined;
    self.materials = .empty;

    Inlucere.gl.objectLabel(
        Inlucere.gl.BUFFER,
        self.material_pool.buffer_handle,
        13,
        "material_pool",
    );
}

pub fn deinit(self: *MaterialSystem, allocator: std.mem.Allocator) void {
    self.material_pool.deinit(allocator);
    self.materials.deinit(allocator);
}

pub fn begin(self: *MaterialSystem) void {
    self.current_pool = self.material_pool.acquire_pool_or_wait();
}

pub fn add_material(self: *MaterialSystem, allocator: std.mem.Allocator, id: u32, mat: Material) !u32 {
    const entry = try self.materials.getOrPut(allocator, id);
    if (!entry.found_existing) {
        entry.value_ptr.* = mat;
    }
    return @intCast(entry.index);
}

pub fn get_slot(self: *MaterialSystem, id: u32) u32 {
    const index = self.materials.getIndex(id) orelse 0;
    return @intCast(index);
}

pub fn end(self: *MaterialSystem, bindpoint: u32) void {
    var materials_array: std.array_list.Aligned(Material, null) = .initBuffer(@ptrCast(@alignCast(self.current_pool.memory)));
    materials_array.appendSliceBounded(self.materials.values()) catch {
        std.log.err("GPU Buffer (Material) doesn't have enought size", .{});
        return;
    };

    self.material_pool.release_pool();
    Inlucere.gl.bindBufferRange(
        Inlucere.gl.SHADER_STORAGE_BUFFER,
        bindpoint,
        self.material_pool.buffer_handle,
        self.current_pool.offset,
        @intCast(self.current_pool.memory.len),
    );
    self.materials.clearRetainingCapacity();
}
