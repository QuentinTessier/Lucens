const std = @import("std");
const ecez = @import("ecez");

pub fn Application(comptime Storage: type, comptime Scheduler: type, comptime ApplicationContext: type) type {
    return struct {
        allocator: std.mem.Allocator,
        storage: Storage,
        scheduler: Scheduler,
        context: ApplicationContext,

        custom_run_callback: *const fn (*@This()) anyerror!void,

        pub fn init(self: *@This(), allocator: std.mem.Allocator, run_callback: *const fn (*@This()) anyerror!void, init_args: ApplicationContext.AllInitArgs) !void {
            self.* = .{
                .allocator = allocator,
                .scheduler = .uninitialized,
                .storage = try .init(allocator),
                .context = undefined,
                .custom_run_callback = run_callback,
            };

            try self.scheduler.init(.{
                .pool_allocator = allocator,
                .query_submit_allocator = allocator,
            });
            errdefer {
                self.storage.deinit();
                self.scheduler.deinit();
            }

            try self.context.init(allocator, init_args);
        }

        pub fn deinit(self: *@This()) void {
            self.context.deinit(self.allocator);
            self.scheduler.deinit();
            self.storage.deinit();
        }

        pub fn run(self: *@This()) anyerror!void {
            return self.custom_run_callback(self);
        }
    };
}
