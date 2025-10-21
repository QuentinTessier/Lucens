#version 460 core

#include <light/light.glsl>

layout(location = 0) in vec3 fWorldPos;
layout(location = 1) in vec3 fNormal;
layout(location = 2) in flat uint fMaterialID;

layout(location = 0) out vec4 rColor;

layout(std140, binding = 0) uniform Scene {
    mat4 view;
    mat4 proj;
    vec4 view_pos;
};

layout(std430, binding = 3) buffer readonly Lights {
    uint light_count;
    Light lights[];
};

layout(std430, binding = 4) buffer readonly Materials {
    vec4 color[];
};

void main()
{
    vec3 norm = normalize(fNormal);
    vec3 view_dir = normalize(view_pos.xyz - fWorldPos);

    vec3 ambient_sum = vec3(0, 0, 0);
    vec3 diffuse_sum = vec3(0, 0, 0);
    vec3 specular_sum = vec3(0, 0, 0);

    float ambient_strength = 0.1;
    float specular_strength = 0.5;
    float shininess = 64.0;

    vec3 model_color = color[fMaterialID].xyz;

    LightContribution sum;
    sum.ambient = vec3(0);
    sum.diffuse = vec3(0);
    sum.specular = vec3(0);
    for (int i = 0; i < light_count.x; i += 1) {
        Light light = lights[i];
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
            case 2: {
                LightContribution contrib = spot_light_contribution(light, fWorldPos, norm, view_dir, model_color);
                sum.ambient += contrib.ambient;
                sum.diffuse += contrib.diffuse;
                sum.specular += contrib.specular;
                break;
            }
            default:
                break;
        }
    }

    sum.ambient /= float(light_count);
    sum.diffuse /= float(light_count);
    sum.specular /= float(light_count);
    vec3 result = sum.diffuse + sum.specular;
    rColor = vec4(result, 1.0);
}