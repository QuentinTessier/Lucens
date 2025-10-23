const std = @import("std");

pub const ShaderCompiler = @This();

pub fn extract_filepath_include(_: *ShaderCompiler, allocator: std.mem.Allocator, line: []const u8, shader_source_folder: []const u8) ![]u8 {
    var filepath: std.array_list.Aligned(u8, null) = .empty;
    try filepath.appendSlice(allocator, shader_source_folder);

    const start_quote = std.mem.indexOfScalar(u8, line, '<') orelse @panic("");
    const end_quote = std.mem.indexOfScalar(u8, line, '>') orelse @panic("");

    try filepath.appendSlice(allocator, line[start_quote + 1 .. end_quote]);

    return filepath.toOwnedSlice(allocator);
}

pub fn insert_include_into_sources(
    _: *ShaderCompiler,
    allocator: std.mem.Allocator,
    filepath: []const u8,
    sources: *std.array_list.Aligned(u8, null),
    index: usize,
    len: usize,
) !void {
    var file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    const size = try file.getEndPos();
    if (size > len) {
        const byte_size = size - len;

        _ = try sources.addManyAt(allocator, index + len, byte_size);
        const slice = sources.items[index .. index + size];
        _ = try file.readAll(slice);
    } else {
        @memset(sources.items[index .. index + len], ' ');
        _ = try file.readAll(sources.items[index .. index + len]);
    }
}

pub fn resolve_include_dependencies(
    self: *ShaderCompiler,
    allocator: std.mem.Allocator,
    sources: *std.array_list.Aligned(u8, null),
    shader_source_folder: []const u8,
) !void {
    var file_stack: std.array_list.Aligned([]u8, null) = .empty;
    defer {
        for (file_stack.items) |item| {
            allocator.free(item);
        }
        file_stack.deinit(allocator);
    }

    var index: usize = 0;
    while (index < sources.items.len) : (index += 1) {
        if (sources.items[index] == '#' and std.mem.startsWith(u8, sources.items[index..], "#include")) {
            const end_of_line_index = std.mem.indexOfScalar(u8, sources.items[index..], '\n') orelse @panic("");
            const line = sources.items[index .. index + end_of_line_index];
            const filepath = try self.extract_filepath_include(allocator, line, shader_source_folder);
            try self.insert_include_into_sources(allocator, filepath, sources, index, line.len);
        }
    }

    return;
}
