#version 460 core

out gl_PerVertex
{
    vec4 gl_Position;
};

layout(location = 0) in vec3 v_Position;
layout(location = 1) in vec3 v_Normal;
layout(location = 2) in vec3 v_Tangent;
layout(location = 3) in vec2 v_TexCoords;

out VS_OUT {
    vec4 FragPos;
    vec2 texCoords;
    vec3 normal;
    flat int instance_id;
} vs_out;

layout(std140, binding = 0) uniform Scene {
    mat4 view_projection_matrix;
};

struct Instance {
    mat4 model_matrix;
    vec4 color;
};

layout(std430, binding = 0) readonly buffer Instances {
    Instance instances[];
};

void main()
{
    Instance instance = instances[gl_InstanceID];
    vs_out.normal = v_Normal;
    vs_out.texCoords = v_TexCoords;
    vs_out.FragPos = instance.model_matrix * vec4(v_Position, 1.0);
    vs_out.instance_id = gl_InstanceID;
    gl_Position = view_projection_matrix * vs_out.FragPos;
}