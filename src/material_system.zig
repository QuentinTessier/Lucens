const std = @import("std");
const Inlucere = @import("Inlucere");

pub const MaterialSystem = @This();

pub const SlotNumber: usize = 32;

pub const Material = extern struct {
    color: [4]f32,
};

next_mat_id: u32 = 1,
free_slots: std.StaticBitSet(SlotNumber),
buffer: Inlucere.Device.MappedBuffer,
materials: std.AutoArrayHashMapUnmanaged(u32, struct {
    slot: ?usize,
    material: Material,
}),

pub fn init() !MaterialSystem {
    const buffer: Inlucere.Device.MappedBuffer = try .initEmpty("materials", Material, @intCast(SlotNumber), .ExplicitFlushed, .{});
    return .{
        .free_slots = .initEmpty(),
        .materials = .empty,
        .buffer = buffer,
    };
}

pub fn deinit(self: *MaterialSystem, allocator: std.mem.Allocator) void {
    self.buffer.deinit();
    self.materials.deinit(allocator);
}

pub fn add_mat(self: *MaterialSystem, allocator: std.mem.Allocator, material: Material) !u32 {
    const id = self.next_mat_id;
    self.next_mat_id += 1;

    try self.materials.put(allocator, id, .{
        .slot = null,
        .material = material,
    });
    return id;
}

pub fn find_free_slot(self: *const MaterialSystem) !usize {
    if (self.free_slots.findLastSet()) |index| {
        if (index >= SlotNumber) {
            return error.OutOfMemory;
        }
        return index + 1;
    } else {
        return 0;
    }
}

pub fn make_resident(self: *MaterialSystem, mat: u32) !usize {
    var slots = self.buffer.cast(Material);
    if (self.materials.getPtr(mat)) |entry| {
        const index = try self.find_free_slot();

        self.free_slots.set(index);
        slots[index] = entry.material;
        entry.slot = index;
        self.buffer.flushRange(@intCast(@sizeOf(Material) * index), @sizeOf(Material));
        return index;
    } else {
        @panic("No such mat");
    }
}
