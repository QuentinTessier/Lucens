#version 460 core

layout(location = 0) in vec3 fWorldPos;
layout(location = 1) in vec3 fNormal;
layout(location = 2) in flat uint fMaterialID;

layout(location = 0) out vec4 rColor;

layout(std140, binding = 0) uniform Scene {
    mat4 view;
    mat4 proj;
    vec4 view_pos;
};

struct Light {
    vec3 color;         // 12 bytes (aligned to 16)
    uint type_flags;    // 4 bytes  -> offset 12
    vec3 direction;     // 12 bytes (aligned to 16)
    float range;        // 4 bytes  -> offset 28
    vec3 position;      // 12 bytes (aligned to 16)
    float intensity;    // 4 bytes  -> offset 44
    float angleScale;   // 4 bytes  -> offset 48
    float angleOffset;  // 4 bytes  -> offset 52
};


layout(std430, binding = 3) buffer readonly Lights {
    uint light_count;
    Light lights[];
};

layout(std430, binding = 4) buffer readonly Materials {
    vec4 color[];
};

float BlinnPhonSpecular(vec3 light_dir, vec3 view_dir, vec3 normal, float shininess)
{
    vec3 halfway_dir = normalize(light_dir + view_dir);
    return pow(max(dot(normal, halfway_dir), 0.0), shininess);
}

struct LightContribution {
    vec3 ambient;
    vec3 diffuse;
    vec3 specular;
};

LightContribution directional_light_contribution(in Light light, vec3 normal, vec3 view_dir, vec3 object_color)
{
    float ambient_strength = 0.1;
    vec3 ambient = light.color * object_color;

    float specular_strength = 0.5;

    vec3 light_dir = normalize(-light.direction);
    float diff = max(dot(normal, light_dir), 0.0);
    vec3 diffuse = light.color * diff * object_color;

    vec3 reflect_dir = reflect(-light.direction, normal);
    float spec = pow(max(dot(view_dir, reflect_dir), 0.0), 16.0);
    vec3 specular = specular_strength * spec * light.color;

    LightContribution contrib;
    contrib.ambient = ambient;
    contrib.diffuse = diffuse;
    contrib.specular = specular;
    return contrib;
}

float Attenuation(float dist, float range)
{
    float att = 1.0 - (dist / range);
    return max(att, 0.0) * max(att, 0.0);
}

LightContribution point_light_contribution(in Light light, vec3 frag_pos, vec3 normal, vec3 view_dir, vec3 object_color)
{
    float ambient_strength = 0.1;
    vec3 ambient = light.color * object_color;

    vec3 light_dir = normalize(light.position - frag_pos);
    float diff = max(dot(normal, light_dir), 0.0);
    vec3 diffuse = light.color * diff * object_color;

    float specular_strength = 0.5;
    //vec3 reflect_dir = reflect(-light.direction, normal);
    float spec = pow(max(dot(view_dir, -light.direction), 0.0), 16.0);
    vec3 specular = specular_strength * spec * light.color;

    float distance = length(light.position - frag_pos);
    float attenuation = Attenuation(distance, light.range);

    ambient *= attenuation;
    diffuse *= attenuation;
    specular *= attenuation;

    LightContribution contrib;
    contrib.ambient = ambient;
    contrib.diffuse = diffuse;
    contrib.specular = specular;
    return contrib;
}

LightContribution spot_light_contribution(in Light light, vec3 frag_pos, vec3 normal, vec3 view_dir, vec3 object_color)
{
    LightContribution contrib;
    contrib.ambient = vec3(0, 0, 0);
    contrib.diffuse = vec3(0, 0, 0);
    contrib.specular = vec3(0, 0, 0);

    vec3 light_dir = normalize(light.position - frag_pos);
    float theta = dot(light_dir, normalize(-light.direction));

    if (theta > light.intensity)
    {
        float ambient_strength = 0.01;
        contrib.ambient = light.color * object_color;

        float diff = max(dot(normal, light_dir), 0.0);
        contrib.diffuse = light.color * diff * object_color;

        float specular_strength = 0.5;
        vec3 reflect_dir = reflect(-light.direction, normal);
        float spec = pow(max(dot(view_dir, reflect_dir), 0.0), 16.0);
        contrib.specular = specular_strength * spec * light.color;

        float distance = length(light.position - frag_pos);
        //float attenuation = Attenuation(distance, light.intensity);

        // contrib.ambient *= attenuation;
        // contrib.diffuse *= attenuation;
        // contrib.specular *= attenuation;
    }

    return contrib;
}

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