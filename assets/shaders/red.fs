#version 460 core

in VS_OUT {
    vec4 FragPos;
    vec2 texCoords;
    vec3 normal;
    flat int instance_id;
} fs_in;

layout(location = 0) out vec4 r_Color;

struct Instance {
    mat4 model_matrix;
    vec4 color;
};

layout(std430, binding = 0) readonly buffer Instances {
    Instance instances[];
};

void main()
{
    Instance instance = instances[fs_in.instance_id];
    r_Color = vec4(instance.color.xyz, 1.0);
}
