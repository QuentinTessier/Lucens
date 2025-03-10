const std = @import("std");

pub const Scheduler = @This();

pub const Task = struct {
    name: []const u8,
    function: *const fn (*anyopaque) anyerror!void,
    data: *anyopaque,
    priority: f32,
    isRecurring: bool,
    interval: f32,
    nextExecTime: f32,

    pub fn exec(self: *@This()) anyerror!void {
        return self.function(self.data);
    }
};

pub const Step = struct {
    name: []const u8,
    tasks: std.ArrayListUnmanaged(Task) = .{},
    isActive: bool = true,
};

allocator: std.mem.Allocator,
pipeline: std.ArrayListUnmanaged(Step) = .{},
stepIndices: std.StringHashMapUnmanaged(usize) = .{},
current_time: f32,

pub fn init(self: *@This(), allocator: std.mem.Allocator) void {
    self.allocator = allocator;
    self.pipeline = .{};
    self.stepIndices = .{};
    self.current_time = 0.0;
}

pub fn deinit(self: *@This()) void {
    for (self.pipeline.items) |*step| {
        step.tasks.deinit(self.allocator);
    }

    var ite = self.stepIndices.iterator();
    while (ite.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
    }

    self.pipeline.deinit(self.allocator);
    self.stepIndices.deinit(self.allocator);
}

pub const StepCreationOption = struct {
    default_state: bool = true,
    insert_index: isize = -1, // Appends by default
};

pub fn createStep(self: *@This(), name: []const u8, options: StepCreationOption) !void {
    if (self.stepIndices.contains(name)) {
        return;
    }

    const copy = try self.allocator.dupe(u8, name);

    if (options.insert_index < 0) {
        const index = self.pipeline.items.len;
        try self.pipeline.append(self.allocator, .{
            .name = copy,
            .tasks = .{},
            .isActive = options.default_state,
        });
        try self.stepIndices.put(self.allocator, copy, index);
    } else {
        const index: usize = @min(self.pipeline.items.len - 1, @as(usize, @intCast(options.insert_index)));
        try self.pipeline.insert(self.allocator, index, .{
            .name = copy,
            .tasks = .{},
            .isActive = options.default_state,
        });
        try self.stepIndices.put(self.allocator, copy, index);
    }
}

pub fn addTask(self: *@This(), step_name: []const u8, task_name: []const u8, fnc: *const fn (*anyopaque) anyerror!void, ctx: *anyopaque, priority: f32) !void {
    const index = self.stepIndices.get(step_name) orelse @panic("");
    const step: *Step = &self.pipeline.items[index];

    try step.tasks.append(self.allocator, Task{
        .name = task_name,
        .function = fnc,
        .data = ctx,
        .priority = priority,
        .isRecurring = false,
        .interval = 0.0,
        .nextExecTime = 0.0,
    });
}

pub fn addRecurringTask(self: *@This(), step_name: []const u8, task_name: []const u8, fnc: *const fn (*anyopaque) anyerror!void, ctx: *anyopaque, interval: f32, priority: f32) !void {
    const index = self.stepIndices.get(step_name) orelse @panic("");
    const step: *Step = &self.pipeline.items[index];

    try step.tasks.append(self.allocator, Task{
        .name = task_name,
        .function = fnc,
        .data = ctx,
        .priority = priority,
        .isRecurring = true,
        .interval = interval,
        .nextExecTime = 0.0,
    });
}

pub fn toggleStep(self: *@This(), step_name: []const u8) bool {
    const index = self.stepIndices.get(step_name) orelse @panic("");

    self.pipeline.items[index].isActive = !self.pipeline.items[index].isActive;
    return self.pipeline.items[index].isActive;
}

pub fn stepIndex(self: *@This(), step_name: []const u8) usize {
    return self.stepIndices.get(step_name) orelse @panic("");
}

pub fn runPipeline(self: *@This(), deltaTime: f32) anyerror!void {
    self.current_time += deltaTime;

    for (self.pipeline.items) |*step| {
        if (!step.isActive) continue;

        std.sort.block(Task, step.tasks.items, void{}, struct {
            pub fn lessThan(_: void, lhs: Task, rhs: Task) bool {
                return lhs.priority > rhs.priority;
            }
        }.lessThan);

        for (@as([]Task, step.tasks.items)) |*task| {
            if (!task.isRecurring) {
                try task.exec();
            } else {
                if (self.current_time >= task.nextExecTime) {
                    try task.exec();
                    task.nextExecTime = self.current_time + task.interval;
                }
            }
        }
    }
}

pub fn runStep(self: *@This(), step_name: []const u8) anyerror!void {
    const index = self.stepIndices.get(step_name) orelse @panic("");
    const step = &self.pipeline.items[index];

    for (@as([]Task, step.tasks.items)) |*task| {
        if (!task.isRecurring) {
            try task.exec();
        } else {
            if (self.current_time >= task.nextExecTime) {
                try task.exec();
                task.nextExecTime = self.current_time + task.interval;
            }
        }
    }
}

pub fn listSteps(self: *@This(), writer: anytype) !void {
    for (self.pipeline.items, 0..) |step, i| {
        try writer.print("{}: {s}\n", .{ i, step.name });
    }
}
