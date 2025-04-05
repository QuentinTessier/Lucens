#version 460 core

layout(location = 0) in vec3 v_Position;
layout(location = 1) in vec3 v_Normal;
layout(location = 2) in vec2 v_TexCoords;

layout(location = 0) out vec3 f_WorldFragPos;
layout(location = 1) out vec2 f_TexCoords;
layout(location = 2) out vec3 f_Normal;
layout(location = 3) out flat int f_InstanceID;

struct Light {
    vec4 position;
    vec4 color;
};

layout(binding = 0) uniform Scene {
    mat4 cameraToWorld;
};

struct PerInstance {
    mat4 model;
    mat4 normalMat;
    vec4 color;
};

layout(std430, binding = 1) readonly buffer MeshData {
    PerInstance instances[];
};

void main()
{
    PerInstance instance = instances[gl_InstanceID];

    f_WorldFragPos = vec3(instance.model * vec4(v_Position, 1.0));
    f_TexCoords = v_TexCoords;
    f_Normal = vec3(instance.normalMat * vec4(v_Normal, 0.0));
    f_InstanceID = gl_InstanceID;
    gl_Position = cameraToWorld * instance.model * vec4(v_Position, 1.0);
}