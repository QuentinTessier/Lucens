const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("zglfw");
const Inlucere = @import("Inlucere");
const Mesh = @import("./3D/Mesh.zig");
const math = @import("zmath");
const SinglePoolAllocator = @import("./graphics/SinglePoolAllocator.zig").GPUSinglePoolAllocator;

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

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
    const window = try glfw.Window.create(1280, 720, "zig-gamedev: minimal_glfw_gl", null);
    glfw.makeContextCurrent(window);
    try Inlucere.init(glfw.getProcAddress);
    var device: Inlucere.Device = undefined;
    defer {
        device.deinit();
        Inlucere.deinit();
        window.destroy();
    }

    try device.init(allocator);

    var mesh = try Mesh.initFromObj(allocator, "./assets/meshes/suzanne.obj");
    defer mesh.deinit(allocator);

    var mesh_allocator: SinglePoolAllocator = undefined;
    defer mesh_allocator.deinit();
    try mesh_allocator.init("mesh_allocator", allocator, @sizeOf(Mesh.Vertex) * 100_000);

    const allocation = try mesh_allocator.alloc(@sizeOf(Mesh.Vertex) * mesh.positions.len);

    const vertices = allocation.cast(Mesh.Vertex);
    for (vertices, mesh.positions, mesh.normals, mesh.tangents, mesh.texCoords) |*vertex, position, normal, tangent, texCoord| {
        vertex.position = position;
        vertex.normal = normal;
        vertex.tangent = tangent;
        vertex.texCoord = texCoord;
    }

    allocation.flush();
    const info = allocation.binding();
    device.bindStorageBuffer(0, info.buffer, .{ ._range = .{ info.offset, info.size } });

    const scene = math.mul(
        math.lookAtRh(
            math.f32x4(10.0, 10.0, 10.0, 1.0),
            math.f32x4(0.0, 0.0, 0.0, 1.0),
            math.f32x4(0.0, 1.0, 0.0, 1.0),
        ),
        math.perspectiveFovRhGl(0.25 * std.math.pi, 800 / 800, 0.1, 100),
    );
    const scene_buffer: Inlucere.Device.DynamicBuffer = try .init("scene", std.mem.asBytes(&scene), @sizeOf(math.Mat));
    defer scene_buffer.deinit();

    const instances: [3]math.Mat = .{
        math.translation(-2, 0.0, 0.0),
        math.identity(),
        math.translation(2, 0.0, 0.0),
    };
    const instance_buffer: Inlucere.Device.DynamicBuffer = try .init("instance", std.mem.asBytes(&instances), @sizeOf(math.Mat));
    defer instance_buffer.deinit();

    const elements: Inlucere.Device.StaticBuffer = .init("indices", std.mem.sliceAsBytes(mesh.indices), @sizeOf(u32));
    defer elements.deinit();

    device.bindUniformBuffer(0, scene_buffer.toBuffer(), Inlucere.Device.Buffer.Binding.whole());
    device.bindStorageBuffer(0, instance_buffer.toBuffer(), Inlucere.Device.Buffer.Binding.whole());

    const pipeline = try loadMeshPipeline(allocator, &device);
    _ = pipeline;
    while (!window.shouldClose()) {
        glfw.pollEvents();

        device.clearSwapchain(.{
            .colorLoadOp = .clear,
        });
        if (device.bindGraphicPipeline("DefaultMeshPipeline")) {
            device.bindElementBuffer(elements.toBuffer(), .u32);
            device.bindVertexBuffer(0, info.buffer, info.offset, @sizeOf(Mesh.Vertex));
            device.drawElements(@intCast(mesh.indices.len), 3, 0, 0, 0);
        }

        window.swapBuffers();
    }
}
