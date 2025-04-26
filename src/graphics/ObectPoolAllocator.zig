const std = @import("std");
const Inlucere = @import("Inlucere");

pub fn ObjectPoolAllocator(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Allocation = struct {
            pool: *Self,
            offset: u32,

            pub fn cast(self: *const Allocation) *T {
                const memory = self.pool.memory.cast(u8)[self.offset .. self.offset + @sizeOf(T)];
                return @ptrCast(@alignCast(memory.ptr));
            }
        };

        allocator: std.mem.Allocator,
        memory: Inlucere.Device.MappedBuffer,
        free_slots: std.ArrayListUnmanaged(u32),

        pub fn init(allocator: std.mem.Allocator, pool_size: usize) !@This() {
            var free_slots: std.ArrayListUnmanaged(u32) = try .initCapacity(allocator, pool_size);
            for (0..pool_size) |i| {
                const index = (pool_size - 1) - i;
                free_slots.appendAssumeCapacity(@intCast(index * @sizeOf(T)));
            }

            return .{
                .allocator = allocator,
                .memory = try Inlucere.Device.MappedBuffer.initEmpty(null, T, pool_size, .ExplicitFlushed, .{}),
                .free_slots = free_slots,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.memory.deinit();
            self.free_slots.deinit(self.allocator);
        }

        pub fn create(self: *@This()) !Allocation {
            if (self.free_slots.pop()) |slot| {
                return Allocation{
                    .pool = self,
                    .offset = slot,
                };
            } else {
                return error.OutOfMemory;
            }
        }

        pub fn destroy(self: *@This(), alloc: Allocation) !void {
            if (std.debug.runtime_safety) {
                if (std.mem.indexOfScalar(u32, self.free_slots.items, alloc.offset)) |_| {
                    @panic("Double free on GPU memory");
                }

                alloc.cast().* = undefined;
            }

            try self.free_slots.append(self.allocator, alloc.offset);
        }
    };
}
