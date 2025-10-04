#version 460 core

struct MeshInstance {
    mat4 model_to_world;
    mat4 world_to_model;
    uint material_id;
};

struct MeshInstanceRange {
    uint index;
    uint count;
};

out gl_PerVertex
{
    vec4 gl_Position;
};

layout(location = 0) in vec4 vPosition;
layout(location = 1) in vec4 vNormal;
layout(location = 2) in vec4 vTangent;
layout(location = 3) in vec2 vTexCoords;

layout(location = 0) out vec3 fWorldPos;
layout(location = 1) out vec3 fNormal;
layout(location = 2) out flat uint fMaterialID;
layout(location = 3) out mat4 fModelToWorld;


layout(std140, binding = 0) uniform Scene {
    mat4 view;
    mat4 proj;
    vec4 view_pos;
};

layout(std430, binding = 1) readonly buffer PerInstance {
    MeshInstance mesh_instances[];
};

layout(std430, binding = 2) readonly buffer InstanceRange {
    MeshInstanceRange ranges[];
};

void main()
{
    MeshInstanceRange range = ranges[gl_DrawID];
    MeshInstance instance = mesh_instances[range.index + gl_InstanceID];

    fModelToWorld = instance.model_to_world;
    fMaterialID = range.index;
    vec4 WorldPos = mat4(instance.model_to_world) * vec4(vPosition.xyz, 1.0);
    vec4 Normal = mat4(instance.world_to_model) * vec4(vNormal.xyz, 1.0);
    fWorldPos = WorldPos.xyz;
    fNormal = Normal.xyz;
    gl_Position = proj * view * vec4(fWorldPos, 1.0);
}