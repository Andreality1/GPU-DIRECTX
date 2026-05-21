// shader.hlsl

// Structure for data passed from Vertex Shader to Pixel Shader
struct VS_OUTPUT {
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD;
};

// Constant Buffer: data passed from C++ to GPU every frame
// Must be 16-byte aligned to match the C++ struct
cbuffer Constants : register(b0) {
    float u_time;           // 4 bytes
    float2 u_resolution;    // 8 bytes
    float padding;          // 4 bytes (for alignment)
};

// --- Vertex Shader ---
// Generates a full-screen triangle using only the vertex ID
// vID 0: (-1, 1), vID 1: (3, 1), vID 2: (-1, -3)
VS_OUTPUT VSMain(uint vID : SV_VertexID) {
    VS_OUTPUT output;
    output.uv = float2((vID << 1) & 2, vID & 2);
    output.pos = float4(output.uv * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
    return output;
}

// --- Pixel Shader ---
// Handles the actual color pattern generation
float4 PSMain(VS_OUTPUT input) : SV_Target {
    // 1. Setup coordinates
    float2 uv = input.uv;
    float2 p = (uv * 2.0 - 1.0); // Map UV from [0,1] to [-1,1]
    
    // Correct for aspect ratio to keep shapes circular
    float aspect = u_resolution.x / u_resolution.y;
    p.x *= aspect;

    // 2. Base Color Pattern (Moving Rainbow)
    // Uses cos waves shifted by time and position
    float3 col = 0.5 + 0.5 * cos(u_time + uv.xyx + float3(0, 2, 4));
    
    // 3. Circular Ripple Effect
    // d is the distance from the center
    float d = length(p);
    float ripples = sin(d * 15.0 - u_time * 4.0);
    col *= ripples * 0.4 + 0.6;
    
    // 4. Grid Overlay
    // Using fwidth for a consistent line thickness regardless of resolution
    float2 gridLines = abs(frac(uv * 10.0 - 0.5) - 0.5) / fwidth(uv * 10.0);
    
    // gridIntensity avoids the 'line' keyword conflict
    float gridIntensity = min(gridLines.x, gridLines.y);
    
    // Apply a subtle white glow to the grid lines
    col += (1.0 - min(gridIntensity, 1.0)) * 0.3;

    // 5. Output final RGBA color
    return float4(col, 1.0);
}