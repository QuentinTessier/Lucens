const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("zglfw");
const Inlucere = @import("Inlucere");
const Mesh = @import("./3D/Mesh.zig");
const math = @import("zmath");
const SinglePoolAllocator = @import("./graphics/SinglePoolAllocator.zig").GPUSinglePoolAllocator;
const MeshManager = @import("./3D/MeshManager.zig");
const ecez = @import("ecez");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

var mesh_manager: MeshManager = undefined;

const Command = struct {
    id: u32,
    color: [3]f32,
    transform: math.Mat,

    pub fn lessThan(_: void, lhs: Command, rhs: Command) bool {
        return lhs.id < rhs.id;
    }
};
var render_command: std.ArrayList(Command) = undefined;

const Components = struct {
    pub const Transform = struct { matrix: math.Mat };
    pub const Color = struct {
        r: f32,
        g: f32,
        b: f32,
    };
    pub const MeshID = struct {
        id: u32,
    };
};

const Storage = ecez.CreateStorage(.{
    Components.Transform,
    Components.MeshID,
    Components.Color,
});

const Queries = struct {
    pub const CollectMesh = ecez.Query(struct {
        mesh_id: Components.MeshID,
        transform: Components.Transform,
        color: Components.Color,
    }, .{}, .{});
};

const Systems = struct {
    pub fn collectRenderableMeshes(collected_meshes: *Queries.CollectMesh) void {
        render_command.clearRetainingCapacity();
        while (collected_meshes.next()) |item| {
            if (!mesh_manager.isGPUResident(item.mesh_id.id)) {
                _ = mesh_manager.makeGPUResident(item.mesh_id.id) catch @panic("need to figure out how to handle errors in system !");
            }

            render_command.append(.{
                .id = item.mesh_id.id,
                .transform = item.transform.matrix,
                .color = .{
                    item.color.r,
                    item.color.g,
                    item.color.b,
                },
            }) catch @panic("need to figure out how to handle errors in system !");
        }
        std.sort.block(Command, render_command.items, void{}, Command.lessThan);
    }
};

const LoopDriving = ecez.Event("LoopDriving", .{
    Systems.collectRenderableMeshes,
});

const Scheduler = ecez.CreateScheduler(.{
    LoopDriving,
});

const Instance = extern struct {
    model_matrix: math.Mat,
    color: [4]f32,
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

    var storage = try Storage.init(allocator);
    defer storage.deinit();

    var scheduler = try Scheduler.init(.{
        .pool_allocator = allocator,
        .query_submit_allocator = allocator,
    });
    defer scheduler.deinit();

    mesh_manager = try .init(allocator);
    defer mesh_manager.deinit();

    render_command = .init(allocator);
    defer render_command.deinit();

    const suzanne = try mesh_manager.loadObj("./assets/meshes/suzanne.obj");
    _ = try mesh_manager.makeGPUResident(suzanne);

    const sphere = try mesh_manager.loadObj("./assets/meshes/sphere.obj");
    _ = try mesh_manager.makeGPUResident(sphere);

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

    const e1 = try storage.createEntity(.{ Components.MeshID{
        .id = suzanne,
    }, Components.Transform{
        .matrix = math.identity(),
    }, Components.Color{
        .r = 1.0,
        .g = 1.0,
        .b = 1.0,
    } });
    _ = e1;

    const e2 = try storage.createEntity(.{ Components.MeshID{
        .id = sphere,
    }, Components.Transform{
        .matrix = math.translation(-2.0, 0.0, 0.0),
    }, Components.Color{
        .r = 0.0,
        .g = 1.0,
        .b = 1.0,
    } });
    _ = e2;

    const instance_buffer: Inlucere.Device.MappedBuffer = try .initEmpty("instance", Instance, 64, .ExplicitFlushed, .{});
    defer instance_buffer.deinit();

    device.bindUniformBuffer(0, scene_buffer.toBuffer(), Inlucere.Device.Buffer.Binding.whole());
    device.bindStorageBuffer(0, instance_buffer.toBuffer(), Inlucere.Device.Buffer.Binding.whole());

    const pipeline = try loadMeshPipeline(allocator, &device);
    _ = pipeline;
    while (!window.shouldClose()) {
        glfw.pollEvents();

        device.clearSwapchain(.{
            .colorLoadOp = .clear,
        });

        scheduler.dispatchEvent(&storage, .LoopDriving, void{});
        scheduler.waitEvent(.LoopDriving);

        if (device.bindGraphicPipeline("DefaultMeshPipeline")) {
            device.bindElementBuffer(mesh_manager.gpu_indices_allocator.gpuMemory.toBuffer(), .u32);
            device.bindVertexBuffer(0, mesh_manager.gpu_vertices_allocator.gpuMemory.toBuffer(), 0, @sizeOf(Mesh.Vertex));
            var i: usize = 0;
            var current_id = render_command.items[0].id;
            var offset: usize = 0;
            var mapped_instance = instance_buffer.cast(Instance);
            while (i < render_command.items.len) : (i += 1) {
                if (current_id != render_command.items[i].id) {
                    instance_buffer.flushRange(0, @intCast(@sizeOf(Instance) * offset));
                    const binding_info = mesh_manager.getBindingInfo(current_id) orelse @panic("Better error handling");
                    device.drawElements(
                        @intCast(@divExact(binding_info.indices_size, @sizeOf(u32))),
                        @intCast(offset),
                        0,
                        @intCast(@divExact(binding_info.indices_offset, @sizeOf(u32))),
                        0,
                    );
                    current_id = render_command.items[i].id;
                }
                mapped_instance[offset] = .{
                    .model_matrix = render_command.items[i].transform,
                    .color = .{
                        render_command.items[i].color[0],
                        render_command.items[i].color[1],
                        render_command.items[i].color[2],
                        1.0,
                    },
                };
                offset += 1;
            }

            instance_buffer.flushRange(0, @intCast(@sizeOf(Instance) * offset));
            const binding_info = mesh_manager.getBindingInfo(current_id) orelse @panic("Better error handling");
            device.drawElements(
                @intCast(@divExact(binding_info.indices_size, @sizeOf(u32))),
                @intCast(offset),
                0,
                @intCast(@divExact(binding_info.indices_offset, @sizeOf(u32))),
                0,
            );
        }
        window.swapBuffers();
    }
}
