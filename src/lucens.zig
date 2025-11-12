const std = @import("std");
const builtin = @import("builtin");
const ecez = @import("ecez");
const zglfw = @import("zglfw");
const zmath = @import("zmath");
const Inlucere = @import("Inlucere");
const Mesh = @import("./3D/Mesh.zig");
const Example = @import("example.zig");
const ShaderCompiler = @import("shader_compiler.zig");
const Camera = @import("3D/Camera.zig");

const MaterialSystem = @import("graphics/material_system.zig");
const StagingBuffer = @import("graphics/staging_buffer_manager.zig");
const MeshPipeline = @import("graphics/mesh_pipeline.zig");
const MeshManager = @import("graphics/mesh_buffer_manager.zig").MeshManager(u32, Mesh.Vertex);

pub const LucensEngine = @This();

pub const Storage = @import("components.zig").Storage;
pub const ECS = @import("components.zig");
const Scheduler = ecez.CreateScheduler(Storage, .{
    ECS.RenderingUpdateEvent,
});
const Events = @import("events.zig");

// TODO: Move to a better place
const SceneUniform = extern struct {
    view: zmath.Mat,
    proj: zmath.Mat,
    view_pos: [4]f32,
};

pub const LucensGraphicsContext = struct {
    staging_buffer: StagingBuffer,
    mesh_manager: MeshManager,
    material_system: MaterialSystem,
    mesh_pipeline: MeshPipeline,
    tmp_main_geometry_vertex_array: Inlucere.Device.VertexArrayObject,
    tmp_scene_buffer: Inlucere.Device.MappedBuffer,
};

allocator: std.mem.Allocator,
storage: Storage,
scheduler: Scheduler,
window: *zglfw.Window,

graphics_context: LucensGraphicsContext,

pub const Options = struct {
    screen_width: u32 = 1280,
    screen_height: u32 = 720,
};

fn framebuffer_resize_callback(window: *zglfw.Window, w: c_int, h: c_int) callconv(.c) void {
    _ = window;
    _ = w;
    _ = h;
}

pub fn init(self: *LucensEngine, allocator: std.mem.Allocator, options: Options) !void {
    try zglfw.init();

    zglfw.windowHint(.context_version_major, 4);
    zglfw.windowHint(.context_version_minor, 6);
    zglfw.windowHint(.opengl_profile, .opengl_core_profile);
    if (builtin.mode == .Debug) zglfw.windowHint(.opengl_debug_context, true);
    var scheduler: Scheduler = Scheduler.uninitialized;
    try scheduler.init(.{
        .pool_allocator = allocator,
        .query_submit_allocator = allocator,
    });
    self.* = LucensEngine{
        .allocator = allocator,
        .storage = try .init(allocator),
        .scheduler = scheduler,
        .window = try zglfw.createWindow(@intCast(options.screen_width), @intCast(options.screen_height), "Lucens", null),
        .graphics_context = undefined,
    };
    zglfw.makeContextCurrent(self.window);
    try Inlucere.init(zglfw.getProcAddress);

    zglfw.setWindowUserPointer(self.window, self);
    _ = zglfw.setFramebufferSizeCallback(self.window, framebuffer_resize_callback);

    var shader_compiler: ShaderCompiler = .init("./assets/shaders/");
    const program = try shader_compiler.compile_program(allocator, &.{
        "instanced_mesh_standard.vert",
        "no_lights.frag",
    });

    self.graphics_context.staging_buffer = try .init(self.allocator, &.{});
    self.graphics_context.tmp_main_geometry_vertex_array = Example.create_vertex_array();
    try self.graphics_context.mesh_manager.init(self.allocator, 300_000, 400_000, self.graphics_context.tmp_main_geometry_vertex_array.handle);
    try self.graphics_context.material_system.init(allocator);
    self.graphics_context.mesh_pipeline.program = program;
    try self.graphics_context.mesh_pipeline.init(allocator, &self.graphics_context.mesh_manager, &self.graphics_context.material_system);

    const camera = Camera{
        .position = .{ 10, 0, 0 },
        .psi = std.math.pi / 2.0,
        .theta = -std.math.pi / 2.0,
    };
    const scene_uniform_cpu = SceneUniform{
        .view = zmath.lookAtRh(.{ 0, 50, 10, 1 }, .{ 0, 0, 0, 1 }, .{ 0, 1, 0, 0 }),
        .proj = camera.getProjection(1280, 720, 45.0),
        .view_pos = .{ camera.position[0], camera.position[1], camera.position[2], 1.0 },
    };
    self.graphics_context.tmp_scene_buffer = try .init("scene_uniform", SceneUniform, &[1]SceneUniform{scene_uniform_cpu}, .ExplicitFlushed, .{});
    Inlucere.gl.bindBufferBase(Inlucere.gl.UNIFORM_BUFFER, 0, self.graphics_context.tmp_scene_buffer.handle);
}

