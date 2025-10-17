const std = @import("std");
const math = @import("zmath");
const Components = @import("components.zig").Components;
const Queries = @import("queries.zig");

pub const Systems = @This();

pub fn update_gpu_instance(components: *Queries.QueryTransfromAndGPUInstance) void {
    while (components.next()) |item| {
        const transform: *Components.Transform = item.transform;
        const instance: *Components.InstanceSlot = item.instance;

        if (transform.dirty) {
            const ptr = instance.allocation.cast();
            transform.to_matrix(&ptr.model_to_world);
            ptr.world_to_model = math.transpose(math.inverse(ptr.model_to_world));
            instance.allocation.flush();
            transform.dirty = false;
        }
    }
}
