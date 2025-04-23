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

var current_offset: usize = 0;
var simulated_gpu_transform_buffer: []math.Mat = &.{};
var indirection_table_entity_to_offset: std.AutoArrayHashMapUnmanaged(ecez.Entity, usize) = .empty;
var indirection_table_offset_to_entity: std.AutoArrayHashMapUnmanaged(usize, ecez.Entity) = .empty;

pub fn get_instance_offset(entity: ecez.Entity) ?usize {
    return indirection_table_entity_to_offset.get(entity);
}

pub fn add_instance_to_indirection_table(allocator: std.mem.Allocator, entity: ecez.Entity) usize {
    const offset = current_offset;
    current_offset += 1;
    indirection_table_entity_to_offset.put(allocator, entity, offset) catch unreachable;
    indirection_table_offset_to_entity.put(allocator, offset, entity) catch unreachable;

    return offset;
}

const Components = struct {
    pub const Transform = struct {
        position: [3]f32,
        rotation: [3]f32,
        scale: [3]f32,

        cached_matrix: math.Mat,

        pub fn computeMatrix(self: *Transform) math.Mat {
            const translation = math.translationV(math.Vec{ self.position[0], self.position[1], self.position[2], 1.0 });
            const rotation = math.matFromRollPitchYawV(math.Vec{ self.rotation[0], self.rotation[1], self.rotation[2], 1.0 });
            const scale = math.scalingV(math.Vec{ self.scale[0], self.scale[1], self.scale[2], 1.0 });

            const matrix = math.mul(translation, math.mul(rotation, scale));
            self.cached_matrix = matrix;
            return matrix;
        }

        pub fn getMatrix(self: *Transform) math.Mat {
            return self.cached_matrix;
        }
    };
    pub const DirtyTransform = struct {};
    pub const Color = struct {
        r: f32,
        g: f32,
        b: f32,
    };
    pub const MeshID = struct {
        id: u32,
    };
};

const PerInstance = struct {
    transform: math.Mat,
    material: u32,
    min: [2]f32,
    max: [2]f32,
};

const Storage = ecez.CreateStorage(.{
    Components.Transform,
    Components.MeshID,
    Components.Color,
    Components.DirtyTransform,
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

    pub const ConstTransforms = ecez.Query(struct {
        entity: ecez.Entity,
        transform: *const Components.Transform,
    }, .{}, .{});

    pub const DirtyTransforms = ecez.Query(struct {
        entity: ecez.Entity,
        transform: *Components.Transform,
    }, .{Components.DirtyTransform}, .{});
};

const Systems = struct {
    pub fn rotateObjectAtSpeed(queried_transform: *Queries.Transforms, params: *const LoopDrivingParam) void {
        while (queried_transform.next()) |item| {
            if (item.entity.id % 2 == 0) {
                // Only updating odd id :)
                continue;
            }
            item.transform.rotation[2] += 0.1 * params.delta_time;
            std.log.info("Updating transform for {}, set Components.DirtyTransform", .{item.entity});
            params.storage.setComponents(item.entity, .{Components.DirtyTransform{}}) catch unreachable;
        }
    }

    pub fn updateMatrixAndClear(collected_dirty_transform: *Queries.DirtyTransforms, params: *const LoopDrivingParam) void {
        while (collected_dirty_transform.next()) |item| {
            const offset = get_instance_offset(item.entity) orelse add_instance_to_indirection_table(params.allocator, item.entity);
            simulated_gpu_transform_buffer[offset] = item.transform.computeMatrix();
            params.storage.unsetComponents(item.entity, .{Components.DirtyTransform});
        }
    }

    pub fn checkIfAnyDirtyLeft(collected_dirty_transform: *Queries.DirtyTransforms, _: *const LoopDrivingParam) void {
        while (collected_dirty_transform.next()) |item| {
            std.log.info("Entity {} is still tagged has dirty", .{item.entity});
        }
    }
};

const LoopDriving = ecez.Event("LoopDriving", .{
    Systems.rotateObjectAtSpeed,
    Systems.updateMatrixAndClear,
    Systems.checkIfAnyDirtyLeft,
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

const LoopDrivingParam = struct {
    delta_time: f32,
    storage: *Storage,
    allocator: std.mem.Allocator,
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

    simulated_gpu_transform_buffer = try allocator.alloc(math.Mat, 1000);
    defer allocator.free(simulated_gpu_transform_buffer);
    defer {
        indirection_table_entity_to_offset.deinit(allocator);
        indirection_table_offset_to_entity.deinit(allocator);
    }

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

    for (0..1000) |_| {
        _ = try storage.createEntity(.{
            Components.Transform{
                .position = .{ 0, 0, 0 },
                .rotation = .{ 0, 0, 0 },
                .scale = .{ 0, 0, 0 },
                .cached_matrix = math.identity(),
            },
        });
    }

    var last_time = glfw.getTime();
    while (!window.shouldClose()) {
        glfw.pollEvents();
        const current_time = glfw.getTime();
        const delta_time = @as(f32, @floatCast(current_time - last_time));
        last_time = current_time;

        const loop_params: LoopDrivingParam = .{
            .delta_time = delta_time,
            .storage = &storage,
            .allocator = allocator,
        };

        device.clearSwapchain(.{
            .colorLoadOp = .clear,
        });

        scheduler.dispatchEvent(&storage, .LoopDriving, &loop_params);
        scheduler.waitEvent(.LoopDriving);

        window.swapBuffers();
    }
}
