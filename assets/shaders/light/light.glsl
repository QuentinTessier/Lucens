#include <light/blinn_phong.glsl>

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
