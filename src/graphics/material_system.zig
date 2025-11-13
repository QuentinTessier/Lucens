const std = @import("std");
const PersistentBufferedPool = @import("persistent_buffered_pool.zig");
const Inlucere = @import("Inlucere");
const BufferView = @import("buffer_view.zig").BufferView;

pub const MaterialSystem = @This();

pub const Material = extern struct {
    color: [4]f32,
};

pub const MaxNumberOfMaterial: usize = 64;

material_pool: PersistentBufferedPool,
current_pool: BufferView,
materials: std.AutoArrayHashMapUnmanaged(u32, struct { index: ?usize, material: Material }),
free_slots: std.bit_set.StaticBitSet(64),

pub fn init(self: *MaterialSystem, allocator: std.mem.Allocator) !void {
    if (MaxNumberOfMaterial > 64 and @TypeOf(self.free_slots) == std.bit_set.StaticBitSet(u64)) {
        @compileError("Use a std.bit_set.ArrayBitSet");
    }
    try self.material_pool.init(allocator, @sizeOf(Material) * MaxNumberOfMaterial, 3);
    self.current_pool = undefined;
    self.materials = .empty;
    self.free_slots = .initEmpty();

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

pub fn find_slot(self: *MaterialSystem) !usize {
    for (0..self.free_slots.capacity()) |i| {
        if (!self.free_slots.isSet(i)) {
            self.free_slots.set(i);
            return i;
        }
    }
    return error.NoSlot;
}

pub fn add_material(self: *MaterialSystem, allocator: std.mem.Allocator, id: u32, mat: Material) !u32 {
    const entry = try self.materials.getOrPut(allocator, id);
    if (!entry.found_existing) {
        entry.value_ptr.* = .{
            .index = null,
            .material = mat,
        };
    }
    return @intCast(entry.index);
}

pub fn get_slot(self: *MaterialSystem, id: u32) !u32 {
    if (self.materials.getPtr(id)) |mat| {
        std.debug.assert(mat.index != null);
        return @intCast(mat.index.?);
    }
    return error.missing_material;
}

pub fn end(self: *MaterialSystem, bindpoint: u32) void {
    // var materials_array: std.array_list.Aligned(Material, null) = .initBuffer(@ptrCast(@alignCast(self.current_pool.memory)));
    // materials_array.appendSliceBounded(self.materials.values()) catch {
    //     std.log.err("GPU Buffer (Material) doesn't have enought size", .{});
    //     return;
    // };

    self.material_pool.release_pool();
    Inlucere.gl.bindBufferRange(
        Inlucere.gl.SHADER_STORAGE_BUFFER,
        bindpoint,
        self.material_pool.buffer_handle,
        self.current_pool.offset,
        @intCast(self.current_pool.memory.len),
    );
}
