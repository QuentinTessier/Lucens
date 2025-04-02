const std = @import("std");
const Lucens = @import("../../lucens.zig");
const Inlucere = @import("Inlucere");
const InlucereModule = @import("../InlucereModule.zig");
const zmath = @import("zmath");
const zstbi = @import("zstbi");

pub const Renderer2DModule = @This();

pub const PerInstance = extern struct {
    position: [2]f32,
    scale: [2]f32,
    uv_offset_scale: [4]f32,
    color: [4]f32,
    rotation: f32,
};

pub const Scene = extern struct {
    view_projection: zmath.Mat,
};

pub const UnitQuadVertices = [_][4]f32{
    .{ -0.5, -0.5, 0.0, 0.0 },
    .{ 0.5, -0.5, 1.0, 0.0 },
    .{ 0.5, 0.5, 1.0, 1.0 },
    .{ -0.5, 0.5, 0.0, 1.0 },
};

pub const UnitQuadIndices = [_]u16{
    0, 1, 2,
    2, 3, 0,
};

pub const Renderer2D_MaxInstance: usize = 20_000;

base: Lucens.LucensModule,
inlucere: *InlucereModule,
vertices: Inlucere.Device.StaticBuffer,
indices: Inlucere.Device.StaticBuffer,

per_instance: Inlucere.Device.DynamicBuffer,
scene: Inlucere.Device.DynamicBuffer,

spritesheet: Inlucere.Device.Texture2D,

pub const init_base: Lucens.LucensModule = .{
    .name = @typeName(@This()),
    .user_init = &Renderer2DModule.init,
    .user_deinit = &Renderer2DModule.deinit,
};

pub fn init(base: *Lucens.LucensModule, allocator: std.mem.Allocator) anyerror!void {
    const self = base.as(Renderer2DModule);

    zstbi.init(allocator);
    zstbi.setFlipVerticallyOnLoad(true);

    self.inlucere = Lucens.LucensEngine().getModule(InlucereModule, @typeName(InlucereModule)).?;

    _ = self.inlucere.device.loadShader("Renderer2D_Program", &.{
        .{ .stage = .Vertex, .source = Renderer2D_VertexShaderSources },
        .{ .stage = .Fragment, .source = Renderer2D_FragmentShaderSources },
    }) catch |e| {
        std.log.err("Got an error {}", .{e});
        while (true) {}
    };

    // TODO: Blending
    var rasterization = Inlucere.Device.GraphicPipeline.PipelineRasterizationState.default();
    rasterization.cullMode = .front;
    _ = try self.inlucere.device.createGraphicPipeline("Renderer2D_Pipeline", &.{
        .programs = &.{"Renderer2D_Program"},
        .vertexInputState = .{
            .vertexAttributeDescription = &.{
                .{ .location = 0, .binding = 0, .inputType = .vec2 },
                .{ .location = 1, .binding = 0, .inputType = .vec2 },
            },
        },
        .rasterizationState = rasterization,
    });

    self.vertices = Inlucere.Device.StaticBuffer.init("Renderer2D_vertices", std.mem.sliceAsBytes(&UnitQuadVertices), @sizeOf(f32) * 4);
    self.indices = Inlucere.Device.StaticBuffer.init("Renderer2D_indices", std.mem.sliceAsBytes(&UnitQuadIndices), @sizeOf(u16));
    self.per_instance = try Inlucere.Device.DynamicBuffer.initEmpty("Renderer2D_per_instance", Renderer2D_MaxInstance * @sizeOf(PerInstance), @sizeOf(PerInstance));

    const scene = Scene{
        .view_projection = zmath.orthographicOffCenterRhGl(
            -1280.0 * 0.5,
            1280 * 0.5,
            -720.0 * 0.5,
            720.0 * 0.5,
            -1.0,
            1.0,
        ),
    };
    self.scene = try Inlucere.Device.DynamicBuffer.init("Renderer2D_Scene", std.mem.asBytes(&scene), @sizeOf(Scene));

    var image = try zstbi.Image.loadFromFile("./sheet.png", 3);
    defer image.deinit();

    self.spritesheet.init(&.{
        .name = null,
        .levelCount = 1,
        .extent = .{ .width = @intCast(image.width), .height = @intCast(image.height) },
        .format = .rgb8,
        .data = .{
            .channels = .rgb,
            .type = .u8,
            .offset = .{ .width = 0, .height = 0 },
            .level = 0,
            .extent = .{
                .width = @intCast(image.width),
                .height = @intCast(image.height),
            },
            .data = image.data,
        },
    });
}

