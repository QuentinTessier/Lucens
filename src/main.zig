const std = @import("std");
const builtin = @import("builtin");
const ecez = @import("ecez");
const glfw = @import("zglfw");
const Inlucere = @import("Inlucere");
const gl = Inlucere.gl;
const zmath = @import("zmath");
const zmesh = @import("zmesh");
const Mesh = @import("3D/Mesh.zig");
const LightSystem = @import("light_system.zig");

const Storage = @import("components.zig").Storage;
const MeshManagerGeneric = @import("graphics/mesh_buffer_manager.zig").MeshManager;
const StagingBuffer = @import("graphics/staging_buffer_manager.zig");
const MeshPipeline = @import("graphics/mesh_pipeline.zig");
const MeshManager = MeshManagerGeneric(u32, Mesh.Vertex);
const MaterialSystem = @import("graphics/material_system.zig");
const Camera = @import("3D/Camera.zig");

const Frustum = @import("3D/Frustum.zig");
const BoundingBox = @import("3D/BoundingBox.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

const SceneUniform = extern struct {
    view: zmath.Mat,
    proj: zmath.Mat,
    view_pos: [4]f32,
};

fn upload_mesh(allocator: std.mem.Allocator, mesh_manager: *MeshManager, staging_buffer: *StagingBuffer, handle: u32, mesh: *const Mesh) !?MeshManager.MeshHandle {
    std.log.info("Uploading mesh {}", .{handle});
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

fn load_cat_mesh(allocator: std.mem.Allocator) !Mesh {
    var mesh_indices = std.ArrayListUnmanaged(u32){};
    var mesh_positions = std.ArrayListUnmanaged([3]f32){};
    var mesh_normals = std.ArrayListUnmanaged([3]f32){};
    var mesh_texcoords = std.ArrayListUnmanaged([2]f32){};

    const data = try zmesh.io.zcgltf.parseAndLoadFile("./assets/meshes/cat.glb");
    defer zmesh.io.zcgltf.freeData(data);

    try zmesh.io.zcgltf.appendMeshPrimitive(
        allocator,
        data,
        0, // mesh index
        0, // gltf primitive index (submesh index)
        &mesh_indices,
        &mesh_positions,
        &mesh_normals, // normals (optional)
        &mesh_texcoords, // texcoords (optional)
        null, // tangents (optional)
    );

    std.log.info("Mesh containes {} indices and {} vertices", .{ mesh_indices.items.len, mesh_positions.items.len });

    var mesh = Mesh{
        .indices = try mesh_indices.toOwnedSlice(allocator),
        .positions = try mesh_positions.toOwnedSlice(allocator),
        .normals = try mesh_normals.toOwnedSlice(allocator),
        .texCoords = try mesh_texcoords.toOwnedSlice(allocator),
        .tangents = undefined,
        .bounds = undefined,
    };
    mesh.tangents = try allocator.alloc([3]f32, mesh.positions.len);
    return mesh;
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

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();
    _ = rand;

    try glfw.init();
    defer glfw.terminate();

    zmesh.init(allocator);
    defer zmesh.deinit();

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
        .view = zmath.lookAtRh(.{ 0, 0, 10, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 1, 0, 0 }),
        .proj = camera.getProjection(1280, 720, 45.0),
        .view_pos = .{ camera.position[0], camera.position[1], camera.position[2], 1.0 },
    };

    const view_direction = zmath.normalize4(@Vector(4, f32){ 0, 0, 0, 1 } - @Vector(4, f32){ 0, 0, 10, 1 });
    const frustum: Frustum.FrustumCorner = .init(&.{
        .position = .{ 0, 1, 10, 1 },
        .view_direction = view_direction,
        .far = 100.1,
    });

    const near_bottom_left = frustum.get_point(.near_bottom_left);
    const far_bottom_left = frustum.get_point(.far_bottom_left);

    const near_bottom_left_extended: @Vector(4, f32) = .{
        far_bottom_left[0],
        far_bottom_left[1],
        near_bottom_left[2],
        1.0,
    };

    const frustum_bounding_box: BoundingBox = .{
        .max = frustum.get_point(.far_top_right),
        .min = near_bottom_left_extended,
    };

    const n_slice: usize = 7;
    var bbs: [n_slice]BoundingBox = undefined;

    const z_length = @abs(frustum_bounding_box.max[2] - frustum_bounding_box.min[2]);
    const z_length_slice: f32 = z_length / @as(f32, @floatFromInt(n_slice));
    const z_dir = view_direction[2];
    bbs[0] = .{
        .min = frustum_bounding_box.min,
        .max = .{
            frustum_bounding_box.max[0],
            frustum_bounding_box.max[1],
            frustum_bounding_box.min[2] + z_length_slice * z_dir,
            1.0,
        },
    };
    for (1..n_slice) |i| {
        const previous_bb = bbs[i - 1];
        bbs[i] = .{ .min = .{
            previous_bb.min[0],
            previous_bb.min[1],
            previous_bb.max[2],
            1.0,
        }, .max = .{
            previous_bb.max[0],
            previous_bb.max[1],
            previous_bb.max[2] + z_length_slice * z_dir,
            1.0,
        } };
    }
    const GPUFrustumBoundingBoxes = extern struct {
        count: [4]u32,
        bbs: [n_slice][3][4]f32,
    };

    const colors: [7][4]f32 = .{
        .{ 1, 1, 1, 1 },
        .{ 1, 0, 0, 1 },
        .{ 0, 1, 0, 1 },
        .{ 0, 0, 1, 1 },
        .{ 0, 1, 1, 1 },
        .{ 1, 1, 0, 1 },
        .{ 1, 0, 1, 1 },
    };

    const gpu_frustum_bounding_boxes: GPUFrustumBoundingBoxes = .{
        .count = .{ @intCast(n_slice), 0, 0, 0 },
        .bbs = blk: {
            var buffer: [n_slice][3][4]f32 = undefined;
            inline for (0..n_slice) |i| {
                buffer[i][0] = bbs[i].min;
                buffer[i][1] = bbs[i].max;
                buffer[i][2] = colors[i];
            }
            break :blk buffer;
        },
    };
    var buffer_tmp: Inlucere.Device.MappedBuffer = try .init("scene", GPUFrustumBoundingBoxes, &[1]GPUFrustumBoundingBoxes{gpu_frustum_bounding_boxes}, .ExplicitFlushed, .{});
    defer buffer_tmp.deinit();
    Inlucere.gl.objectLabel(
        Inlucere.gl.BUFFER,
        buffer_tmp.handle,
        10,
        "buffer_tmp",
    );

    gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, 9, buffer_tmp.handle);

    inline for (std.meta.fields(Frustum.FrustumCorner.PointName)) |field| {
        const value: Frustum.FrustumCorner.PointName = @enumFromInt(field.value);
        std.debug.print("{any}\n", .{frustum.get_point(value)});
    }

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
    try mesh_manager.init(allocator, 300_000, 400_000, vao.handle);
    defer mesh_manager.deinit(allocator);

    const suzanne_id: u32 = 1;
    var suzanne: Mesh = try .initFromObj(allocator, "./assets/meshes/suzanne.obj");
    defer suzanne.deinit(allocator);

    // const sphere_id: u32 = 2;
    // var sphere: Mesh = try .initFromObj(allocator, "./assets/meshes/sphere.obj");
    // defer sphere.deinit(allocator);

    const cat_id: u32 = 3;
    var cat: Mesh = try load_cat_mesh(allocator);
    defer cat.deinit(allocator);

    staging_buffer.begin_frame();
    _ = try upload_mesh(allocator, &mesh_manager, &staging_buffer, suzanne_id, &suzanne);
    //_ = try upload_mesh(allocator, &mesh_manager, &staging_buffer, sphere_id, &sphere);
    _ = try upload_mesh(allocator, &mesh_manager, &staging_buffer, cat_id, &cat);
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

    // const speed: f32 = 0.001;
    //var position: @Vector(4, f32) = .{ 0, 0, 0, 1 };
    while (!window.shouldClose()) {
        glfw.pollEvents();

        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        //position[2] += z_dir * speed;

        material_system.begin();
        mesh_pipeline.begin();

        _ = try material_system.add_material(allocator, 0, .{
            .color = .{ 1, 1, 1, 1 },
        });
        _ = try material_system.add_material(allocator, 1, .{
            .color = .{ 0, 1, 1, 1 },
        });

        try mesh_pipeline.draw_instance(
            allocator,
            cat_id,
            zmath.scaling(0.5, 0.5, 0.5),
            1,
        );

        // try mesh_pipeline.draw_instance(allocator, sphere_id, zmath.translation(-1.5, 0, 0), 1);
        // try mesh_pipeline.draw_instance(allocator, sphere_id, zmath.translation(1.5, 0, 0), 1);

        mesh_pipeline.end();
        material_system.end(4);
        mesh_pipeline.draw();

        window.swapBuffers();
    }
}
