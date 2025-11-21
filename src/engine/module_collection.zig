const std = @import("std");
const ecez = @import("ecez");

pub fn ModuleCollection(comptime Modules: anytype) type {
    return struct {
        pub fn GatherAllComponents() type {
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

        pub fn StorageType(comptime AllComponents: type) type {
            return ecez.CreateStorage(AllComponents{});
        }
    };
}
