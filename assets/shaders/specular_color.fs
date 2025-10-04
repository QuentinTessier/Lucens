#version 460 core

layout(location = 0) in vec4 fColor;
layout(location = 1) in vec3 fNormal;
layout(location = 2) in vec3 fWorldPos;

layout(location = 0) out vec4 rColor;

layout(std140, binding = 1) uniform Scene {
    mat4 view;
    mat4 proj;
    vec4 view_pos;
};

void main()
{
    vec3 lightPos = vec3(5.0, 0.0, 0.0);
    vec3 viewPos = view_pos.xyz; 
    vec3 lightColor = vec3(1.0, 1.0, 1.0);
    vec3 objectColor = fColor.xyz;

    // ambient
    float ambientStrength = 0.1;
    vec3 ambient = ambientStrength * lightColor;
  	
    // diffuse 
    vec3 norm = normalize(fNormal);
    vec3 lightDir = normalize(lightPos - fWorldPos);
    float diff = max(dot(norm, lightDir), 0.0);
    vec3 diffuse = diff * lightColor;
    
    // specular
    float specularStrength = 0.5;
    vec3 viewDir = normalize(viewPos - fWorldPos);
    vec3 reflectDir = reflect(-lightDir, norm);  
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32);
    vec3 specular = specularStrength * spec * lightColor;
        
    vec3 result = (ambient + diffuse + specular) * objectColor;
    rColor = vec4(result, 1.0);
}