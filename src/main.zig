const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("zglfw");
const Inlucere = @import("Inlucere");
const gl = Inlucere.gl;
const Mesh = @import("3D/Mesh.zig");
const MeshManager = @import("3D/MeshManager.zig");
const Camera = @import("3D/Camera.zig");
const zmath = @import("zmath");
const MeshPipeline = @import("mesh_pipeline.zig");
const MaterialSystem = @import("material_system.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub const MeshData = extern struct {
    model_matrix: zmath.Mat,
    color: [4]f32,
};

const SceneUniform = extern struct {
    view: zmath.Mat,
    proj: zmath.Mat,
    view_pos: [4]f32,
};

fn read_file(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const size = try file.getEndPos();

    return try file.readToEndAlloc(allocator, size);
}

pub const UploadedMesh = struct {
    vertices: u32,
    indices: u32,
    primitive_count: u32,
};

fn upload_mesh(mesh: *const Mesh) !UploadedMesh {
    var buffers: [2]u32 = .{ 0, 0 };
    gl.createBuffers(2, (&buffers).ptr);
    gl.namedBufferStorage(
        buffers[0],
        @intCast(@sizeOf(Mesh.Vertex) * mesh.positions.len),
        null,
        gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT,
    );

    const ptr = gl.mapNamedBufferRange(
        buffers[0],
        0,
        @intCast(@sizeOf(Mesh.Vertex) * mesh.positions.len),
        gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT,
    ) orelse return error.failed;

    const bytes: [*]u8 = @ptrCast(ptr);
    const casted: [*]Mesh.Vertex = @ptrCast(@alignCast(bytes));
    const slice = casted[0..mesh.positions.len];

    for (slice, mesh.positions, mesh.normals, mesh.tangents, mesh.texCoords) |*v, p, n, t, tex| {
        v.position = .{ p[0], p[1], p[2], 0.0 };
        v.normal = .{ n[0], n[1], n[2], 0.0 };
        v.tangent = .{ t[0], t[1], t[2], 0.0 };
        v.texCoord = tex;
    }

    gl.namedBufferStorage(buffers[1], @intCast(@sizeOf(u32) * mesh.indices.len), @ptrCast(mesh.indices.ptr), 0);
    return UploadedMesh{
        .primitive_count = @intCast(mesh.indices.len),
        .vertices = buffers[0],
        .indices = buffers[1],
    };
}

fn upload_scene_data(buffer: u32, width: f32, height: f32, fov: f32, camera: *const Camera) void {
    var mat: zmath.Mat = zmath.identity();

    const view = camera.getView();
    const projection = camera.getProjection(width, height, fov);
    mat = zmath.mul(projection, view);
    gl.namedBufferData(buffer, @sizeOf(zmath.Mat), @ptrCast(&mat), gl.DYNAMIC_DRAW);
}

