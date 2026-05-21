// pixel.hlsl

// Constant Buffer - Must match C++ struct alignment (16 bytes)
cbuffer ShaderData : register(b0) {
    float u_time;
    float3 padding; 
};

struct PS_INPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD;
};

// Rotation helper
float3 rotateY(float3 p, float a) {
    float s = sin(a);
    float c = cos(a);
    return float3(p.x * c + p.z * s, p.y, p.z * c - p.x * s);
}

// Distance Function for a Rounded Box
float map(float3 p) {
    float3 q = rotateY(p, u_time);
    
    float3 b = float3(0.5, 0.5, 0.5);
    float3 d = abs(q) - b;
    return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0) - 0.1;
}

// Pixel Shader Entry Point
float4 main(PS_INPUT input) : SV_Target {
    // 1. Fix Aspect Ratio (800 / 600 = 1.33)
    float2 uv = input.uv * float2(1.33, 1.0);
    
    // 2. Setup Camera
    float3 ro = float3(0, 0, -3);          // Camera position
    float3 rd = normalize(float3(uv, 1.5)); // Ray direction
    
    // 3. Raymarching Loop
    float t = 0.0;
    for(int i = 0; i < 80; i++) {
        float3 p = ro + rd * t;
        float d = map(p);
        
        // If we hit the surface
        if(d < 0.001) {
            // Calculate a basic "fake" normal for lighting
            float3 lightDir = normalize(float3(1, 1, -1));
            float3 eps = float3(0.01, 0, 0);
            float3 normal = normalize(float3(
                map(p + eps.xyy) - map(p - eps.xyy),
                map(p + eps.yxy) - map(p - eps.yxy),
                map(p + eps.yyx) - map(p - eps.yyx)
            ));
            
            float diff = max(dot(normal, lightDir), 0.0);
            float3 color = float3(0.2, 0.5, 0.9) * diff + 0.1; // Blue-ish light
            
            return float4(color, 1.0);
        }
        
        t += d;
        if(t > 20.0) break; // Optimization: Stop if ray goes too far
    }

    // 4. Background (Dark grey/blue gradient)
    return float4(0.05, 0.05, 0.1, 1.0) + (input.uv.y * 0.05);
}