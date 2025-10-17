const std = @import("std");
const Inlucere = @import("Inlucere");
const gl = Inlucere.gl;
const StagingBufferManager = @import("staging_buffer_manager.zig");

// TODO: Generate VAO from VertexType
pub fn MeshManager(comptime IdType: type, comptime VertexType: type) type {
    return struct {
        pub const Self = @This();

        const Block = struct {
            offset: u32,
            size: u32,

            pub fn order(lhs: Block, rhs: Block) std.math.Order {
                return std.math.order(lhs.offset, rhs.offset);
            }
        };

        const MeshHandle = struct {
            id: IdType,
            vertex_offset: u32,
            vertex_count: u32,
            index_offset: u32,
            index_count: u32,
        };

        vertex_buffer: u32,
        index_buffer: u32,
        vertex_array_object: u32,

        max_vertices: usize,
        max_indices: usize,
        vertex_count: usize,
        index_count: usize,

        vertex_free_blocks: std.array_list.Aligned(Block, null),
        index_free_blocks: std.array_list.Aligned(Block, null),
        allocation: std.AutoHashMapUnmanaged(IdType, MeshHandle),

        pub fn init(self: *Self, allocator: std.mem.Allocator, max_vertices: usize, max_indices: usize, vertex_array_object: u32) !void {
            var buffer_handles: [2]u32 = undefined;
            gl.createBuffers(2, (&buffer_handles).ptr);
            self.vertex_buffer = buffer_handles[0];
            gl.namedBufferStorage(self.vertex_buffer, @intCast(max_vertices * @sizeOf(VertexType)), null, 0);
            Inlucere.gl.objectLabel(
                Inlucere.gl.BUFFER,
                self.vertex_buffer,
                8,
                "vertices",
            );

            self.index_buffer = buffer_handles[1];
            gl.namedBufferStorage(self.index_buffer, @intCast(max_indices * @sizeOf(u32)), null, 0);
            Inlucere.gl.objectLabel(
                Inlucere.gl.BUFFER,
                self.index_buffer,
                7,
                "indices",
            );

            self.vertex_array_object = vertex_array_object;
            self.max_vertices = max_vertices;
            self.max_indices = max_indices;
            self.vertex_count = 0;
            self.index_count = 0;

            self.allocation = .empty;
            self.vertex_free_blocks = try .initCapacity(allocator, 32);
            self.vertex_free_blocks.appendAssumeCapacity(.{ .offset = 0, .size = @intCast(max_vertices) });
            self.index_free_blocks = try .initCapacity(allocator, 32);
            self.index_free_blocks.appendAssumeCapacity(.{ .offset = 0, .size = @intCast(max_indices) });

            gl.vertexArrayVertexBuffer(self.vertex_array_object, 0, self.vertex_buffer, 0, @sizeOf(VertexType));
            gl.vertexArrayElementBuffer(self.vertex_array_object, self.index_buffer);
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            gl.deleteBuffers(1, &self.index_buffer);
            gl.deleteBuffers(1, &self.vertex_buffer);
            gl.deleteVertexArrays(1, &self.vertex_array_object);
            self.allocation.deinit(allocator);
            self.vertex_free_blocks.deinit(allocator);
            self.index_free_blocks.deinit(allocator);
        }

        pub fn alloc(self: *Self, allocator: std.mem.Allocator, id: IdType, vertices: []const VertexType, indices: []const u32, staging: *StagingBufferManager) !?MeshHandle {
            const vertex_offset = self.alloc_from_freelist(&self.vertex_free_blocks, vertices.len);
            const index_offset = self.alloc_from_freelist(&self.index_free_blocks, indices.len);

            if (vertex_offset == std.math.maxInt(usize) or index_offset == std.math.maxInt(usize)) return null;

            const handle: MeshHandle = .{
                .id = id,
                .vertex_offset = @intCast(vertex_offset),
                .vertex_count = @intCast(vertices.len),
                .index_offset = @intCast(index_offset),
                .index_count = @intCast(indices.len),
            };

            _ = staging.upload(self.vertex_buffer, handle.vertex_offset * @sizeOf(VertexType), std.mem.sliceAsBytes(vertices));
            _ = staging.upload(self.index_buffer, handle.index_offset * @sizeOf(u32), std.mem.sliceAsBytes(indices));

            try self.allocation.put(allocator, id, handle);
            self.vertex_count += vertices.len;
            self.index_count += indices.len;
            return handle;
        }

        pub fn free(self: *Self, allocator: std.mem.Allocator, handle: *const MeshHandle) bool {
            if (!self.allocation.contains(handle.id)) {
                return false;
            }

            const vertex_block: Block = .{ .offset = handle.vertex_offset, .size = handle.vertex_count };
            const index_block: Block = .{ .offset = handle.index_offset, .size = handle.index_count };

            try self.insert_and_merge_free_block(allocator, &self.vertex_free_blocks, vertex_block);
            try self.insert_and_merge_free_block(allocator, &self.index_free_blocks, index_block);

            self.vertex_count -= handle.vertex_count;
            self.index_count -= handle.index_count;

            self.allocation.remove(handle.id);
        }

        pub fn defragment(self: *Self, allocator: std.mem.Allocator) void {
            if (self.allocation.size == 0) return;

            var tmp_buffers: [2]u32 = undefined;
            gl.createBuffers(2, (&tmp_buffers).ptr);
            gl.namedBufferStorage(tmp_buffers[0], self.max_vertices * @sizeOf(VertexType), null, 0);
            gl.namedBufferStorage(tmp_buffers[1], self.max_indices * @sizeOf(u32), null, 0);

            var ite = self.allocation.valueIterator();
            var new_vertex_offset: usize = 0;
            var new_index_offset: usize = 0;
            while (ite.next()) |*entry| {
                gl.copyNamedBufferSubData(
                    self.vertex_buffer,
                    tmp_buffers[0],
                    @intCast(entry.vertex_offset * @sizeOf(VertexType)),
                    @intCast(new_vertex_offset),
                    @intCast(entry.vertex_count * @sizeOf(VertexType)),
                );

                gl.copyNamedBufferSubData(
                    self.index_buffer,
                    tmp_buffers[1],
                    @intCast(entry.index_offset * @sizeOf(u32)),
                    @intCast(new_vertex_offset),
                    @intCast(entry.index_count * @sizeOf(u32)),
                );

                entry.vertex_offset = new_vertex_offset;
                entry.index_offset = new_index_offset;

                new_vertex_offset += entry.vertex_count;
                new_index_offset += entry.index_count;
            }

            gl.deleteBuffers(1, &self.vertex_buffer);
            gl.deleteBuffers(1, &self.index_buffer);

            self.vertex_buffer = tmp_buffers[0];
            self.index_buffer = tmp_buffers[1];

            gl.vertexArrayVertexBuffer(self.vertex_array_object, 0, self.vertex_buffer, 0, @sizeOf(VertexType));
            gl.vertexArrayElementBuffer(self.vertex_array_object, self.index_buffer);

            self.vertex_free_blocks.clearRetainingCapacity();
            self.index_free_blocks.clearRetainingCapacity();

            if (new_vertex_offset < self.max_vertices) {
                self.vertex_free_blocks.append(allocator, .{
                    .offset = @intCast(new_vertex_offset),
                    .size = @intCast(self.max_vertices - new_vertex_offset),
                });
            }

            if (new_index_offset < self.max_indices) {
                self.index_free_blocks.append(allocator, .{
                    .offset = @intCast(new_index_offset),
                    .size = @intCast(self.max_indices - new_index_offset),
                });
            }
        }

        fn alloc_from_freelist(_: *Self, free_list: *std.array_list.Aligned(Block, null), size: usize) usize {
            for (free_list.items, 0..) |*block, index| {
                if (block.size >= size) {
                    const offset = block.offset;

                    if (block.size == size) {
                        _ = free_list.orderedRemove(index);
                    } else {
                        block.offset += @intCast(size);
                        block.size -= @intCast(size);
                    }

                    return offset;
                }
            }
            return std.math.maxInt(usize);
        }

        fn insert_and_merge_free_block(_: *Self, allocator: std.mem.Allocator, free_list: *std.array_list.Aligned(Block, null), block: Block) !void {
            const index = std.sort.lowerBound(Block, free_list.items, block, Block.order);
            try free_list.insert(allocator, index, block);

            const next = index + 1;
            const maybe_next_offset = free_list.items[index].offset + free_list.items[index].size;
            if (next < free_list.items.len and maybe_next_offset == free_list.items[next].offset) {
                free_list.items[index].offset += free_list.items[next].size;
                free_list.orderedRemove(next);
            }

            if (index != 0) {
                const prev = index - 1;
                const maybe_block_offset = free_list.items[prev].offset + free_list.items[prev].size;
                if (maybe_block_offset == free_list.items[index].offset) {
                    free_list.items[prev].offset += free_list.items[index].size;
                    free_list.orderedRemove(index);
                }
            }
        }
    };
}
