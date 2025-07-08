const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("zglfw");
const Inlucere = @import("Inlucere");
const Mesh = @import("./3D/Mesh.zig");
const math = @import("zmath");
const SinglePoolAllocator = @import("./graphics/SinglePoolAllocator.zig").GPUSinglePoolAllocator;
const ObjectPoolAllocator = @import("./graphics/ObectPoolAllocator.zig").ObjectPoolAllocator;
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
        self.device.deinit();
        allocator.destroy(self.device);
        self.window.destroy();
    }
};

pub const PushConstant = extern struct {
    g_num_elements: u32,
};

pub const SortContext = struct {
    executed: bool = false,
    data: []const u32,
    push_constant: Inlucere.Device.DynamicBuffer,
    buffer1: Inlucere.Device.DynamicBuffer,
    buffer2: Inlucere.Device.DynamicBuffer,

    pub fn init(data: []const u32) !SortContext {
        std.log.info("Creating a sorting context for {} elements", .{data.len});
        const size_as_u32: PushConstant = .{ .g_num_elements = @intCast(data.len) };
        const push_constant: Inlucere.Device.DynamicBuffer = try .init("radix_sort_push_constants", std.mem.asBytes(&size_as_u32), @sizeOf(PushConstant));
        const buffer1: Inlucere.Device.DynamicBuffer = try .init("radix_sort_buffer_1", std.mem.sliceAsBytes(data), @sizeOf(u32));
        const buffer2: Inlucere.Device.DynamicBuffer = try .initEmpty("radix_sort_buffer_2", @intCast(data.len * @sizeOf(u32)), @sizeOf(u32));
        return .{
            .data = data,
            .push_constant = push_constant,
            .buffer1 = buffer1,
            .buffer2 = buffer2,
        };
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

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    var engine: Engine = undefined;
    defer engine.deinit(allocator);

    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.context_version_major, 4);
    glfw.windowHint(.context_version_minor, 6);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.opengl_debug_context, true);
    engine.window = try glfw.Window.create(1280, 720, "lucens", null);
    glfw.makeContextCurrent(engine.window);

    var ext = try std.BoundedArray([]const u8, 32).init(0);
    try ext.append("GL_KHR_shader_subgroup_arithmetic");
    try Inlucere.init(glfw.getProcAddress, ext.slice());
    engine.device = try allocator.create(Inlucere.Device);
    try engine.device.init(allocator);

    engine.storage = try allocator.create(Storage);
    engine.storage.* = try .init(allocator);

    _ = try engine.device.createComputePipeline("SingleRadixSortPipeline", @embedFile("single_radixsort.comp"));

    const data = try allocator.alloc(u32, 16);
    defer allocator.free(data);
    for (data, 0..) |*item, i| {
        item.* = @intCast(i);
    }
    rand.shuffle(u32, data);

    for (data) |item| {
        std.debug.print("{} ", .{item});
    }
    std.debug.print("\n", .{});

    var sort_context: SortContext = try .init(data);

    // const gpu_mapped = Inlucere.gl.mapNamedBuffer(sort_context.buffer2.handle, Inlucere.gl.READ_ONLY);
    // if (gpu_mapped == null) {
    //     std.log.err("Failed to map memory", .{});
    //     return;
    // }
    // const gpu_memory: [*]u32 = @ptrCast(@alignCast(gpu_mapped.?));
    // const gpu_memory_slice = gpu_memory[0..data.len];
    // @memcpy(data, gpu_memory_slice);

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

        if (!sort_context.executed) {
            sort_context.executed = true;

            if (engine.device.bindComputePipeline("SingleRadixSortPipeline")) {
                engine.device.bindUniformBuffer(2, sort_context.push_constant.toBuffer(), .whole());
                engine.device.bindStorageBuffer(0, sort_context.buffer1.toBuffer(), .whole());
                engine.device.bindStorageBuffer(1, sort_context.buffer2.toBuffer(), .whole());
                engine.device.dispatch(1, 1, 1);
                engine.device.setMemoryBarrier(.{
                    .ShaderStorageBarrier = true,
                });
            }

            var sync = engine.device.fence();
            const res = try sync.wait(Inlucere.gl.TIMEOUT_IGNORED);
            std.log.info("Done sorting !", .{});

            switch (res) {
                .Success => {
                    Inlucere.gl.getNamedBufferSubData(sort_context.buffer2.handle, 0, @intCast(data.len * @sizeOf(u32)), @ptrCast(data.ptr));
                },
                .Timeout => {
                    std.log.warn("Fence timeout", .{});
                },
            }
            sync.deinit();

            for (data) |item| {
                std.debug.print("{} ", .{item});
            }
            std.debug.print("\n", .{});
        }

        engine.window.swapBuffers();
    }
}
