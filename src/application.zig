const std = @import("std");
const ecez = @import("ecez");

fn GatherAllComponents(comptime Modules: anytype) type {
    var fields: []const std.builtin.Type.StructField = &[0]std.builtin.Type.StructField{};

    var i: usize = 0;
    inline for (Modules) |module| {
        inline for (module.Components) |comp| {
            var num_buf: [128]u8 = undefined;
            fields = fields ++ [_]std.builtin.Type.StructField{.{
                .type = type,
                .name = std.fmt.bufPrintZ(&num_buf, "{d}", .{i}) catch unreachable,
                .default_value_ptr = &comp,
                .alignment = @alignOf(type),
                .is_comptime = true,
            }};
            i += 1;
        }
    }

    return @Type(.{
        .@"struct" = .{
            .fields = fields,
            .decls = &.{},
            .is_tuple = true,
            .layout = .auto,
        },
    });
}

fn GatherAllEvents(comptime Modules: anytype) type {
    var fields: []const std.builtin.Type.StructField = &[0]std.builtin.Type.StructField{};

    var i: usize = 0;
    inline for (Modules) |module| {
        inline for (module.Events) |event| {
            var num_buf: [128]u8 = undefined;
            fields = fields ++ [_]std.builtin.Type.StructField{.{
                .type = type,
                .name = std.fmt.bufPrintZ(&num_buf, "{d}", .{i}) catch unreachable,
                .default_value_ptr = &event,
                .alignment = @alignOf(type),
                .is_comptime = true,
            }};
            i += 1;
        }
    }

    return @Type(.{
        .@"struct" = .{
            .fields = fields,
            .decls = &.{},
            .is_tuple = true,
            .layout = .auto,
        },
    });
}

pub fn GatherAllModulesData(comptime Modules: anytype) type {
    var fields: []const std.builtin.Type.StructField = &[0]std.builtin.Type.StructField{};

    inline for (Modules) |module| {
        const name: [:0]const u8 = @tagName(module.name);
        const data: type = module.Context;
        fields = fields ++ [_]std.builtin.Type.StructField{.{
            .name = name,
            .type = *data,
            .default_value_ptr = null,
            .alignment = @alignOf(*data),
            .is_comptime = false,
        }};
    }

    return @Type(.{
        .@"struct" = .{
            .fields = fields,
            .decls = &.{},
            .is_tuple = false,
            .layout = .auto,
        },
    });
}

pub fn Application(comptime Modules: anytype) type {
    return struct {
        const all_components = GatherAllComponents(Modules);
        const all_events = .{};
        const all_module_data: type = GatherAllModulesData(Modules);
        const ecez_storage = ecez.CreateStorage(all_components{});
        const ecez_scheduler = ecez.CreateScheduler(ecez_storage, all_events);

        allocator: std.mem.Allocator,
        storage: ecez_storage,
        scheduler: ecez_scheduler,
        modules: all_module_data,

        custom_run_callback: *const fn (*@This()) anyerror!void,

        pub fn init(self: *@This(), allocator: std.mem.Allocator, run_callback: *const fn (*@This()) anyerror!void) !void {
            self.* = .{
                .allocator = allocator,
                .scheduler = .uninitialized,
                .storage = try .init(allocator),
                .modules = undefined,
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

            inline for (Modules) |mod| {
                std.log.info("Initializing {s}", .{@tagName(mod.name)});
                @field(self.modules, @tagName(mod.name)) = try allocator.create(mod.Context);
                try @field(self.modules, @tagName(mod.name)).init(allocator);
            }
        }

        pub fn deinit(self: *@This()) void {
            const fields: []const std.builtin.Type.StructField = std.meta.fields(all_module_data);
            comptime var ite = std.mem.reverseIterator(fields);
            inline while (ite.next()) |field| {
                @field(self.modules, field.name).deinit(self.allocator);
                self.allocator.destroy(@field(self.modules, field.name));
            }
            self.scheduler.deinit();
            self.storage.deinit();
        }

        pub fn run(self: *@This()) anyerror!void {
            return self.custom_run_callback(self);
        }
    };
}
