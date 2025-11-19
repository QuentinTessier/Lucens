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

    pub fn get_subtree_range(self: *const SceneTree, index: u32) struct { u32, u32 } {
        return .{
            index,
            index + self.flat.items(.subtree_size)[@intCast(index)],
        };
    }

    pub fn get_subtree(self: *const SceneTree, entity: u32) ?struct { u32, u32 } {
        const index = self.entity_to_flat.get(entity) orelse return null;
        return self.get_subtree_range(index);
    }

    pub fn add_node_root(self: *SceneTree, allocator: std.mem.Allocator, entity: u32) !u32 {
        const node: SceneNode = .{
            .depth = 0,
            .subtree_size = 1,
            .parent_index = std.math.maxInt(u32),
            .entity = entity,
        };

        const index = self.flat.len;
        try self.flat.append(allocator, node);
        try self.entity_to_flat.put(allocator, entity, @intCast(index));

        return @intCast(index);
    }

    pub fn add_node_child(self: *SceneTree, allocator: std.mem.Allocator, parent: u32, child: u32) !u32 {
        const parent_index = self.entity_to_flat.get(parent) orelse return error.missing_entity;

        const range = self.get_subtree_range(parent_index);
        const end = range.@"1";
        const insert_pos = end;

        const node: SceneNode = .{
            .depth = self.flat.items(.depth)[parent_index] + 1,
            .subtree_size = 1,
            .parent_index = parent_index,
            .entity = child,
        };

        try self.flat.insert(allocator, insert_pos, node);
        try self.entity_to_flat.put(allocator, child, @intCast(insert_pos));

        for (@intCast(insert_pos + 1)..self.flat.len) |i| {
            const entity: u32 = self.flat.items(.entity)[i];
            if (self.entity_to_flat.getPtr(entity)) |index| {
                index.* += 1;
            } else {
                unreachable;
            }
        }

        var ancestor = parent_index;
        while (ancestor != std.math.maxInt(u32)) {
            self.flat.items(.subtree_size)[ancestor] += 1;
            ancestor = self.flat.items(.parent_index)[ancestor];
        }

        return insert_pos;
    }

    fn adjust_subtree_sizes_after_move(self: *SceneTree, old_pos: u32, old_end: u32, new_pos: u32) void {
        const count = old_end - old_pos;

        var old_parent: u32 = self.flat.items(.parent_index)[old_pos];
        while (old_parent != std.math.maxInt(u32)) {
            std.log.info("Old parent: {}", .{self.flat.items(.entity)[old_parent]});
            self.flat.items(.subtree_size)[old_parent] -= count;
            old_parent = self.flat.items(.parent_index)[old_parent];
        }

        var new_parent: u32 = self.flat.items(.parent_index)[new_pos];
        while (new_parent != std.math.maxInt(u32)) {
            std.log.info("New parent: {}", .{self.flat.items(.entity)[new_parent]});
            self.flat.items(.subtree_size)[new_parent] += count;
            new_parent = self.flat.items(.parent_index)[new_parent];
        }
    }

    pub fn reparent2(self: *SceneTree, allocator: std.mem.Allocator, target_index: u32, new_parent_index: u32) !void {
        if (target_index == new_parent_index) return;

        const target_range = self.get_subtree_range(target_index);
        const new_parent_range = self.get_subtree_range(new_parent_index);
        const count: usize = @intCast(target_range.@"1" - target_range.@"0");

        var buffer: std.array_list.Aligned(SceneNode, null) = try .initCapacity(allocator, count);
        defer buffer.deinit(allocator);
        const slice = self.flat.slice();

        for (@intCast(target_range.@"0")..@intCast(target_range.@"1")) |i| {
            buffer.appendAssumeCapacity(slice.get(i));
        }

        {
            var indices: std.array_list.Aligned(usize, null) = try .initCapacity(allocator, count);
            defer indices.deinit(allocator);

            for (@intCast(target_range.@"0")..@intCast(target_range.@"1")) |i| {
                indices.appendAssumeCapacity(i);
            }

            self.flat.orderedRemoveMany(indices.items);
        }

        const index = new_parent_range.@"1";

        for (buffer.items, 0..) |*node, i| {
            const idx: usize = @as(usize, @intCast(index)) + i;

            if (idx > self.flat.len) {
                try self.flat.append(allocator, node.*);
            } else {
                try self.flat.insert(allocator, idx, node.*);
            }
        }

        self.flat.items(.parent_index)[@intCast(index)] = new_parent_index;
        const old_depth = self.flat.items(.depth)[@intCast(index)];
        self.flat.items(.depth)[@intCast(index)] = self.flat.items(.depth)[@intCast(new_parent_index)] + 1;
        const static_offset: i64 = @as(i64, @intCast(old_depth)) - @as(i64, @intCast(self.flat.items(.depth)[@intCast(index)]));

        for (1..count) |i| {
            const idx: usize = @as(usize, @intCast(index)) + i;

            const offset = self.flat.items(.depth)[idx] - static_offset;
            self.flat.items(.depth)[idx] = @intCast(offset);
        }
    }

    pub fn dump(self: *const SceneTree) void {
        const slice = self.flat.slice();

        for (0..slice.len) |i| {
            std.debug.print("{} : {}\n", .{ i, slice.get(i) });
        }
    }
};
