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
} vs_out;

// We currently only expect 1 mesh
layout(std140, binding = 0) uniform Scene {
    mat4 view_projection_matrix;
    mat4 model_matrix;
};

void main()
{
    vs_out.normal = v_Normal;
    vs_out.texCoords = v_TexCoords;
    vs_out.FragPos = model_matrix * vec4(v_Position, 1.0);
    gl_Position = view_projection_matrix * vs_out.FragPos;
}