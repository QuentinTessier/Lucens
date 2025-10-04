#version 460 core

out gl_PerVertex
{
    vec4 gl_Position;
};

layout(location = 0) in vec4 vPosition;
layout(location = 1) in vec4 vNormal;
layout(location = 2) in vec4 vTangent;
layout(location = 3) in vec2 vTexCoords;

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
    fWorldPos = mat3(instance.model_to_world) * vPosition.xyz;
    fNormal = mat3(transpose(inverse(instance.model_to_world))) * vNormal.xyz;
    gl_Position = proj * view * vec4(fWorldPos, 1.0);
}