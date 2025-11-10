#version 460 core

#extension GL_GOOGLE_cpp_style_line_directive : require

#include "utils/depth.glsl"
#include "light/light.glsl"

layout(location = 0) in vec3 fWorldPos;
layout(location = 1) in vec3 fNormal;
layout(location = 2) in flat uint fMaterialID;

layout(location = 0) out vec4 rColor;

struct BoundingBox {
	vec4 min;
	vec4 max;
    uvec4 count;
    Light lights[64];
};

layout(std140, binding = 0) uniform Scene {
    mat4 view;
    mat4 proj;
    vec4 view_pos;
};

layout(std430, binding = 9) readonly buffer BBS {
	uint count;
    float distance_per_box;
    vec4 custom_view_dir;
	BoundingBox bbs[];
};

layout(std430, binding = 4) buffer readonly Materials {
    vec4 color[];
};

void main()
{
    vec3 norm = normalize(fNormal);
    vec3 view_dir = normalize(view_pos.xyz - fWorldPos);
    vec3 model_color = color[fMaterialID].xyz;

    float dist = distance(custom_view_dir.xyz, fWorldPos);
    uint index = uint(dist / distance_per_box);

    LightContribution sum;
    sum.ambient = vec3(0);
    sum.diffuse = vec3(0);
    sum.specular = vec3(0);
    for (int i = 0; i < bbs[index].count.x; i += 1) {
        Light light = bbs[index].lights[i];
        switch (light.type_flags) {
            case 0: {
                LightContribution contrib = directional_light_contribution(light, norm, view_dir, model_color);
                sum.ambient += contrib.ambient;
                sum.diffuse += contrib.diffuse;
                sum.specular += contrib.specular;
                break;
            }
            case 1: {
                LightContribution contrib = point_light_contribution(light, fWorldPos, norm, view_dir, model_color);
                sum.ambient += contrib.ambient;
                sum.diffuse += contrib.diffuse;
                sum.specular += contrib.specular;
                break;
            }
            default:
                break;
        }
    }

    sum.ambient /= float(bbs[index].count.x);
    sum.diffuse /= float(bbs[index].count.x);
    sum.specular /= float(bbs[index].count.x);
    vec3 result = sum.diffuse;
    rColor = vec4(result, 1.0);
}