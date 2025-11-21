const std = @import("std");
const ecez = @import("ecez");

pub const SceneNode = struct {
    parent_index: u32,
    depth: u32,
    subtree_size: u32,
    entity: ecez.Entity,
};

pub const SceneTree = struct {
    flat: std.MultiArrayList(SceneNode),
    entity_to_flat: std.AutoArrayHashMapUnmanaged(ecez.Entity, u32),

    pub const ChildIterator = struct {
        slice: std.MultiArrayList(SceneNode).Slice,
        end: u32,
        parent_depth: u32,
        current: u32 = undefined,

        pub fn next(self: *ChildIterator) ?SceneNode {
            while (self.current < self.end) {
                const node = self.slice.get(@intCast(self.current));
                self.current += node.subtree_size + 1;
                if (self.parent_depth + 1 == node.depth) {
                    return node;
                }
            }
            return null;
        }
    };

    pub fn SubtreeIterator(comptime field: ?std.MultiArrayList(SceneNode).Field) type {
        if (field) |f| {
            return struct {
                slice: []@FieldType(SceneNode, @tagName(f)),
                current: u32,
                end: u32,

                pub fn next(self: *@This()) ?@FieldType(SceneNode, @tagName(f)) {
                    if (self.current >= self.end) return null;
                    defer self.current += 1;
                    return self.slice[@intCast(self.current)];
                }

                pub fn next_mutable(self: *@This()) ?*@FieldType(SceneNode, @tagName(f)) {
                    if (self.current >= self.end) return null;
                    defer self.current += 1;
                    return &self.slice[@intCast(self.current)];
                }
            };
        } else {
            return struct {
                slice: std.MultiArrayList(SceneNode).Slice,
                current: u32,
                end: u32,

                pub fn next(self: *@This()) ?SceneNode {
                    if (self.current >= self.end) return null;
                    defer self.current += 1;
                    return self.slice.get(@intCast(self.current));
                }
            };
        }
    }

    pub fn children(self: *SceneTree, parent_entity: ecez.Entity) ChildIterator {
        const parent_idx = self.entity_to_flat.get(parent_entity) orelse @panic("TODO: Better debug. Seems like the parent entity is missing");

        return ChildIterator{
            .slice = self.flat.slice(),
            .end = parent_idx + self.flat.items(.subtree_size)[parent_idx] + 1,
            .parent_depth = self.flat.items(.depth)[parent_idx],
            .current = parent_idx + 1,
        };
    }

    pub fn subtree(self: *SceneTree, comptime field: ?std.MultiArrayList(SceneNode).Field, root_entity: ecez.Entity) SubtreeIterator(field) {
        const root_index = self.entity_to_flat.get(root_entity) orelse @panic("TODO: Better debug. Seems like the parent entity is missing");

        if (field) |f| {
            return SubtreeIterator(field){
                .slice = self.flat.items(f),
                .current = root_index,
                .end = root_index + self.flat.items(.subtree_size)[root_index] + 1,
            };
        } else {
            return SubtreeIterator(field){
                .slice = self.flat.slice(),
                .current = root_index,
                .end = root_index + self.flat.items(.subtree_size)[root_index] + 1,
            };
        }
    }

    pub fn subtree_slice(self: *SceneTree, comptime field: ?std.MultiArrayList(SceneNode).Field, root_entity: ecez.Entity) blk: {
        if (field) |f| {
            break :blk []@FieldType(SceneNode, @tagName(f));
        } else {
            break :blk std.MultiArrayList(SceneNode).Slice;
        }
    } {
        const root_index = self.entity_to_flat.get(root_entity) orelse @panic("TODO: Better debug. Seems like the parent entity is missing");
        const root_subtree_size = self.flat.items(.subtree_size)[@intCast(root_index)];
        if (field) |f| {
            return self.flat.items(f)[@intCast(root_index)..@intCast(root_index + root_subtree_size + 1)];
        } else {
            return self.flat.slice().subslice(@intCast(root_index), @intCast(root_subtree_size + 1));
        }
    }

    pub fn init() SceneTree {
        return .{
            .flat = .empty,
            .entity_to_flat = .empty,
        };
    }

    pub fn deinit(self: *SceneTree, allocator: std.mem.Allocator) void {
        self.flat.deinit(allocator);
        self.entity_to_flat.deinit(allocator);
    }

    pub fn add_node_root(self: *SceneTree, allocator: std.mem.Allocator, entity: ecez.Entity) !void {
        try self.entity_to_flat.put(allocator, entity, 0);
        try self.flat.append(allocator, .{
            .parent_index = std.math.maxInt(u32),
            .depth = 0,
            .subtree_size = 0,
            .entity = entity,
        });
    }

    pub fn add_node(self: *SceneTree, allocator: std.mem.Allocator, entity: ecez.Entity, parent: ecez.Entity) !u32 {
        const parent_idx = self.entity_to_flat.get(parent) orelse return error.missing_entity;

        const insert_pos: u32 = 1 + parent_idx + self.flat.items(.subtree_size)[@intCast(parent_idx)];
        const parent_depth: u32 = self.flat.items(.depth)[@intCast(parent_idx)];

        try self.flat.insert(allocator, insert_pos, .{
            .parent_index = parent_idx,
            .depth = parent_depth + 1,
            .subtree_size = 0,
            .entity = entity,
        });

        for (1..self.flat.len) |i| {
            if (i == insert_pos) continue;

            if (self.flat.items(.parent_index)[i] >= insert_pos) {
                self.flat.items(.parent_index)[i] += 1;
            }
        }

        const i = insert_pos + 1;
        for (self.flat.items(.entity)[@intCast(i)..], @intCast(i)..) |e, x| {
            const ptr = self.entity_to_flat.getPtr(e) orelse return error.missing_entity;
            ptr.* = @intCast(x);
        }

        try self.entity_to_flat.put(allocator, entity, insert_pos);

        var ancestor_idx = parent_idx;
        if (ancestor_idx != std.math.maxInt(u32)) {
            while (true) {
                if (ancestor_idx == std.math.maxInt(u32) or ancestor_idx == self.flat.items(.parent_index)[ancestor_idx]) break;
                self.flat.items(.subtree_size)[ancestor_idx] += 1;
                ancestor_idx = self.flat.items(.parent_index)[ancestor_idx];
            }
        }

        return insert_pos;
    }

    pub fn remove_node(self: *SceneTree, allocator: std.mem.Allocator, entity: ecez.Entity) !bool {
        const node_idx = self.entity_to_flat.get(entity) orelse return false;
        if (node_idx == 0) return false;

        const node = self.flat.get(node_idx);
        const subtree_size = node.subtree_size;

        const dst_offset: usize = @intCast(node_idx);
        const src_offset: usize = @intCast(node_idx + 1);
        const shift_size: usize = self.flat.len - src_offset;
        self.shift_by(dst_offset, src_offset, shift_size);
        self.fix_parent_indices(dst_offset > src_offset, dst_offset + 1, dst_offset + shift_size, 1, node_idx);
        try self.flat.resize(allocator, self.flat.len - 1);
        for (@intCast(node_idx)..@intCast(node_idx + subtree_size)) |i| {
            if (self.flat.items(.depth)[i] == node.depth + 1) {
                self.flat.items(.parent_index)[i] = node.parent_index;
            }
            self.flat.items(.depth)[i] -= 1;
        }

        var ancestor_idx = node.parent_index;
        while (true) {
            if (ancestor_idx > self.flat.len or ancestor_idx == self.flat.items(.parent_index)[ancestor_idx]) break;
            self.flat.items(.subtree_size)[ancestor_idx] -= 1;
            ancestor_idx = self.flat.items(.parent_index)[ancestor_idx];
        }
        return true;
    }

    pub fn remove_subtree(self: *SceneTree, allocator: std.mem.Allocator, entity: ecez.Entity) !bool {
        const node_idx = self.entity_to_flat.get(entity) orelse return false;
        if (node_idx == 0) return false;

        const remove_count = self.flat.items(.subtree_size)[node_idx] + 1;
        var ancestor_idx = self.flat.items(.parent_index)[node_idx];
        while (ancestor_idx != node_idx) {
            if (ancestor_idx == std.math.maxInt(u32) or ancestor_idx == self.flat.items(.parent_index)[ancestor_idx]) break;
            self.flat.items(.subtree_size)[ancestor_idx] -= remove_count;
            ancestor_idx = self.flat.items(.parent_index)[ancestor_idx];
        }

        var i: u32 = 0;
        while (i < remove_count) : (i += 1) {
            _ = self.entity_to_flat.swapRemove(self.flat.items(.entity)[node_idx + i]);
        }

        if (node_idx + remove_count < self.flat.len) {
            inline for (std.meta.fields(SceneNode), 0..) |field, x| {
                const src = self.flat.items(@enumFromInt(x))[@intCast(node_idx + remove_count)..];
                const dst = self.flat.items(@enumFromInt(x))[@intCast(node_idx)..];
                std.mem.copyForwards(field.type, dst, src);
            }
            try self.flat.resize(allocator, self.flat.len - remove_count);
        } else if (node_idx + remove_count == self.flat.len) {
            try self.flat.resize(allocator, self.flat.len - remove_count);
        }

        i = node_idx;
        while (i < @as(u32, @intCast(self.flat.len))) : (i += 1) {
            const entry = try self.entity_to_flat.getOrPut(allocator, self.flat.items(.entity)[i]);
            if (entry.found_existing) {
                entry.value_ptr.* = i;
            }
        }

        return true;
    }

    pub fn shift_by(self: *SceneTree, dst: usize, src: usize, len: usize) void {
        if (dst == src) {
            return;
        }

        inline for (std.meta.fields(SceneNode), 0..) |_, x| {
            const src_mem = self.flat.items(@enumFromInt(x))[src .. src + len];
            const dst_mem = self.flat.items(@enumFromInt(x))[dst .. dst + len];
            @memmove(dst_mem, src_mem);
        }
    }

    pub fn fix_parent_indices(self: *SceneTree, forward: bool, start: usize, end: usize, offset: u32, target: u32) void {
        if (!forward) {
            for (start..end) |i| {
                if (self.flat.items(.parent_index)[i] > target) {
                    self.flat.items(.parent_index)[i] -= @intCast(offset);
                }
            }
        } else {
            for (start..end) |i| {
                if (self.flat.items(.parent_index)[i] >= target) {
                    self.flat.items(.parent_index)[i] += @intCast(offset);
                }
            }
        }
    }

    pub fn reparent(self: *SceneTree, allocator: std.mem.Allocator, target_entity: ecez.Entity, new_parent_entity: ecez.Entity) !void {
        const target_index = self.entity_to_flat.get(target_entity) orelse return error.missing_entity;
        const new_parent_index = self.entity_to_flat.get(new_parent_entity) orelse return error.missing_entity;

        if (target_entity <= new_parent_index and new_parent_index <= target_index + self.flat.items(.subtree_size)[target_index]) {
            return error.would_cycle;
        }

        const subtree_size = self.flat.items(.subtree_size)[target_index] + 1;
        var s = try allocator.alloc(SceneNode, subtree_size);
        defer allocator.free(s);

        for (0..@intCast(subtree_size)) |i| {
            inline for (std.meta.fields(SceneNode), 0..) |field, x| {
                @field(s[i], field.name) = self.flat.items(@enumFromInt(x))[@as(usize, @intCast(target_index)) + i];
            }
        }

        const old_parent_index = self.flat.items(.parent_index)[target_index];
        var ancestor_idx = old_parent_index;
        while (ancestor_idx != target_index) {
            if (ancestor_idx > self.flat.len or ancestor_idx == self.flat.items(.parent_index)[ancestor_idx]) break;
            self.flat.items(.subtree_size)[ancestor_idx] -= subtree_size;
            ancestor_idx = self.flat.items(.parent_index)[ancestor_idx];
        }

        {
            const shift_size: usize = self.flat.len - @as(usize, @intCast(target_index + subtree_size));
            const dst_offset: usize = @intCast(target_index);
            const src_offset: usize = @intCast(target_index + subtree_size);
            self.shift_by(dst_offset, src_offset, shift_size);
            self.fix_parent_indices(dst_offset > src_offset, @intCast(target_index + 1), @as(usize, @intCast(target_index)) + shift_size, subtree_size, target_index);
        }

        const adjusted_parent_idx = if (new_parent_entity > target_index) new_parent_index - @as(u32, @intCast(subtree_size)) else self.entity_to_flat.get(new_parent_entity).?;
        const insert_pos = adjusted_parent_idx + self.flat.items(.subtree_size)[adjusted_parent_idx] + 1;

        {
            const shift_size: usize = self.flat.len - @as(usize, @intCast(subtree_size + insert_pos));
            const dst_offset: usize = insert_pos + s.len;
            const src_offset = insert_pos;
            self.shift_by(dst_offset, src_offset, shift_size);
            self.fix_parent_indices(dst_offset > src_offset, dst_offset + 1, dst_offset + shift_size, subtree_size, insert_pos);
        }

        const depth_delta = @as(i32, @intCast(self.flat.items(.depth)[adjusted_parent_idx] + 1)) - @as(i32, @intCast(s[0].depth));
        s[0].parent_index = adjusted_parent_idx;
        s[0].depth = @intCast(@as(i32, @intCast(s[0].depth)) + depth_delta);
        for (s[1..]) |*n| {
            n.depth = @intCast(@as(i32, @intCast(n.depth)) + depth_delta);
            const delta_index = @as(i32, @intCast(n.parent_index)) - @as(i32, @intCast(target_index));
            n.parent_index = @intCast(@as(i32, @intCast(insert_pos)) + delta_index);
        }

        var slice = self.flat.slice().subslice(@intCast(insert_pos), s.len);
        for (s, 0..) |*n, i| {
            slice.set(i, n.*);
        }

        ancestor_idx = adjusted_parent_idx;
        while (true) {
            if (ancestor_idx > self.flat.len or ancestor_idx == self.flat.items(.parent_index)[ancestor_idx]) break;
            self.flat.items(.subtree_size)[ancestor_idx] += subtree_size;
            ancestor_idx = self.flat.items(.parent_index)[ancestor_idx];
        }

        self.entity_to_flat.clearRetainingCapacity();
        for (self.flat.items(.entity), 0..) |e, i| {
            try self.entity_to_flat.put(allocator, e, @intCast(i));
        }
    }
};
