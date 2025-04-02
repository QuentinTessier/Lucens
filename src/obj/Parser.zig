const std = @import("std");

pub const Vertex = struct {
    position: u32,
    texCoords: u32,
    normal: u32,
};

pub const Triangle = struct {
    vertices: [3]Vertex,
};

pub const ParseResult = struct {
    allocator: std.mem.Allocator,
    name: []u8,
    positions: std.ArrayListUnmanaged([3]f32),
    texcoords: std.ArrayListUnmanaged([2]f32),
    normals: std.ArrayListUnmanaged([3]f32),
    faces: std.ArrayListUnmanaged(Triangle),

    pub fn init(self: *ParseResult, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.name = &.{};
        self.positions = .{};
        self.texcoords = .{};
        self.normals = .{};
        self.faces = .{};
    }

    pub fn deinit(self: *ParseResult) void {
        self.allocator.free(self.name);
        self.positions.deinit(self.allocator);
        self.texcoords.deinit(self.allocator);
        self.normals.deinit(self.allocator);
        self.faces.deinit(self.allocator);
    }
};

pub const Parser = @This();

const ParseLineFn = *const fn (*ParseResult, []const u8) anyerror!void;
const ParseLine = struct {
    code: []const u8,
    fnc: ParseLineFn,
};

fn parseVertex(result: *ParseResult, line: []const u8) anyerror!void {
    var ite = std.mem.split(u8, line, " ");

    var vertex: [4]f32 = .{ 0, 0, 0, 0 };
    var counter: usize = 0;
    while (ite.next()) |f| {
        if (counter < 4) {
            const value = try std.fmt.parseFloat(f32, f);
            vertex[counter] = value;
            counter += 1;
        }
    }
    try result.positions.append(result.allocator, .{ vertex[0], vertex[1], vertex[2] });
}

fn parseNormal(result: *ParseResult, line: []const u8) anyerror!void {
    var ite = std.mem.split(u8, line, " ");

    var vertex: [4]f32 = .{ 0, 0, 0, 0 };
    var counter: usize = 0;
    while (ite.next()) |f| {
        if (counter < 4) {
            const value = try std.fmt.parseFloat(f32, f);
            vertex[counter] = value;
            counter += 1;
        }
    }
    try result.normals.append(result.allocator, .{ vertex[0], vertex[1], vertex[2] });
}

fn parseTexCoords(result: *ParseResult, line: []const u8) anyerror!void {
    var ite = std.mem.split(u8, line, " ");

    var vertex: [4]f32 = .{ 0, 0, 0, 0 };
    var counter: usize = 0;
    while (ite.next()) |f| {
        if (counter < 4) {
            const value = std.fmt.parseFloat(f32, f) catch |e| {
                return e;
            };
            vertex[counter] = value;
            counter += 1;
        }
    }
    try result.texcoords.append(result.allocator, .{ vertex[0], vertex[1] });
}

fn parseComment(_: *ParseResult, _: []const u8) anyerror!void {}

fn parseFace(content: []const u8) !Vertex {
    var ite = std.mem.split(u8, content, "/");

    var face: [3]u32 = .{ 0, 0, 0 };
    var counter: usize = 0;
    while (ite.next()) |int| {
        if (counter < 3) {
            const value = try std.fmt.parseInt(u32, int, 10);
            face[counter] = value;
            counter += 1;
        }
    }
    return Vertex{ .position = face[0], .texCoords = face[1], .normal = face[2] };
}

fn parseTriangle(result: *ParseResult, line: []const u8) anyerror!void {
    var ite = std.mem.split(u8, line, " ");

    var faces: [3]Vertex = undefined;
    var counter: usize = 0;
    while (ite.next()) |face| {
        if (counter < 3) {
            faces[counter] = try parseFace(face);
            counter += 1;
        }
    }
    try result.faces.append(result.allocator, .{
        .vertices = faces,
    });
}

const Parsers = [_]ParseLine{
    .{ .code = "vt", .fnc = parseTexCoords },
    .{ .code = "vn", .fnc = parseNormal },
    .{ .code = "#", .fnc = parseComment },
    .{ .code = "v", .fnc = parseVertex },
    .{ .code = "f", .fnc = parseTriangle },
};

pub fn getNumberOfOject(allocator: std.mem.Allocator, content: []const u8) ![]usize {
    const delimiter = if (@import("builtin").os.tag == .windows) "\r\n" else "\n";
    var ite = std.mem.split(u8, content, delimiter);
    var indices = std.ArrayList(usize).init(allocator);

    var offset: usize = 0;
    while (ite.next()) |line| {
        if (std.mem.startsWith(u8, line, "o")) {
            try indices.append(offset);
        }
        offset += line.len;
    }
    return indices.toOwnedSlice();
}

pub fn parseObject(allocator: std.mem.Allocator, content: []const u8) !ParseResult {
    const delimiter = if (@import("builtin").os.tag == .windows) "\r\n" else "\n";
    var ite = std.mem.split(u8, content, delimiter);
    var result: ParseResult = undefined;

    result.init(allocator);

    while (ite.next()) |line| {
        for (Parsers) |parser| {
            if (std.mem.startsWith(u8, line, parser.code)) {
                try parser.fnc(&result, line[parser.code.len + 1 ..]);
                break;
            }
        } else {
            if (std.mem.startsWith(u8, line, "o")) {
                result.name = try allocator.dupe(u8, line[2..]);
            }
        }
    }
    return result;
}

pub fn parse(allocator: std.mem.Allocator, content: []const u8) ![]ParseResult {
    const indices = try getNumberOfOject(allocator, content);
    defer allocator.free(indices);
    std.log.info("Found {} objects", .{indices.len});

    if (indices.len <= 1) {
        var result = try parseObject(allocator, content);
        if (indices.len == 0) result.name = try allocator.dupe(u8, "NoName");

        return allocator.dupe(ParseResult, &.{result});
    } else {
        var objects = std.ArrayList(ParseResult).init(allocator);
        for (indices[0 .. indices.len - 2], 0..) |start, i| {
            const end = indices[i + 1];

            const subContent = content[start..end];
            try objects.append(try parseObject(allocator, subContent));
        }
        try objects.append(try parseObject(allocator, content[indices[indices.len - 1]..]));
        return objects.toOwnedSlice();
    }
}
