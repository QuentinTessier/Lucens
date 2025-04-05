const std = @import("std");
const Inlucere = @import("Inlucere");

pub const AllocationHandle = struct {
    allocator: *const GPUSinglePoolAllocator,
    offset: u32,
    size: u32,
    memory: []u8,

    pub const BindingInformation = struct {
        buffer: Inlucere.Device.Buffer,
        offset: u32,
        size: u32,
    };

    pub fn cast(self: *const AllocationHandle, comptime T: type) []T {
        return @ptrCast(@alignCast(self.memory));
    }

    pub fn flush(self: *const AllocationHandle) void {
        Inlucere.gl.flushMappedNamedBufferRange(self.allocator.gpuMemory.handle, self.offset, self.size);
    }

    pub fn binding(self: *const AllocationHandle) BindingInformation {
        return BindingInformation{
            .buffer = self.allocator.gpuMemory.toBuffer(),
            .offset = self.offset,
            .size = self.size,
        };
    }
};

pub const GPUSinglePoolAllocator = struct {
    pub const AllocationInternal = packed struct(u64) {
        free: bool,
        offset: u31,
        size: u32,
    };

    allocator: std.mem.Allocator,

    capacity: usize,
    gpuMemory: Inlucere.Device.MappedBuffer,
    allocations: std.ArrayListUnmanaged(AllocationInternal) = .{},

    pub fn init(self: *GPUSinglePoolAllocator, name: ?[]const u8, allocator: std.mem.Allocator, poolSize: usize) !void {
        const mem = try Inlucere.Device.MappedBuffer.initEmpty(
            name,
            u8,
            poolSize,
            .ExplicitFlushed,
            .{},
        );

        self.allocator = allocator;
        self.gpuMemory = mem;
        self.allocations = .{};
        try self.allocations.append(allocator, .{
            .free = true,
            .offset = 0,
            .size = @intCast(poolSize),
        });
    }

    fn findFreeBlock(self: *const GPUSinglePoolAllocator, requestSize: usize) ?usize {
        for (self.allocations.items, 0..) |allocation, i| {
            if (!allocation.free) continue;

            if (allocation.size >= requestSize) return i;
        }
        return null;
    }

    fn splitBlock(self: *GPUSinglePoolAllocator, requestSize: usize, blockIndex: usize) !usize {
        const block = &self.allocations.items[blockIndex];

        block.free = false;
        if (block.size > requestSize) {
            const newSize = block.size - requestSize;
            const newOffset = block.offset + requestSize;
            block.size = @intCast(requestSize);

            try self.allocations.insert(self.allocator, blockIndex + 1, .{
                .free = true,
                .size = @intCast(newSize),
                .offset = @intCast(newOffset),
            });
        }
        return blockIndex;
    }

    pub fn printState(self: *GPUSinglePoolAllocator) void {
        for (self.allocations.items) |a| {
            std.debug.print("{}\n", .{a});
        }
    }

    pub fn alloc(self: *GPUSinglePoolAllocator, request_size: usize) !AllocationHandle {
        const newAlignedSize: usize = request_size;

        const maybeFreeBlockIndex = self.findFreeBlock(newAlignedSize);
        if (maybeFreeBlockIndex == null) return error.OutOfMemory;

        const freeBlockIndex = maybeFreeBlockIndex.?;

        const allocationIndex = try self.splitBlock(newAlignedSize, freeBlockIndex);

        const size = self.allocations.items[allocationIndex].size;
        const offset = self.allocations.items[allocationIndex].offset;

        return AllocationHandle{
            .allocator = self,
            .size = size,
            .offset = offset,
            .memory = self.gpuMemory.cast(u8)[offset .. offset + size],
        };
    }

    pub fn free(self: *GPUSinglePoolAllocator, allocation: AllocationHandle) void {
        if (self != allocation.allocator) {
            std.log.err("Trying to free allocation with wrong allocator", .{});
        }

        for (self.allocations.items) |*a| {
            if (a.offset == allocation.offset and a.size == allocation.size) {
                a.free = true;
            }
        }
    }

    pub fn segmentationPass(self: *GPUSinglePoolAllocator) void {
        var shouldStop: bool = false;
        while (!shouldStop) {
            for (self.allocations.items[0 .. self.allocations.items.len - 1], 0..) |*a, i| {
                const b = &self.allocations.items[i + 1];

                if (a.free and b.free) {
                    a.size += b.size;
                    _ = self.allocations.orderedRemove(i + 1);
                    break;
                }
            } else {
                shouldStop = true;
            }
        }
    }

    pub fn deinit(self: *GPUSinglePoolAllocator) void {
        self.allocations.deinit(self.allocator);
        self.gpuMemory.deinit();
    }
};
