// pixel1.hlsl
cbuffer ShaderData : register(b0) {
    float u_time;
    float3 padding;
};

float4 main(float4 pos : SV_POSITION, float2 uv : TEXCOORD0) : SV_TARGET {
    float2 p = -1.0 + 2.0 * uv;
    
    // Wave math
    float val = sin(p.x * 10.0 + u_time) + sin((p.y * 10.0 + u_time) / 2.0);
    val += sin((p.x * 10.0 + p.y * 10.0 + u_time) / 2.0);
    
    float2 c = p + float2(0.5 * sin(u_time / 3.0), 0.5 * cos(u_time / 5.0));
    val += sin(sqrt(100.0 * (c.x * c.x + c.y * c.y) + 1.0) + u_time);
    
    float3 color = float3(0.5 + 0.5 * sin(val), 
                          0.5 + 0.5 * sin(val + 2.094), 
                          0.5 + 0.5 * sin(val + 4.188));
                          
    return float4(color, 1.0);
}