pub const Context = struct {
    mesh_manager: MeshManager,
    mesh_pipeline: MeshPipeline,
    material_system: MaterialSystem,

    scene_uniform_buffer: Inlucere.Device.MappedBuffer,
    light_buffer: Inlucere.Device.MappedBuffer,

    pub fn load_scene_buffer(self: *Context, scene_uniform_data: *const SceneUniform) !void {
        self.scene_uniform_buffer = try .init("scene", SceneUniform, &[1]SceneUniform{scene_uniform_data.*}, .ExplicitFlushed, .{});
    }

    pub fn load_light_buffer(self: *Context) !void {
        const LightBuffer = extern struct {
            n: [4]u32 = .{ 2, 0, 0, 0 },
            cpu_lights: [2][2][4]f32 = .{
                .{ .{ 5, 0, 0, 1 }, .{ 1, 1, 1, 1 } },
                .{ .{ 0, 5, 0, 1 }, .{ 1, 1, 1, 1 } },
            },
        };

        const light_buffer = LightBuffer{};

        self.light_buffer = try .init("lights", LightBuffer, &[1]LightBuffer{light_buffer}, .ExplicitFlushed, .{});
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

    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.context_version_major, 4);
    glfw.windowHint(.context_version_minor, 6);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.opengl_debug_context, true);
    const window = try glfw.createWindow(1280, 720, "zig-gamedev: minimal_glfw_gl", null);
    defer glfw.destroyWindow(window);

    glfw.makeContextCurrent(window);

    try Inlucere.init(glfw.getProcAddress);
    defer Inlucere.deinit();

    var context: Context = .{
        .mesh_manager = try .init(allocator),
        .mesh_pipeline = undefined,
        .material_system = undefined,
        .scene_uniform_buffer = undefined,
        .light_buffer = undefined,
    };
    defer {
        context.mesh_manager.deinit();
        context.material_system.deinit(allocator);
        context.mesh_pipeline.deinit(allocator);
        context.light_buffer.deinit();
        context.scene_uniform_buffer.deinit();
    }

    const camera = Camera{
        .position = .{ 10, 0, 0 },
        .psi = std.math.pi / 2.0,
        .theta = -std.math.pi / 2.0,
    };
    const scene_uniform_cpu = SceneUniform{
        .view = zmath.lookAtRh(.{ 0, 10, 10, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 1, 0, 0 }),
        .proj = camera.getProjection(1280, 720, 45.0),
        .view_pos = .{ camera.position[0], camera.position[1], camera.position[2], 1.0 },
    };

    try context.load_scene_buffer(&scene_uniform_cpu);
    try context.load_light_buffer();

    const suzanne = try context.mesh_manager.loadObj("./assets/meshes/suzanne.obj");
    _ = try context.mesh_manager.makeGPUResident(suzanne);

    const sphere = try context.mesh_manager.loadObj("./assets/meshes/sphere.obj");
    _ = try context.mesh_manager.makeGPUResident(sphere);

    const cube = try context.mesh_manager.loadObj("./assets/meshes/cube.obj");
    _ = try context.mesh_manager.makeGPUResident(cube);

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

    context.mesh_pipeline = try .init(allocator, &.{
        .vertex_array = vao,
        .vertex_buffer = context.mesh_manager.gpu_vertices_allocator.gpuMemory.toBuffer(),
        .index_buffer = context.mesh_manager.gpu_indices_allocator.gpuMemory.toBuffer(),
        .scene_uniform_buffer = context.scene_uniform_buffer.toBuffer(),
        .light_buffer = context.light_buffer.toBuffer(),
    });
    context.material_system = try .init();

    gl.clearColor(0, 0, 0, 1);
    gl.enable(gl.DEPTH_TEST);

    var timer = try std.time.Timer.start();

    const purple = try context.material_system.add_mat(allocator, .{
        .color = .{ 1, 0, 1, 1 },
    });
    const purple_slot = try context.material_system.make_resident(purple);
    std.log.info("Binding Purple to slot {}", .{purple_slot});
    const blue = try context.material_system.add_mat(allocator, .{
        .color = .{ 0, 0, 1, 1 },
    });
    const blue_slot = try context.material_system.make_resident(blue);
    std.log.info("Binding Blue to slot {}", .{blue_slot});
    const green = try context.material_system.add_mat(allocator, .{
        .color = .{ 0, 1, 0, 1 },
    });
    const green_slot = try context.material_system.make_resident(green);
    std.log.info("Binding Green to slot {}", .{green_slot});

    try context.mesh_pipeline.add_instance(allocator, suzanne, &.{
        .transform = zmath.translation(2, 0, 0),
        .material_id = @intCast(purple_slot),
        .binding_info = context.mesh_manager.getBindingInfo(suzanne).?,
    });

    try context.mesh_pipeline.add_instance(allocator, suzanne, &.{
        .transform = zmath.translation(2, 0, 2),
        .material_id = @intCast(blue_slot),
        .binding_info = context.mesh_manager.getBindingInfo(suzanne).?,
    });

    try context.mesh_pipeline.add_instance(allocator, suzanne, &.{
        .transform = zmath.translation(2, 0, -2),
        .material_id = @intCast(green_slot),
        .binding_info = context.mesh_manager.getBindingInfo(suzanne).?,
    });

    try context.mesh_pipeline.add_instance(allocator, sphere, &.{
        .transform = zmath.identity(),
        .material_id = @intCast(purple_slot),
        .binding_info = context.mesh_manager.getBindingInfo(sphere).?,
    });

    try context.mesh_pipeline.add_instance(allocator, sphere, &.{
        .transform = zmath.translation(0, 0, 2),
        .material_id = @intCast(blue_slot),
        .binding_info = context.mesh_manager.getBindingInfo(sphere).?,
    });

    try context.mesh_pipeline.add_instance(allocator, sphere, &.{
        .transform = zmath.translation(0, 0, -2),
        .material_id = @intCast(green_slot),
        .binding_info = context.mesh_manager.getBindingInfo(sphere).?,
    });

    try context.mesh_pipeline.add_instance(allocator, cube, &.{
        .transform = zmath.translation(-2, 0, 0),
        .material_id = @intCast(purple_slot),
        .binding_info = context.mesh_manager.getBindingInfo(cube).?,
    });

    try context.mesh_pipeline.add_instance(allocator, cube, &.{
        .transform = zmath.mul(zmath.scaling(0.5, 0.5, 0.5), zmath.translation(-2, 0, 2)),
        .material_id = @intCast(blue_slot),
        .binding_info = context.mesh_manager.getBindingInfo(cube).?,
    });

    try context.mesh_pipeline.add_instance(allocator, cube, &.{
        .transform = zmath.mul(zmath.rotationZ(std.math.degreesToRadians(45)), zmath.translation(-2, 0, -2)),
        .material_id = @intCast(green_slot),
        .binding_info = context.mesh_manager.getBindingInfo(cube).?,
    });

    context.mesh_pipeline.bind();
    gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, 4, context.material_system.buffer.handle);
    while (!window.shouldClose()) {
        glfw.pollEvents();

        const nano = timer.lap();
        const delta_time = @as(f32, @floatFromInt(nano)) / @as(f32, std.time.ns_per_ms);
        _ = delta_time;

        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        context.mesh_pipeline.draw();

        window.swapBuffers();
    }
}
