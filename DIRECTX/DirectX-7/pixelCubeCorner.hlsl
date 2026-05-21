// pixel.hlsl
cbuffer ShaderData : register(b0) {
    float u_time;
    float2 u_resolution;
    float padding;
};

struct PS_INPUT {
    float4 pos : SV_POSITION; 
    float2 uv  : TEXCOORD;    
};

// --- Cube SDF ---
float sdBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// --- Rotation Helper ---
float3x3 rotateY(float a) {
    float c = cos(a), s = sin(a);
    return float3x3(c, 0, s, 0, 1, 0, -s, 0, c);
}

float3x3 rotateX(float a) {
    float c = cos(a), s = sin(a);
    return float3x3(1, 0, 0, 0, c, -s, 0, s, c);
}

float4 main(PS_INPUT input) : SV_Target {
    // 1. Center UVs: Map 0..1 to -1..1
    float2 uv = input.uv * 2.0 - 1.0;
    
    // 2. Fix Aspect Ratio (Fallback to 1.33 if resolution is missing)
    float aspect = (u_resolution.y > 0) ? (u_resolution.x / u_resolution.y) : 1.33;
    uv.x *= aspect;
    
    // 3. Camera Setup
    float3 ro = float3(0, 0, -5);          // Ray Origin (Camera position)
    float3 rd = normalize(float3(uv, 1.0)); // Ray Direction

    // 4. Raymarching Loop
    float t = 0.0;
    bool hit = false;
    float3 p;

    for(int i = 0; i < 64; i++) {
        p = ro + rd * t;
        
        // Rotate the cube over time
        float3x3 rot = mul(rotateY(u_time), rotateX(u_time * 0.5));
        float3 q = mul(rot, p);
        
        float d = sdBox(q, float3(1, 1, 1)); // 1x1x1 Cube
        
        if(d < 0.001) {
            hit = true;
            break;
        }
        t += d;
        if(t > 20.0) break;
    }

    // 5. Coloring
    if(hit) {
        // Simple lighting based on distance
        float light = 1.0 - (t / 10.0);
        return float4(light, light * 0.5, light * 0.2, 1.0); // Orange-ish cube
    }

    // Background: If you see this Blue, the shader is active!
    return float4(0.1, 0.2, 0.4, 1.0); 
}