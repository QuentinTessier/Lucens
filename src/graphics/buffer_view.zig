pub const BufferView = struct {
    handle: u32,
    offset: u32,
    memory: []u8,

    pub fn to_typed(self: *BufferView, comptime T: type) TypedBufferView(T) {
        return .{
            .handle = self.handle,
            .offset = self.offset,
            .memory = @ptrCast(@alignCast(self.memory)),
        };
    }
};

pub fn TypedBufferView(comptime T: type) type {
    return struct {
        handle: u32,
        offset: u32,
        memory: []T,
    };
}
