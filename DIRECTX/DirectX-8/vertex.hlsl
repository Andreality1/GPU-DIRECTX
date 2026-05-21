struct VS_OUTPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD;
};

VS_OUTPUT main(uint id : SV_VertexID) {
    VS_OUTPUT output;
    
    // This math generates three points:
    // id 0: uv(0, 0) pos(-1,  1)
    // id 1: uv(2, 0) pos( 3,  1)
    // id 2: uv(0, 2) pos(-1, -3)
    output.uv = float2((id << 1) & 2, id & 2);
    output.pos = float4(output.uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    
    return output;
}