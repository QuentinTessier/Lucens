const std = @import("std");
const ecez = @import("ecez");
const ApplicationContextGenerator = @import("modules_context.zig").ApplicationContext;

fn GatherAllContext(comptime Modules: anytype, comptime Storage: type) type {
    var fields: []const std.builtin.Type.StructField = &[0]std.builtin.Type.StructField{};
    inline for (Modules) |mod| {
        const name: [:0]const u8 = @tagName(mod.name);
        const Module: type = mod.Module(Storage);

        if (!@hasDecl(Module, "Context")) continue;
        fields = fields ++ [_]std.builtin.Type.StructField{.{
            .type = *Module.Context,
            .name = name,
            .default_value_ptr = null,
            .alignment = @alignOf(*Module.Context),
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

pub fn ModuleCollection(comptime Modules: anytype) type {
    return struct {
        pub fn GatherAllComponents() []const type {
            var types: []const type = &[0]type{};

            inline for (Modules) |module| {
                types = types ++ module.components;
            }

            return types;
        }

        pub fn GatherAllEvents(comptime Storage: type) type {
            var fields: []const std.builtin.Type.StructField = &[0]std.builtin.Type.StructField{};
            var i: usize = 0;
            inline for (Modules) |mod| {
                const Module: type = mod.Module(Storage);

                if (!@hasDecl(Module, "Events")) continue;
                const Events = Module.Events();
                inline for (Events) |event| {
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

        pub fn GatherAllContext(comptime Storage: type) type {
            const fields: []const std.builtin.Type.StructField = &[0]std.builtin.Type.StructField{};
            inline for (Modules) |mod| {
                const name: [:0]const u8 = @tagName(mod.name);
                const Module: type = mod.Module(Storage);

                if (!@hasDecl(Module, "Context")) continue;
                _ = .{ name, fields };
                // fields = fields ++ [_]std.builtin.Type.StructField{.{
                //     .type = *Module.Context,
                //     .name = name,
                //     .default_value_ptr = &Module.Context.empty,
                //     .alignment = @alignOf(Module.Context),
                //     .is_comptime = true,
                // }};
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

        pub fn StorageType(comptime AllComponents: []const type) type {
            return ecez.CreateStorage(AllComponents);
        }

        pub fn SchedulerType(comptime Storage: type, comptime AllEvents: type) type {
            return ecez.CreateScheduler(Storage, AllEvents{});
        }

        pub fn ApplicationContext(comptime Storage: type) type {
            return ApplicationContextGenerator(Storage, Modules);
        }
    };
}
