const std = @import("std");
const Inlucere = @import("Inlucere");
const gl = Inlucere.gl;

pub const StagingBufferManager = @This();

const StagingBuffer = struct {
    handle: u32,
    memory: []u8,
    fence: ?gl.GLsync,
};

staging_buffers: std.array_list.Aligned(StagingBuffer, null),
staging_size: u32,
offset: u32,
current_frame: u32,

pub const InitOption = struct {
    size: usize = 64 * 1024 * 1024, // 64Mb
    count: usize = 2,
};

pub fn init(allocator: std.mem.Allocator, options: *const InitOption) !StagingBufferManager {
    var staging_buffers: std.array_list.Aligned(StagingBuffer, null) = .initCapacity(allocator, options.count);
    for (0..options.count) |_| {
        const ptr = staging_buffers.addOneAssumeCapacity();
        gl.createBuffers(1, &ptr.handle);
        gl.namedBufferStorage(
            ptr.handle,
            @intCast(options.size),
            null,
            gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT,
        );
        const mapped_opaque_ptr = gl.mapNamedBufferRange(
            ptr.handle,
            0,
            @intCast(options.size),
            gl.MAP_COHERENT_BIT | gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT,
        ) orelse return error.FailedToMap;
        const mapped_multibytes_ptr: [*]u8 = @ptrCast(@alignCast(mapped_opaque_ptr));
        ptr.mapped_memory = mapped_multibytes_ptr[0..options.size];
        ptr.fence = null;
    }

    return .{
        .staging_buffers = staging_buffers,
        .staging_size = @intCast(options.size),
        .current_frame = 0,
        .offset = 0,
    };
}

pub fn deinit(self: *StagingBufferManager, allocator: std.mem.Allocator) void {
    for (self.staging_buffers.items) |staging_buffer| {
        _ = gl.unmapNamedBuffer(staging_buffer.handle);
        gl.deleteBuffers(1, &staging_buffer.handle);
        if (staging_buffer.fence) |f| gl.deleteSync(f);
    }
    self.staging_buffers.deinit(allocator);
}

pub fn begin_frame(self: *StagingBufferManager) void {
    self.current_frame = @mod(self.current_frame + 1, @as(u32, @intCast(self.staging_buffers.items.len)));
    self.offset = 0;

    if (self.staging_buffers.items[@intCast(self.current_frame)].fence) |fence| {
        gl.clientWaitSync(fence, gl.SYNC_FLUSH_COMMANDS_BIT, 10000000);
        gl.deleteSync(fence);
        self.staging_buffers.items[@intCast(self.current_frame)].fence = null;
    }
}

pub fn end_frame(self: *StagingBufferManager) void {
    self.staging_buffers.items[@intCast(self.current_frame)].fence = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0);
}

pub fn upload(self: *StagingBufferManager, dst_buffer: u32, dst_offset: u32, data: []u8) bool {
    if (self.offset + @as(u32, @intCast(data.len)) > self.staging_size) {
        // TODO: Better handling !
        return false;
    }

    const slice = self.staging_buffers.items[@intCast(self.current_frame)].memory[@intCast(self.offset) .. @as(usize, @intCast(self.offset)) + data.len];
    @memcpy(slice, data);

    gl.copyNamedBufferSubData(
        self.staging_buffers.items[@intCast(self.current_frame)].handle,
        dst_buffer,
        @intCast(self.offset),
        @intCast(dst_offset),
        @intCast(data.len),
    );

    self.offset += @intCast(data.len);
}