pub fn deinit(base: *Lucens.LucensModule) void {
    const self = base.as(Renderer2DModule);

    self.indices.deinit();
    self.vertices.deinit();
    self.per_instance.deinit();

    zstbi.deinit();
}

pub fn draw(self: *Renderer2DModule, instances: []const PerInstance) void {
    std.debug.assert(instances.len < Renderer2D_MaxInstance); // TODO: Flush the rendering pipeline when we have to many elements
    self.per_instance.update(std.mem.sliceAsBytes(instances), 0);
    if (self.inlucere.device.bindGraphicPipeline("Renderer2D_Pipeline")) {
        self.inlucere.device.bindElementBuffer(self.indices.toBuffer(), .u16);
        self.inlucere.device.bindVertexBuffer(0, self.vertices.toBuffer(), 0, null);
        self.inlucere.device.bindStorageBuffer(1, self.per_instance.toBuffer(), .{
            ._whole = void{},
        });
        self.inlucere.device.bindUniformBuffer(0, self.scene.toBuffer(), .{
            ._whole = void{},
        });
        self.inlucere.device.bindTexture(3, self.spritesheet.toTexture());
        self.inlucere.device.drawElements(6, @intCast(instances.len), 0, 0, 0);
    }
}

pub fn tmp_draw(self: *Renderer2DModule) void {
    const sprite_buffer = comptime blk: {
        var buffer: []const PerInstance = &[0]PerInstance{};
        for (0..17) |x| {
            for (0..8) |y| {
                const fX = @as(f32, 16.0) * @as(f32, @floatFromInt(x));
                const fY = @as(f32, 16.0) * @as(f32, @floatFromInt(y));

                buffer = buffer ++ [_]PerInstance{.{
                    .position = .{ fX, fY },
                    .scale = .{ 16, 16 },
                    .rotation = 0,
                    .uv_offset_scale = .{
                        272.0 / fX, 128.0 / fY, 272.0 / 16, 128.0 / 16,
                    },
                    .color = .{ 1, 1, 1, 1 },
                }};
            }
        }
        break :blk buffer;
    };

    self.draw(sprite_buffer);
}

pub const Renderer2D_VertexShaderSources =
    \\#version 460 core
    \\
    \\out gl_PerVertex
    \\{
    \\    vec4 gl_Position;
    \\};
    \\
    \\layout(location = 0) in vec2 v_Position;
    \\layout(location = 1) in vec2 v_UV;
    \\
    \\layout(location = 0) out vec2 f_Position;
    \\layout(location = 1) out vec2 f_UV;
    \\layout(location = 2) out vec4 f_Color;
    \\
    \\struct PerSpriteInstance {
    \\    vec2 position;
    \\    vec2 scale;
    \\    vec4 uv_offset_scale;
    \\    vec4 color;
    \\    float rotation;
    \\};
    \\
    \\layout(std140, binding = 0) uniform SceneData {
    \\    mat4 view_projection;
    \\};
    \\
    \\layout(std430, binding = 1) buffer PerSpriteInstanceBuffer {
    \\    PerSpriteInstance per_instance[];
    \\};
    \\
    \\mat3 build_transform(vec2 p, vec2 s, float r)
    \\{
    \\    float co = cos(r);
    \\    float si = sin(r);
    \\
    \\    return mat3(
    \\        s.x * co,   -s.y * si,  p.x,
    \\        s.x * si,   s.y * co,   p.y,
    \\        0.0,        0.0,        1.0
    \\    );
    \\}
    \\
    \\void main()
    \\{
    \\    PerSpriteInstance self = per_instance[gl_InstanceID];
    \\
    \\    mat3 model = build_transform(self.position, self.scale, self.rotation);
    \\    vec2 world_pos = (model * vec3(v_Position, 1.0)).xy;
    \\
    \\    f_Position = world_pos;
    \\    f_UV = self.uv_offset_scale.xy + v_UV * self.uv_offset_scale.zw;
    \\    f_Color = self.color;
    \\
    \\    gl_Position = view_projection * vec4(world_pos, 0.0, 1.0);
    \\}
;

pub const Renderer2D_FragmentShaderSources =
    \\#version 460 core
    \\
    \\layout(location = 0) in vec2 f_Position;
    \\layout(location = 1) in vec2 f_UV;
    \\layout(location = 2) in vec4 f_Color;
    \\
    \\layout(location = 0) out vec4 r_Color;
    \\
    \\layout(binding = 3) uniform sampler2D s_Spritesheet;
    \\
    \\void main()
    \\{
    \\    vec4 t = texture(s_Spritesheet, f_UV);
    \\    r_Color = t * f_Color;
    \\}
;
