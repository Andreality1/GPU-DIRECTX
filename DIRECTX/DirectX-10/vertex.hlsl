// vertex.hlsl
struct VS_OUTPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
};

VS_OUTPUT main(uint vID : SV_VertexID) {
    VS_OUTPUT output;
    
    // Creates a triangle that covers the clip space (-1 to 1)
    // uv becomes (0,0), (2,0), (0,2)
    output.uv = float2((vID << 1) & 2, vID & 2);
    
    // Map UV to Render Targets: (-1, 1), (3, 1), (-1, -3)
    output.pos = float4(output.uv * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
    
    return output;
}