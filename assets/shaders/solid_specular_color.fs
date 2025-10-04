#version 460 core

layout(location = 0) in vec3 fWorldPos;
layout(location = 1) in vec3 fNormal;
layout(location = 2) in flat uint fMaterialID;
layout(location = 3) in mat4 fModelToWorld;

layout(location = 0) out vec4 rColor;

layout(std140, binding = 0) uniform Scene {
    mat4 view;
    mat4 proj;
    vec4 view_pos;
};

struct Light {
    vec4 position;
    vec4 color;
};

layout(std430, binding = 3) buffer readonly Lights {
    ivec4 light_count;
    Light lights[];
};

void main()
{
    mat4 t = fModelToWorld;
    vec3 norm = normalize(fNormal);
    vec3 view_dir = normalize(view_pos.xyz - fWorldPos);

    vec3 ambient_sum = vec3(0, 0, 0);
    vec3 diffuse_sum = vec3(0, 0, 0);
    vec3 specular_sum = vec3(0, 0, 0);

    float ambient_strength = 0.1;
    float specular_strength = 0.5;
    float shininess = 32.0;

    for (int i = 0; i < light_count.x; i += 1) {
        vec3 light_pos = lights[i].position.xyz;
        vec3 light_col = lights[i].color.xyz;

        ambient_sum += ambient_strength * light_col;

        vec3 light_dir = normalize(light_pos - fWorldPos);
        float diff = max(dot(norm, light_dir), 0.0);
        diffuse_sum += diff * light_col;

        vec3 reflect_dir = reflect(-light_dir, norm);
        float spec = pow(max(dot(view_dir.xyz, reflect_dir), 0.0), shininess);
        specular_sum += specular_strength * spec * light_col;
    }

    vec3 result = (ambient_sum + diffuse_sum + specular_sum);
    rColor = vec4(result, 1.0);
}