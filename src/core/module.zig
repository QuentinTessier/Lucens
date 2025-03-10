const std = @import("std");

pub const LucensModule = struct {
    name: []const u8,
    user_init: *const fn (*LucensModule, std.mem.Allocator) anyerror!void,
    user_deinit: *const fn (*LucensModule) void,

    _core_free: *const fn (*LucensModule, std.mem.Allocator) void = undefined,

    pub fn as(self: *LucensModule, comptime T: type) *T {
        return @fieldParentPtr("base", self);
    }

    pub fn validate(comptime T: type) void {
        if (!@hasField(T, "base")) {
            @compileError("Module: " ++ @typeName(T) ++ " needs a field name `base` with type Module");
        }

        if (@FieldType(T, "base") != LucensModule) {
            @compileError("Module: " ++ @typeName(T) ++ " as a field named `base` but of wrong type, expected Module");
        }

        if (!@hasDecl(T, "init_base")) {
            @compileError("Module: " ++ @typeName(T) ++ " doesn't have `pub const init_base: Module = .{...}` defined");
        }

        if (@TypeOf(T.init_base) != LucensModule) {
            @compileError("Module: " ++ @typeName(T) ++ " does have `init_base` defined but expected type Module");
        }
    }
};
