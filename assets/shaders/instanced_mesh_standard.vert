#version 460 core

#extension GL_GOOGLE_include_directive : enable

#include "utils/mesh_pipeline.glsl"

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

layout(std140, binding = 0) uniform Scene {
    mat4 view;
    mat4 proj;
    vec4 view_pos;
};

layout(std430, binding = 1) readonly buffer PerInstance {
    MeshInstance mesh_instances[];
};

layout(std430, binding = 2) readonly buffer DrawOffset {
    uint offsets[];
};

void main()
{
    uint offset = offsets[gl_DrawID];
    MeshInstance instance = mesh_instances[offset + gl_InstanceID];

    vec4 WorldPos = mat4(instance.model_to_world) * vec4(vPosition.xyz, 1.0);
    vec4 Normal = mat4(instance.world_to_model) * vec4(vNormal.xyz, 1.0);
    fWorldPos = WorldPos.xyz;
    fNormal = Normal.xyz;
    fMaterialID = instance.material_id;
    gl_Position = proj * view * vec4(fWorldPos, 1.0);
}