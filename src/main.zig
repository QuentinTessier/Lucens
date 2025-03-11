const std = @import("std");
const Lucens = @import("core/lucens.zig");
const WindowingModule = @import("core/Modules/WindowingModule.zig");
const InlucereModule = @import("core/Modules/InlucereModule.zig");
const Inlucere = @import("Inlucere");

pub fn main() !void {
    _ = try Lucens.CreateLucensEngine();
    defer Lucens.ReleaseLucensEngine();

    try Lucens.LucensDeclareDefault2DPipelineAndModules();

    try Lucens.LucensEngineRun();
}
