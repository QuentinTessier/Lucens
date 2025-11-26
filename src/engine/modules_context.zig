const std = @import("std");

pub fn GatherAllContext(comptime Storage: type, comptime Modules: anytype) type {
    var fields: []const std.builtin.Type.StructField = &[0]std.builtin.Type.StructField{};
    inline for (Modules) |mod| {
        const name: [:0]const u8 = @tagName(mod.name);
        const Module: type = mod.Module(Storage);

        if (!@hasDecl(Module, "Context")) continue;
        fields = fields ++ [_]std.builtin.Type.StructField{.{
            .type = *Module.Context,
            .name = name,
            .default_value_ptr = null,
            .alignment = @alignOf(Module.Context),
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

fn GatherInitArgTuple(comptime init_fn: std.builtin.Type.Fn) type {
    var fields: []const std.builtin.Type.StructField = &[0]std.builtin.Type.StructField{};

    inline for (init_fn.params[2..], 0..) |param, i| {
        var num_buf: [128]u8 = undefined;
        fields = fields ++ [_]std.builtin.Type.StructField{.{
            .type = param.type.?,
            .name = std.fmt.bufPrintZ(&num_buf, "{d}", .{i}) catch unreachable,
            .default_value_ptr = null,
            .alignment = @alignOf(param.type.?),
            .is_comptime = false,
        }};
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

pub fn GatherAllInitArgs(comptime ContextData: type) type {
    var fields: []const std.builtin.Type.StructField = &[0]std.builtin.Type.StructField{};

    comptime var i = 0;
    inline for (std.meta.fields(ContextData)) |module_data| {
        if (@hasDecl(@typeInfo(module_data.type).pointer.child, "init")) {
            const InitFn: type = @TypeOf(@typeInfo(module_data.type).pointer.child.init);
            const ArgTuple: type = GatherInitArgTuple(@typeInfo(InitFn).@"fn");
            var num_buf: [128]u8 = undefined;
            fields = fields ++ [_]std.builtin.Type.StructField{.{
                .type = ArgTuple,
                .name = std.fmt.bufPrintZ(&num_buf, "{d}", .{i}) catch unreachable,
                .default_value_ptr = null,
                .alignment = @alignOf(ArgTuple),
                .is_comptime = false,
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

pub fn ApplicationContext(comptime Storage: type, comptime Modules: anytype) type {
    return struct {
        pub const AllContexts: type = GatherAllContext(Storage, Modules);
        pub const AllInitArgs: type = GatherAllInitArgs(AllContexts);

        context: AllContexts,

        pub fn init(self: *@This(), allocator: std.mem.Allocator, args: AllInitArgs) !void {
            self.context = undefined;
            comptime var arg_index = 0;
            inline for (std.meta.fields(AllContexts)) |field| {
                const module = &@field(self.context, field.name);
                module.* = try allocator.create(@typeInfo(field.type).pointer.child);
                if (@hasDecl(@typeInfo(field.type).pointer.child, "init")) {
                    const init_args = args[arg_index];
                    try @call(.auto, @typeInfo(field.type).pointer.child.init, .{ module.*, allocator } ++ if (@TypeOf(args) == void) .{} else init_args);
                    arg_index += 1;
                }
            }
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            const fields: []const std.builtin.Type.StructField = std.meta.fields(AllContexts);
            comptime var ite = std.mem.reverseIterator(fields);
            inline while (ite.next()) |field| {
                if (@hasDecl(@typeInfo(field.type).pointer.child, "deinit")) {
                    @field(self.context, field.name).deinit(allocator);
                }
                allocator.destroy(@field(self.context, field.name));
            }
        }

        pub fn get_context(self: *@This(), comptime enum_value: std.meta.FieldEnum(AllContexts)) blk: {
            break :blk std.meta.fieldInfo(AllContexts, enum_value).type;
        } {
            return @field(self.context, @tagName(enum_value));
        }
    };
}
