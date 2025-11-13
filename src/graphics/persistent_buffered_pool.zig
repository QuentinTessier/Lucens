const std = @import("std");
const Inlucere = @import("Inlucere");
const gl = Inlucere.gl;
const BufferView = @import("buffer_view.zig").BufferView;
const TypedBufferView = @import("buffer_view.zig").TypedBufferView;

pub const PersistentBufferedPool = @This();

buffer_handle: u32,
mapped_memory: []u8,

frame_count: u32,
current_frame: u32,
frame_syncs: std.array_list.Aligned(?gl.GLsync, null),

pub fn init(self: *PersistentBufferedPool, allocator: std.mem.Allocator, bytes_per_pool: usize, max_frame_in_flight: usize) !void {
    const buffer_size_bytes = bytes_per_pool * max_frame_in_flight;
    gl.createBuffers(1, @ptrCast(&self.buffer_handle));
    gl.namedBufferStorage(
        self.buffer_handle,
        @intCast(buffer_size_bytes),
        null,
        gl.MAP_COHERENT_BIT | gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT,
    );

    const mapped_opaque_ptr = gl.mapNamedBufferRange(
        self.buffer_handle,
        0,
        @intCast(buffer_size_bytes),
        gl.MAP_COHERENT_BIT | gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT,
    ) orelse return error.FailedToMap;
    const mapped_multibytes_ptr: [*]u8 = @ptrCast(@alignCast(mapped_opaque_ptr));
    self.mapped_memory = mapped_multibytes_ptr[0..buffer_size_bytes];

    self.frame_count = @intCast(max_frame_in_flight);
    self.frame_syncs = try .initCapacity(allocator, max_frame_in_flight);
    self.frame_syncs.appendNTimesAssumeCapacity(null, max_frame_in_flight);
}

pub fn deinit(self: *PersistentBufferedPool, allocator: std.mem.Allocator) void {
    for (self.frame_syncs.items) |sync| {
        if (sync) |s| gl.deleteSync(s);
    }
    self.frame_syncs.deinit(allocator);
    _ = gl.unmapNamedBuffer(self.buffer_handle);
    gl.deleteBuffers(1, &self.buffer_handle);
}

pub fn frame_range(self: *const PersistentBufferedPool, frame: u32) [2]u32 {
    std.debug.assert(frame < self.frame_count);
    const bytes_per_pool = @divExact(@as(u32, @intCast(self.mapped_memory.len)), self.frame_count);
    const offset = bytes_per_pool * frame;
    return .{ offset, bytes_per_pool };
}

pub const AcquirePoolResult = struct {
    offset: u32,
    memory: []u8,
};

pub fn wait_for_fence_with_timeout(_: *PersistentBufferedPool, fence: gl.GLsync, timeout: u64) bool {
    const res = gl.clientWaitSync(fence, gl.SYNC_FLUSH_COMMANDS_BIT, timeout);
    return res == gl.ALREADY_SIGNALED or res == gl.CONDITION_SATISFIED;
}

pub fn wait_for_fence(_: *PersistentBufferedPool, fence: gl.GLsync) void {
    while (true) {
        const r = gl.clientWaitSync(fence, gl.SYNC_FLUSH_COMMANDS_BIT, 1000000);
        if (r == gl.ALREADY_SIGNALED or r == gl.CONDITION_SATISFIED) break;
    }
}

pub fn acquire_pool(self: *PersistentBufferedPool, timeout: u64) ?BufferView {
    self.current_frame = @mod(self.current_frame + 1, self.frame_count);

    if (self.frame_syncs.items[@intCast(self.current_frame)]) |fence| {
        if (!self.wait_for_fence_with_timeout(fence, timeout)) {
            return null;
        }
        gl.deleteSync(fence);
        self.frame_syncs.items[@intCast(self.current_frame)] = null;
    }
    const range = self.frame_range(self.current_frame);
    return .{
        .handle = self.buffer_handle,
        .offset = range[0],
        .memory = self.mapped_memory[@intCast(range[0])..@intCast(range[0] + range[1])],
    };
}

pub fn acquire_pool_or_wait(self: *PersistentBufferedPool) BufferView {
    self.current_frame = @mod(self.current_frame + 1, self.frame_count);

    if (self.frame_syncs.items[@intCast(self.current_frame)]) |fence| {
        self.wait_for_fence(fence);
        gl.deleteSync(fence);
        self.frame_syncs.items[@intCast(self.current_frame)] = null;
    }
    const range = self.frame_range(self.current_frame);
    return .{
        .handle = self.buffer_handle,
        .offset = range[0],
        .memory = self.mapped_memory[@intCast(range[0])..@intCast(range[0] + range[1])],
    };
}

pub fn acquire_pool_assume_ready(self: *PersistentBufferedPool) AcquirePoolResult {
    self.current_frame = @mod(self.current_frame + 1, self.frame_count);
    const range = self.frame_range(self.current_frame);
    return .{
        .handle = self.buffer_handle,
        .offset = range[0],
        .memory = self.mapped_memory[@intCast(range[0])..@intCast(range[0] + range[1])],
    };
}

pub fn is_next_pool_ready(self: *const PersistentBufferedPool) bool {
    const idx = @mod(self.current_frame + 1, self.frame_count);
    if (self.frame_syncs.items[@intCast(idx)] == null) return true;

    const res = gl.clientWaitSync(self.frame_syncs.items[@intCast(idx)].?, 0, 0);
    return res == gl.ALREADY_SIGNALED or res == gl.CONDITION_SATISFIED;
}

pub fn release_pool(self: *PersistentBufferedPool) void {
    self.frame_syncs.items[@intCast(self.current_frame)] = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0);
}
