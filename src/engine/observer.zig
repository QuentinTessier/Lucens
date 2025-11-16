const std = @import("std");

pub fn Observer(comptime Payload: type) type {
    std.debug.assert(@typeInfo(Payload) == .@"union");
    return struct {
        pub const Listener = struct {
            target: *anyopaque,
            callback: *const fn (*anyopaque, *const Payload) void,
        };

        listeners: std.array_list.Aligned(Listener, null),

        pub fn add_listener(self: *@This(), allocator: std.mem.Allocator, target: *anyopaque, callback: *const fn (*anyopaque, *const Payload) void) !void {
            return self.listeners.append(allocator, .{
                .target = target,
                .callback = callback,
            });
        }

        pub fn remove_listener(self: *@This(), target: *anyopaque) void {
            var index: usize = 0;
            for (self.listeners.items, 0..) |listener, i| {
                if (listener.target == target) {
                    index = i;
                    break;
                }
            } else {
                std.log.warn("Couldn't find listener {*}", .{target});
            }

            _ = self.listeners.swapRemove(index);
        }

        pub fn dispatch(self: *@This(), data: *const Payload) void {
            for (self.listeners.items) |listener| {
                listener.callback(listener.target, data);
            }
        }
    };
}
