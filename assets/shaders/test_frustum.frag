#version 460 core

//#extension GL_GOOGLE_include_directive : require

#include "utils/depth.glsl"

layout(location = 0) in vec3 fWorldPos;
layout(location = 1) in vec3 fNormal;
layout(location = 2) in flat uint fMaterialID;

layout(location = 0) out vec4 rColor;

struct BoundingBox {
	vec4 min;
	vec4 max;
    vec4 color;
};

layout(std140, binding = 0) uniform Scene {
    mat4 view;
    mat4 proj;
    vec4 view_pos;
};

layout(std430, binding = 9) readonly buffer BBS {
	uint count;
	BoundingBox bbs[];
};

void main()
{
    float dist = distance(view_pos.xyz, fWorldPos);
    uint index = uint(dist / 14.285714285714285714285714285714);

    rColor = bbs[index].color;
}