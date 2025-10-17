const std = @import("std");
const builtin = @import("builtin");
const ecez = @import("ecez");
const glfw = @import("zglfw");
const Inlucere = @import("Inlucere");
const gl = Inlucere.gl;
const zmath = @import("zmath");
const Mesh = @import("3D/Mesh.zig");
const LightSystem = @import("light_system.zig");

const Storage = @import("components.zig").Storage;
const MeshManagerGeneric = @import("graphics/mesh_buffer_manager.zig").MeshManager;
const StagingBuffer = @import("graphics/staging_buffer_manager.zig");
const MeshPipeline = @import("graphics/mesh_pipeline.zig");
const MeshManager = MeshManagerGeneric(u32, Mesh.Vertex);
const MaterialSystem = @import("graphics/material_system.zig");
const Camera = @import("3D/Camera.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

const SceneUniform = extern struct {
    view: zmath.Mat,
    proj: zmath.Mat,
    view_pos: [4]f32,
};

fn upload_mesh(allocator: std.mem.Allocator, mesh_manager: *MeshManager, staging_buffer: *StagingBuffer, handle: u32, mesh: *const Mesh) !?MeshManager.MeshHandle {
    var vertices: std.array_list.Aligned(Mesh.Vertex, null) = try .initCapacity(allocator, mesh.normals.len);
    defer vertices.deinit(allocator);
    for (mesh.positions, mesh.normals, mesh.tangents, mesh.texCoords) |pos, norm, tang, tex| {
        vertices.appendAssumeCapacity(.{
            .position = .{ pos[0], pos[1], pos[2], 1.0 },
            .normal = .{ norm[0], norm[1], norm[2], 1.0 },
            .tangent = .{ tang[0], tang[1], tang[2], 1.0 },
            .texCoord = .{ tex[0], tex[1] },
        });
    }

    return mesh_manager.alloc(
        allocator,
        handle,
        vertices.items,
        mesh.indices,
        staging_buffer,
    );
}

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

    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.context_version_major, 4);
    glfw.windowHint(.context_version_minor, 6);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.opengl_debug_context, true);
    const window = try glfw.createWindow(1280, 720, "Lucens", null);
    defer glfw.destroyWindow(window);

    glfw.makeContextCurrent(window);

    try Inlucere.init(glfw.getProcAddress);
    defer Inlucere.deinit();

    gl.clearColor(0, 0, 0, 1);
    gl.enable(gl.DEPTH_TEST);

    var staging_buffer: StagingBuffer = try .init(allocator, &.{});
    defer staging_buffer.deinit(allocator);

    var vao: Inlucere.Device.VertexArrayObject = undefined;
    vao.init(&.{ .vertexAttributeDescription = &.{
        .{
            .location = 0,
            .binding = 0,
            .inputType = .vec4,
        },
        .{
            .location = 1,
            .binding = 0,
            .inputType = .vec4,
        },
        .{
            .location = 2,
            .binding = 0,
            .inputType = .vec4,
        },
        .{
            .location = 3,
            .binding = 0,
            .inputType = .vec2,
        },
    } });
    defer vao.deinit();

    const camera = Camera{
        .position = .{ 10, 0, 0 },
        .psi = std.math.pi / 2.0,
        .theta = -std.math.pi / 2.0,
    };
    const scene_uniform_cpu = SceneUniform{
        .view = zmath.lookAtRh(.{ 0, 1, 10, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 1, 0, 0 }),
        .proj = camera.getProjection(1280, 720, 45.0),
        .view_pos = .{ camera.position[0], camera.position[1], camera.position[2], 1.0 },
    };
    var scene_uniform: Inlucere.Device.MappedBuffer = try .init("scene", SceneUniform, &[1]SceneUniform{scene_uniform_cpu}, .ExplicitFlushed, .{});
    defer scene_uniform.deinit();
    Inlucere.gl.objectLabel(
        Inlucere.gl.BUFFER,
        scene_uniform.handle,
        13,
        "scene_uniform",
    );

    gl.bindBufferBase(gl.UNIFORM_BUFFER, 0, scene_uniform.handle);

    var mesh_manager: MeshManager = undefined;
    try mesh_manager.init(allocator, 10_000, 15_000, vao.handle);
    defer mesh_manager.deinit(allocator);

    const suzanne_id: u32 = 1;
    var suzanne: Mesh = try .initFromObj(allocator, "./assets/meshes/suzanne.obj");
    defer suzanne.deinit(allocator);

    const sphere_id: u32 = 2;
    var sphere: Mesh = try .initFromObj(allocator, "./assets/meshes/sphere.obj");
    defer sphere.deinit(allocator);

    var vertices: std.array_list.Aligned(Mesh.Vertex, null) = try .initCapacity(allocator, suzanne.normals.len);
    defer vertices.deinit(allocator);
    for (suzanne.positions, suzanne.normals, suzanne.tangents, suzanne.texCoords) |pos, norm, tang, tex| {
        vertices.appendAssumeCapacity(.{
            .position = .{ pos[0], pos[1], pos[2], 1.0 },
            .normal = .{ norm[0], norm[1], norm[2], 1.0 },
            .tangent = .{ tang[0], tang[1], tang[2], 1.0 },
            .texCoord = .{ tex[0], tex[1] },
        });
    }

    staging_buffer.begin_frame();
    _ = try upload_mesh(allocator, &mesh_manager, &staging_buffer, suzanne_id, &suzanne);
    _ = try upload_mesh(allocator, &mesh_manager, &staging_buffer, sphere_id, &sphere);
    staging_buffer.end_frame();

    var material_system: MaterialSystem = undefined;
    try material_system.init(allocator);
    defer material_system.deinit(allocator);

    var mesh_pipeline: MeshPipeline = undefined;
    try mesh_pipeline.init(allocator, &mesh_manager, &material_system);
    defer mesh_pipeline.deinit(allocator);

    var light_system: LightSystem = try .init();
    defer light_system.deinit(allocator);

    try light_system.add_light(allocator, LightSystem.DirectionalLight{
        .color = .{ 1, 1, 1 },
        .direction = .{ 0, -1, 0 },
        .intensity = 100.0,
    });

    light_system.upload();
    gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, 3, light_system.buffer.handle);

    while (!window.shouldClose()) {
        glfw.pollEvents();

        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        material_system.begin();
        mesh_pipeline.begin();

        _ = try material_system.add_material(allocator, 0, .{
            .color = .{ 1, 1, 1, 1 },
        });
        _ = try material_system.add_material(allocator, 1, .{
            .color = .{ 0, 1, 1, 1 },
        });

        try mesh_pipeline.draw_instance(allocator, suzanne_id, zmath.identity(), 0);

        try mesh_pipeline.draw_instance(allocator, sphere_id, zmath.translation(-1.5, 0, 0), 1);
        try mesh_pipeline.draw_instance(allocator, sphere_id, zmath.translation(1.5, 0, 0), 1);

        mesh_pipeline.end();
        material_system.end(4);
        mesh_pipeline.draw();

        window.swapBuffers();
    }
}
