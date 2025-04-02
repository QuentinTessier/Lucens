const std = @import("std");
pub const LucensModule = @import("module.zig").LucensModule;
pub const WindowingModule = @import("Modules/WindowingModule.zig");
pub const InlucereModule = @import("Modules/InlucereModule.zig");
pub const Renderer2DModule = @import("Modules/2D/RendererModule.zig");
const Scheduler = @import("scheduler.zig");

pub const LucensEngineContext = struct {
    allocator: std.mem.Allocator,
    modules: std.ArrayListUnmanaged(*LucensModule),
    scheduler: Scheduler,
    timer: std.time.Timer,
    delta_time: f32,
    running: bool,

    pub fn deinit(self: *@This()) void {
        var i = self.modules.items.len;
        while (i > 0) {
            i -= 1;
            self.modules.items[i].user_deinit(self.modules.items[i]);
            self.modules.items[i]._core_free(self.modules.items[i], self.allocator);
        }
        self.modules.deinit(self.allocator);
    }

    pub fn registerModule(self: *@This(), comptime T: type) !*T {
        comptime LucensModule.validate(T);
        const module_ptr = try self.allocator.create(T);
        module_ptr.base = T.init_base;
        module_ptr.base._core_free = struct {
            pub fn inline_free(base: *LucensModule, allocator: std.mem.Allocator) void {
                const ptr = base.as(T);
                allocator.destroy(ptr);
            }
        }.inline_free;

        try self.modules.append(self.allocator, &module_ptr.base);
        try module_ptr.base.user_init(&module_ptr.base, self.allocator);

        return module_ptr;
    }

    pub fn getModule(self: *@This(), comptime T: type, name: []const u8) ?*T {
        for (self.modules.items) |module| {
            if (std.mem.eql(u8, module.name, name)) {
                return module.as(T);
            }
        }
        return null;
    }
};

var _lucens_general_purpose_allocator: std.heap.DebugAllocator(.{}) = .init;
var _lucens_engine_context: ?*LucensEngineContext = null;

pub fn CreateLucensEngine() !*LucensEngineContext {
    std.debug.assert(_lucens_engine_context == null);

    _lucens_engine_context = try _lucens_general_purpose_allocator.allocator().create(LucensEngineContext);
    _lucens_engine_context.?.allocator = _lucens_general_purpose_allocator.allocator();
    _lucens_engine_context.?.modules = .empty;
    _lucens_engine_context.?.scheduler.init(_lucens_general_purpose_allocator.allocator());
    _lucens_engine_context.?.timer = try std.time.Timer.start();
    _lucens_engine_context.?.running = true;
    return _lucens_engine_context.?;
}

pub fn LucensEngine() *LucensEngineContext {
    std.debug.assert(_lucens_engine_context != null);

    return _lucens_engine_context.?;
}

pub fn ReleaseLucensEngine() void {
    if (_lucens_engine_context) |context| {
        context.deinit();
        _lucens_general_purpose_allocator.allocator().destroy(context);
    }
}

pub fn LucensEngineStop() void {
    std.debug.assert(_lucens_engine_context != null);

    _lucens_engine_context.?.running = false;
}

pub fn LucensEngineRun() anyerror!void {
    std.debug.assert(_lucens_engine_context != null);

    _lucens_engine_context.?.timer.reset();
    while (_lucens_engine_context.?.running) {
        const nano_delta_time = _lucens_engine_context.?.timer.lap();
        _lucens_engine_context.?.delta_time = @as(f32, @floatFromInt(nano_delta_time)) / std.time.ns_per_s;
        try _lucens_engine_context.?.scheduler.runPipeline(_lucens_engine_context.?.delta_time);
    }
}

pub fn LucensDeltaTime() f32 {
    std.debug.assert(_lucens_engine_context != null);

    return _lucens_engine_context.?.delta_time;
}

pub fn LucensDeclareDefault2DPipelineAndModules() anyerror!void {
    std.debug.assert(_lucens_engine_context != null);

    const context = _lucens_engine_context.?;

    const windowing = try context.registerModule(WindowingModule);
    const graphics = try context.registerModule(InlucereModule);
    const renderer = try context.registerModule(Renderer2DModule);

    try context.scheduler.createStep("OnFrameStart", .{});
    try context.scheduler.createStep("OnFrameUpdate", .{});
    try context.scheduler.createStep("OnFrameEnd", .{});

    try context.scheduler.addTask("OnFrameStart", "WindowingFrameStart", @ptrCast(&WindowingModule.onFrameStart), windowing, 100.0);
    try context.scheduler.addTask("OnFrameEnd", "DrawSprites", @ptrCast(&Renderer2DModule.tmp_draw), renderer, 1.0);
    try context.scheduler.addTask("OnFrameEnd", "WindowingFrameEnd", @ptrCast(&WindowingModule.onFrameEnd), windowing, 0.0);
    try context.scheduler.addTask("OnFrameStart", "ForceClear", @ptrCast(&InlucereModule.forceClearSwapchain), graphics, 99.0);
}
