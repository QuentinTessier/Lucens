float linear_depth(float near, float far)
{
    float depth01 = 1.0 - gl_FragCoord.w;
    return near * (1.0 - depth01) + (far * depth01);
}
