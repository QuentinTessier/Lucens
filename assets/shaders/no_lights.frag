#version 460 core

#extension GL_GOOGLE_cpp_style_line_directive : require

layout(location = 0) in vec3 fWorldPos;
layout(location = 1) in vec3 fNormal;
layout(location = 2) in flat uint fMaterialID;

layout(location = 0) out vec4 rColor;

layout(std140, binding = 0) uniform Scene {
    mat4 view;
    mat4 proj;
    vec4 view_pos;
};

layout(std430, binding = 4) buffer readonly Materials {
    vec4 color[];
};

void main()
{
    rColor = color[fMaterialID];
}