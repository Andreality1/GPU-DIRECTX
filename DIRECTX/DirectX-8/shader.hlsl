cbuffer ShaderData : register(b0) {
    float u_time;
    float3 padding; 
};

struct VS_INPUT {
    float3 pos : POSITION;
};

struct PS_INPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD;
};

PS_INPUT VS(VS_INPUT input) {
    PS_INPUT output;
    output.pos = float4(input.pos, 1.0f);
    output.uv = input.pos.xy; 
    return output;
}

// Rotate function using HLSL 'lerp'
float3 rotateY(float3 p, float a) {
    float s = sin(a);
    float c = cos(a);
    return float3(p.x * c + p.z * s, p.y, p.z * c - p.x * s);
}

float map(float3 p) {
    // Spin the object over time
    float3 q = rotateY(p, u_time);
    
    // Create a Rounded Box
    float3 b = float3(0.5, 0.5, 0.5);
    float3 d = abs(q) - b;
    return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0) - 0.1;
}

float4 PS(PS_INPUT input) : SV_Target {
    // Adjust aspect ratio (assuming 800x600)
    float2 uv = input.uv * float2(1.33, 1.0);
    
    float3 ro = float3(0, 0, -3); // Camera moved back to -3
    float3 rd = normalize(float3(uv, 1.5)); 

    float t = 0.0;
    for(int i = 0; i < 80; i++) {
        float3 p = ro + rd * t;
        float d = map(p);
        
        if(d < 0.001) {
            // Simple diffuse lighting based on 'fake' normals
            float3 lightDir = normalize(float3(1, 1, -1));
            float3 grad = float3(
                map(p + float3(0.01, 0, 0)) - map(p - float3(0.01, 0, 0)),
                map(p + float3(0, 0.01, 0)) - map(p - float3(0, 0.01, 0)),
                map(p + float3(0, 0, 0.01)) - map(p - float3(0, 0, 0.01))
            );
            float3 normal = normalize(grad);
            float diff = max(dot(normal, lightDir), 0.0);
            
            return float4(float3(0.2, 0.4, 0.8) * diff + 0.1, 1.0);
        }
        
        t += d;
        if(t > 20.0) break;
    }

    // Background gradient
    return float4(0.05, 0.05, 0.1, 1.0) + input.uv.y * 0.1;
}