pub fn deinit(self: *LucensEngine) void {
    self.graphics_context.tmp_main_geometry_vertex_array.deinit();
    self.graphics_context.mesh_manager.deinit(self.allocator);
    self.graphics_context.mesh_pipeline.deinit(self.allocator);
    self.graphics_context.material_system.deinit(self.allocator);
    self.graphics_context.staging_buffer.deinit(self.allocator);

    Inlucere.deinit();
    self.storage.deinit();
    self.scheduler.deinit();
    self.window.destroy();
    zglfw.terminate();
}

pub fn DependecyChainToGraphviz(comptime deps: anytype, opt_names: ?[]const []const u8, writer: std.Io.Writer) !void {
    if (opt_names) |names| {
        std.debug.assert(deps.len == names.len);
        for (deps, names, 0..) |dep, name, id| {
            try writer.print("{} [label = \"{s}\"]\n", .{ id, name });
            for (dep.signal_indices) |signaled_id| {
                try writer.print("{} -> {}\n", .{ id, signaled_id });
            }
        }
    } else {
        for (deps, 0..) |dep, id| {
            try writer.print("{}\n", .{id});
            for (dep.signal_indices) |signaled_id| {
                try writer.print("{} -> {}\n", .{ id, signaled_id });
            }
        }
    }
}

pub fn run(self: *LucensEngine) !void {
    if (@import("builtin").mode == .Debug) {
        inline for (comptime Scheduler.dumpDependencyChain(.render_update), 0..) |dep, system_index| {
            std.debug.print("{d}: {any}\n", .{ system_index, dep });
        }
    }

    var time: f64 = 0.0;
    const fps_target: f64 = 0.016;
    var rendering_time: f64 = fps_target;
    zglfw.setTime(0.0);
    zglfw.swapInterval(0);

    const suzanne_id: u32 = 1;
    {
        var suzanne: Mesh = try .initFromObj(self.allocator, "./assets/meshes/suzanne.obj");

        self.graphics_context.staging_buffer.begin_frame();
        _ = try Example.upload_mesh(
            self.allocator,
            &self.graphics_context.mesh_manager,
            &self.graphics_context.staging_buffer,
            suzanne_id,
            &suzanne,
        );

        self.graphics_context.staging_buffer.end_frame();
        suzanne.deinit(self.allocator);
    }

    _ = try self.storage.createEntity(.{
        ECS.WorldTransform{
            .matrix = zmath.identity(),
        },
        ECS.MeshID{
            .id = suzanne_id,
        },
    });

    while (!self.window.shouldClose()) {
        zglfw.pollEvents();

        const new_time = zglfw.getTime();
        const delta_time = new_time - time;
        time = new_time;

        rendering_time -= delta_time;

        if (rendering_time <= 0.0) {
            try self.scheduler.dispatchEvent(&self.storage, .render_update, ECS.GraphicUpdateSystem.Arguments{
                .allocator = self.allocator,
                .mesh_pipeline = &self.graphics_context.mesh_pipeline,
            });
            try self.scheduler.waitEvent(.render_update);

            self.graphics_context.mesh_pipeline.begin();
            self.graphics_context.material_system.begin();

            _ = try self.graphics_context.material_system.add_material(self.allocator, 0, .{
                .color = .{ 1, 1, 1, 1 },
            });

            self.graphics_context.material_system.end(4);
            self.graphics_context.mesh_pipeline.end();
            self.graphics_context.mesh_pipeline.draw();

            rendering_time = fps_target;
            self.window.swapBuffers();
        }
    }
}
