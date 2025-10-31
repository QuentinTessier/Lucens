pub const std = @import("std");
const ecez = @import("ecez");

pub const ScreenResize = struct {
    width: u32,
    height: u32,
};

pub const EventScreenResize = ecez.Event("ScreenResize", .{}, .{
    .EventArgument = ScreenResize,
    .run_on_main_thread = true,
});

pub const EventMouseMoved = struct {
    x: i32,
    y: i32,
};
