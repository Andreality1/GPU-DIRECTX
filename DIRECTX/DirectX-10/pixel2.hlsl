// pixel2.hlsl
cbuffer ShaderData : register(b0) {
    float u_time;
    float3 padding;
};

float4 main(float4 pos : SV_POSITION, float2 uv : TEXCOORD0) : SV_TARGET {
    // Zoom in slightly for the grid
    float2 gridUV = uv * 20.0;
    
    // Create grid lines
    float2 lineWeight = fwidth(gridUV);
    float2 grid = abs(frac(gridUV - 0.5) - 0.5) / lineWeight;
    float gridLine = 1.0 - min(grid.x, grid.y);
    
    // Moving pulse
    float pulse = sin(uv.y * 10.0 - u_time * 5.0) * 0.5 + 0.5;
    
    float3 baseColor = float3(0.0, 0.2, 0.5); // Deep blue
    float3 finalColor = lerp(baseColor, float3(0.0, 1.0, 0.8), gridLine * pulse);
    
    return float4(finalColor, 1.0);
}