float BlinnPhonSpecular(vec3 light_dir, vec3 view_dir, vec3 normal, float shininess)
{
    vec3 halfway_dir = normalize(light_dir + view_dir);
    return pow(max(dot(normal, halfway_dir), 0.0), shininess);
}