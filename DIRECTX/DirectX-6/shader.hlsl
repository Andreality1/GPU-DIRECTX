// shader.hlsl

// 1. Data coming from the C++ Vertex Buffer
struct VS_INPUT {
    float3 pos : POSITION;
};

// 2. Data being passed from Vertex Shader to Pixel Shader
struct PS_INPUT {
    float4 pos : SV_POSITION; // Target pixel position
    float2 uv  : TEXCOORD;    // Normalized coordinates (0 to 1)
};

// ------------------------------------------------------------------
// VERTEX SHADER
// ------------------------------------------------------------------
PS_INPUT VS(VS_INPUT input) {
    PS_INPUT output;

    // Direct projection: taking our -1 to 1 vertices and 
    // putting them directly on the screen plane.
    output.pos = float4(input.pos, 1.0f);

    // Convert vertex positions (-1 to 1) to texture coordinates (0 to 1)
    // This allows us to treat the screen like a 2D graph.
    output.uv = input.pos.xy * 0.5f + 0.5f;
    
    // In DirectX, the Y axis is inverted compared to OpenGL, 
    // so we flip it to make (0,0) the bottom-left.
    output.uv.y = 1.0f - output.uv.y;

    return output;
}

// ------------------------------------------------------------------
// PIXEL SHADER
// ------------------------------------------------------------------
float4 PS(PS_INPUT input) : SV_Target {
    // Generate a simple test pattern:
    // Red increases from left to right.
    // Green increases from bottom to top.
    float3 color = float3(input.uv.x, input.uv.y, 0.2f);
    
    // Output the final color with 1.0 alpha (opaque)
    return float4(color, 1.0f);
}