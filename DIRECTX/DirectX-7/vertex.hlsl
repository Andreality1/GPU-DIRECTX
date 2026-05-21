// vertex.hlsl

struct VS_INPUT {
    float3 pos : POSITION;
};

struct PS_INPUT {
    float4 pos : SV_POSITION; // Screen position for the GPU
    float2 uv  : TEXCOORD;    // Coordinates for the Pixel Shader
};

PS_INPUT main(VS_INPUT input) {
    PS_INPUT output;
    
    // Direct position (no camera transformation needed for the quad)
    output.pos = float4(input.pos, 1.0f);
    
    // Pass the raw XY coordinates as UVs (-1 to 1 range)
    output.uv = input.pos.xy; 
    
    return output;
}