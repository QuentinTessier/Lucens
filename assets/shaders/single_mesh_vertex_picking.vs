#version 460 core

out gl_PerVertex
{
    vec4 gl_Position;
};

struct Vertex {
    float position[3];
    float normal[3];
    float tangent[3];
    float tex_coords[2];
};

layout(std430, binding = 0) buffer readonly vertex_buffer {
    Vertex vertices[];
};

vec3 get_position(uint index) {
    return vec3(
        vertices[index].position[0],
        vertices[index].position[1],
        vertices[index].position[2]
    );
};

vec3 get_normal(uint index)
{
    return vec3(
        vertices[index].normal[0],
        vertices[index].normal[1],
        vertices[index].normal[2]
    );
}

vec3 get_tangent(uint index)
{
    return vec3(
        vertices[index].tangent[0],
        vertices[index].tangent[1],
        vertices[index].tangent[2]
    );
}

vec2 get_tex_coords(uint index)
{
    return vec2(vertices[index].tex_coords[0], vertices[index].tex_coords[1]);
}

layout(std140, binding = 1) uniform Scene {
    mat4 view;
    mat4 proj;
    vec4 view_pos;
};

struct PerInstance {
    mat4 model_to_world;
    vec4 color;
};

layout(std430, binding = 2) readonly buffer MeshData {
    PerInstance instances[];
};

layout(location = 0) out vec4 fColor;
layout(location = 1) out vec3 fNormal;
layout(location = 2) out vec3 fWorldPos;

void main()
{
    PerInstance instance = instances[0];

    fColor = instance.color;
    fWorldPos = (instance.model_to_world * vec4(get_position(gl_VertexID), 1.0)).xyz;
    fNormal = (instance.model_to_world * vec4(get_normal(gl_VertexID), 1.0)).xyz;
    gl_Position = proj * view * vec4(fWorldPos, 1.0);
}