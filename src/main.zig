const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("zglfw");
const Inlucere = @import("Inlucere");
const Mesh = @import("./3D/Mesh.zig");
const math = @import("zmath");
const SinglePoolAllocator = @import("./graphics/SinglePoolAllocator.zig").GPUSinglePoolAllocator;
const MeshManager = @import("./3D/MeshManager.zig");
const ecez = @import("ecez");
const Components = @import("components.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

const PerInstance = struct {
    transform: math.Mat,
    material: u32,
    min: [2]f32,
    max: [2]f32,
};

const Storage = ecez.CreateStorage(.{
    Components.Transform,
    Components.MeshID,
    Components.Material,
});

const Queries = struct {
    pub const CollectMesh = ecez.Query(struct {
        mesh_id: Components.MeshID,
        transform: Components.Transform,
        color: Components.Color,
    }, .{}, .{});

    pub const Transforms = ecez.Query(struct {
        entity: ecez.Entity,
        transform: *Components.Transform,
    }, .{}, .{});

    pub const DirtyTransforms = ecez.Query(struct {
        entity: ecez.Entity,
        transform: *Components.Transform,
    }, .{Components.DirtyTransform}, .{});
};

pub fn loadMeshPipeline(allocator: std.mem.Allocator, device: *Inlucere.Device) !*Inlucere.Device.GraphicPipeline {
    const vertex_sources = try blk: {
        const vertex_file = try std.fs.cwd().openFile("./assets/shaders/mesh_instanced.vs", .{});
        defer vertex_file.close();

        const file_size = try vertex_file.getEndPos();
        break :blk vertex_file.readToEndAlloc(allocator, file_size);
    };
    defer allocator.free(vertex_sources);

    const fragment_sources = try blk: {
        const fragment_file = try std.fs.cwd().openFile("./assets/shaders/red.fs", .{});
        defer fragment_file.close();

        const file_size = try fragment_file.getEndPos();
        break :blk fragment_file.readToEndAlloc(allocator, file_size);
    };
    defer allocator.free(fragment_sources);

    _ = try device.loadShader("DefaultMeshProgram", &.{
        .{ .stage = .Vertex, .source = vertex_sources },
        .{ .stage = .Fragment, .source = fragment_sources },
    });

    return device.createGraphicPipeline(
        "DefaultMeshPipeline",
        &.{
            .programs = &.{"DefaultMeshProgram"},
            .vertexInputState = .{
                .vertexAttributeDescription = &.{
                    .{ // position
                        .location = 0,
                        .binding = 0,
                        .inputType = .vec3,
                    },
                    .{ // normal
                        .location = 1,
                        .binding = 0,
                        .inputType = .vec3,
                    },
                    .{ // tangent
                        .location = 2,
                        .binding = 0,
                        .inputType = .vec3,
                    },
                    .{ // texCoords
                        .location = 3,
                        .binding = 0,
                        .inputType = .vec2,
                    },
                },
            },
        },
    );
}

pub const Engine = struct {
    device: *Inlucere.Device,
    window: *glfw.Window,
    storage: *Storage,
    mesh_manager: *MeshManager,
    material_manager: void,

    pub fn deinit(self: *Engine, allocator: std.mem.Allocator) void {
        self.storage.deinit();
        allocator.destroy(self.storage);
        self.mesh_manager.deinit();
        allocator.destroy(self.mesh_manager);
        self.device.deinit();
        allocator.destroy(self.device);
        self.window.destroy();
    }
};

pub fn main() !void {
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var engine: Engine = undefined;
    defer engine.deinit(allocator);

    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.context_version_major, 4);
    glfw.windowHint(.context_version_minor, 6);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    engine.window = try glfw.Window.create(1280, 720, "lucens", null);
    glfw.makeContextCurrent(engine.window);

    try Inlucere.init(glfw.getProcAddress);
    engine.device = try allocator.create(Inlucere.Device);
    try engine.device.init(allocator);

    engine.storage = try allocator.create(Storage);
    engine.storage.* = try .init(allocator);

    engine.mesh_manager = try allocator.create(MeshManager);

    engine.mesh_manager.* = try .init(allocator);

    const suzanne = try engine.mesh_manager.loadObj("./assets/meshes/suzanne.obj");
    _ = try engine.mesh_manager.makeGPUResident(suzanne);

    const sphere = try engine.mesh_manager.loadObj("./assets/meshes/sphere.obj");
    _ = try engine.mesh_manager.makeGPUResident(sphere);

    const e = try engine.storage.createEntity(.{ Components.Material{
        .base_color = .{ 1, 0, 0, 1 },
    }, Components.MeshID{
        .id = suzanne,
    }, Components.Transform{
        .cached_matrix = undefined,
        .position = .{ 0, 0, 0 },
        .scale = .{ 1, 1, 1 },
        .rotation = .{ 0, 0, 0 },
    } });
    _ = e;

    var last_time = glfw.getTime();
    while (!engine.window.shouldClose()) {
        glfw.pollEvents();
        const current_time = glfw.getTime();
        const delta_time = @as(f32, @floatCast(current_time - last_time));
        last_time = current_time;
        _ = delta_time;

        engine.device.clearSwapchain(.{
            .colorLoadOp = .clear,
        });

        engine.window.swapBuffers();
    }
}
