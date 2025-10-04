const std = @import("std");

pub const Vertex = struct {
    position: u32,
    texCoords: u32,
    normal: u32,
};

pub const Triangle = struct {
    vertices: [3]Vertex,
};

pub const Object = struct {
    name: []const u8,
    triangles: []Triangle,
};

pub const ParseResult = struct {
    positions: [][3]f32,
    texcoords: [][2]f32,
    normals: [][3]f32,
    objects: []Object,

    pub fn deinit(self: *ParseResult, allocator: std.mem.Allocator) void {
        allocator.free(self.positions);
        allocator.free(self.texcoords);
        allocator.free(self.normals);
        for (self.objects) |obj| {
            allocator.free(obj.name);
            allocator.free(obj.triangles);
        }
        allocator.free(self.objects);
    }
};

pub const Parser = @This();

const DataObject = struct {
    name: []u8,
    triangles: std.array_list.AlignedManaged(Triangle, null),
};

const DataStorage = struct {
    allocator: std.mem.Allocator,
    positions: std.array_list.AlignedManaged([3]f32, null),
    texcoords: std.array_list.AlignedManaged([2]f32, null),
    normals: std.array_list.AlignedManaged([3]f32, null),
    objects: std.array_list.AlignedManaged(DataObject, null),
    currentObject: ?*DataObject,
};

const ParseLineFn = *const fn (*DataStorage, []const u8) anyerror!void;
const ParseLine = struct {
    code: []const u8,
    fnc: ParseLineFn,
};

fn parseVertex(result: *DataStorage, line: []const u8) anyerror!void {
    var ite = std.mem.splitSequence(u8, line, " ");

    var vertex: [4]f32 = .{ 0, 0, 0, 0 };
    var counter: usize = 0;
    while (ite.next()) |f| {
        if (counter < 4) {
            const value = std.fmt.parseFloat(f32, f) catch |e| {
                std.log.err("{s}", .{f});
                return e;
            };
            vertex[counter] = value;
            counter += 1;
        }
    }
    try result.positions.append(.{ vertex[0], vertex[1], vertex[2] });
}

fn parseNormal(result: *DataStorage, line: []const u8) anyerror!void {
    var ite = std.mem.splitSequence(u8, line, " ");

    var vertex: [4]f32 = .{ 0, 0, 0, 0 };
    var counter: usize = 0;
    while (ite.next()) |f| {
        if (counter < 4) {
            const value = try std.fmt.parseFloat(f32, f);
            vertex[counter] = value;
            counter += 1;
        }
    }
    try result.normals.append(.{ vertex[0], vertex[1], vertex[2] });
}

fn parseTexCoords(result: *DataStorage, line: []const u8) anyerror!void {
    var ite = std.mem.splitSequence(u8, line, " ");

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
    try result.texcoords.append(.{ vertex[0], vertex[1] });
}

fn parseComment(_: *DataStorage, _: []const u8) anyerror!void {}

fn parseFace(content: []const u8) !Vertex {
    var ite = std.mem.splitSequence(u8, content, "/");

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

fn parseTriangle(result: *DataStorage, line: []const u8) anyerror!void {
    if (result.currentObject == null) {
        try parseObject(result, "Default");
    }
    var ite = std.mem.splitSequence(u8, line, " ");

    var faces: [3]Vertex = undefined;
    var counter: usize = 0;
    while (ite.next()) |face| {
        if (counter < 3) {
            faces[counter] = try parseFace(face);
            counter += 1;
        }
    }
    try result.currentObject.?.triangles.append(.{
        .vertices = faces,
    });
}

fn parseObject(result: *DataStorage, line: []const u8) anyerror!void {
    std.log.info("Found new object: {s}", .{line});
    const newCurrentObject = try result.objects.addOne();
    newCurrentObject.* = .{
        .name = try result.allocator.dupe(u8, line),
        .triangles = std.array_list.AlignedManaged(Triangle, null).init(result.allocator),
    };
    result.currentObject = newCurrentObject;
}

const Parsers = [_]ParseLine{
    .{ .code = "vt", .fnc = parseTexCoords },
    .{ .code = "vn", .fnc = parseNormal },
    //.{ .code = "#", .fnc = parseComment },
    .{ .code = "v", .fnc = parseVertex },
    .{ .code = "f", .fnc = parseTriangle },
    .{ .code = "g", .fnc = parseObject },
};

pub fn parse(allocator: std.mem.Allocator, content: []const u8) !ParseResult {
    const delimiter = if (@import("builtin").os.tag == .windows) "\r\n" else "\n";
    var ite = std.mem.splitSequence(u8, content, delimiter);
    var storage: DataStorage = .{
        .allocator = allocator,
        .positions = .init(allocator),
        .texcoords = .init(allocator),
        .normals = .init(allocator),
        .objects = .init(allocator),
        .currentObject = null,
    };
    defer storage.objects.deinit();

    while (ite.next()) |line| {
        for (Parsers) |parser| {
            if (std.mem.startsWith(u8, line, parser.code)) {
                try parser.fnc(&storage, line[parser.code.len + 1 ..]);
                break;
            }
        }
        // } else {
        //     if (line.len > 2) {
        //         std.log.warn("Unrecognized/Unsupported tag {s}", .{line[0..2]});
        //     }
        // }
    }

    const objects = try allocator.alloc(Object, storage.objects.items.len);
    for (objects, 0..) |*obj, i| {
        obj.name = storage.objects.items[i].name;
        obj.triangles = try storage.objects.items[i].triangles.toOwnedSlice();
    }

    return ParseResult{
        .positions = try storage.positions.toOwnedSlice(),
        .normals = try storage.normals.toOwnedSlice(),
        .texcoords = try storage.texcoords.toOwnedSlice(),
        .objects = objects,
    };
}
