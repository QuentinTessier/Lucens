const std = @import("std");
const Lucens = @import("core/lucens.zig");
const WindowingModule = @import("core/Modules/WindowingModule.zig");
const InlucereModule = @import("core/Modules/InlucereModule.zig");
const Inlucere = @import("Inlucere");

pub fn main() !void {
    const context = Lucens.LucensEngine();
    defer Lucens.ReleaseLucensEngine();

    const windowing = try context.registerModule(WindowingModule);
    const graphics = try context.registerModule(InlucereModule);

    try context.scheduler.createStep("OnFrameStart", .{});
    try context.scheduler.createStep("OnFrameEnd", .{});
    try context.scheduler.addTask("OnFrameStart", "WindowingFrameStart", @ptrCast(&WindowingModule.onFrameStart), windowing, 100.0);
    try context.scheduler.addTask("OnFrameEnd", "WindowingFrameEnd", @ptrCast(&WindowingModule.onFrameEnd), windowing, 100.0);
    try context.scheduler.addTask("OnFrameStart", "ForceClear", @ptrCast(&InlucereModule.forceClearSwapchain), graphics, 99.0);

    try Lucens.LucensEngineRun();
}
