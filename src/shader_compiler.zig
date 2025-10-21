const std = @import("std");
const Inlucere = @import("Inlucere");

pub const ShaderCompiler = @This();

include_path: []const u8,

pub fn init(include_path: []const u8) ShaderCompiler {
    return .{
        .include_path = include_path,
    };
}

pub fn compile_shader(self: *ShaderCompiler, allocator: std.mem.Allocator, filepath: []const u8, stage: Inlucere.Device.Program.Stage) !u32 {
    const sources = try resolve_includes(allocator, filepath, self.include_path);

    const handle = Inlucere.gl.createShader(@intFromEnum(stage));
    try Inlucere.Device.Program.compileShader(handle, sources);

    return handle;
}

pub fn compile_program(self: *ShaderCompiler, allocator: std.mem.Allocator, filepathes: []const []const u8) !Inlucere.Device.Program {
    var shader_sources: std.array_list.Aligned(Inlucere.Device.Program.ShaderSource, null) = try .initCapacity(allocator, filepathes.len);
    defer {
        for (shader_sources.items) |item| {
            allocator.free(item.source);
        }
        shader_sources.deinit(allocator);
    }

    for (filepathes) |path| {
        shader_sources.appendAssumeCapacity(.{
            .stage = get_shader_stage(path) orelse return error.FailedToRetrieveExt,
            .source = try resolve_includes(allocator, path, self.include_path, true),
        });

        std.debug.print("Compiling {s}\n-------------------------------------------------------------\n", .{shader_sources.items[shader_sources.items.len - 1].source});
    }

    var program: Inlucere.Device.Program = undefined;
    try program.init(shader_sources.items);
    return program;
}

fn get_shader_stage(filepath: []const u8) ?Inlucere.Device.Program.Stage {
    const extensions: []const struct { []const u8, Inlucere.Device.Program.Stage } = &.{
        .{ ".vert", Inlucere.Device.Program.Stage.Vertex },
        .{ ".frag", Inlucere.Device.Program.Stage.Fragment },
        .{ ".comp", Inlucere.Device.Program.Stage.Compute },
        .{ ".tesc", Inlucere.Device.Program.Stage.TesselationControl },
        .{ ".tese", Inlucere.Device.Program.Stage.TesselationEvaluation },
    };
    for (extensions) |ext| {
        if (std.mem.endsWith(u8, filepath, ext.@"0")) {
            return ext.@"1";
        }
    }
    return null;
}

fn resolve_includes(allocator: std.mem.Allocator, filepath: []const u8, include_path: []const u8, root_file: bool) ![]u8 {
    var path = try allocator.alloc(u8, filepath.len + include_path.len);
    defer allocator.free(path);
    @memcpy(path[0..include_path.len], include_path);
    @memcpy(path[include_path.len..], filepath);

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buffer: [512]u8 = undefined;
    var reader = file.reader(&buffer);
    const interface = &reader.interface;

    var line_tag_buffer: [512]u8 = undefined;
    var result: std.array_list.Aligned(u8, null) = .empty;

    if (!root_file) {
        const line_tag = try std.fmt.bufPrint(&line_tag_buffer, "#line {} \"{s}\"\n", .{ 1, path });
        try result.insertSlice(allocator, 0, line_tag);
    }

    var line_number: usize = 1;
    while (interface.takeDelimiterExclusive('\n')) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, "#include")) {
            const start_quote = std.mem.indexOfAny(u8, trimmed, "\"<") orelse @panic("");
            const end_quote = std.mem.lastIndexOfAny(u8, trimmed, "\">") orelse @panic("");

            const include_filepath = trimmed[start_quote + 1 .. end_quote];
            const include_content = try resolve_includes(allocator, include_filepath, include_path, false);
            try result.appendSlice(allocator, include_content);
            allocator.free(include_content);
            const line_tag = try std.fmt.bufPrint(&line_tag_buffer, "#line {} \"{s}\"\n", .{ line_number + 1, path });
            try result.appendSlice(allocator, line_tag);
        } else {
            try result.appendSlice(allocator, line);
            try result.append(allocator, '\n');
        }
        line_number += 1;
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong => return err,
        error.ReadFailed => return err,
    }

    return result.toOwnedSlice(allocator);
}
