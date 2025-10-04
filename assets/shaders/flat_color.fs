#version 460 core

layout(location = 0) in vec4 fColor;
layout(location = 1) in vec3 fNormal;
layout(location = 2) in vec3 fWorldPos;

layout(location = 0) out vec4 rColor;

void main()
{
    rColor = fColor;
}