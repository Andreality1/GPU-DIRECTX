struct PS_INPUT {
    float4 pos : SV_POSITION;
};

// This replaces your Uniforms. Must be 16-byte aligned.
cbuffer Constants : register(b0) {
    float u_time;
    float2 u_resolution;
    float padding;
};

struct ControlPoint {
    float3 pos;
    float weight;
};

struct Hit {
    float dist;
    float2 uv;
    float id; 
};

// Helper Math
float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z *显示 mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float3 getBasis(float t) {
    float invT = 1.0 - t;
    return float3(invT * invT, 2.0 * t * invT, t * t);
}

float3 getPatchPoint(float u, float v, ControlPoint cp[9]) {
    float3 bU = getBasis(u);
    float3 bV = getBasis(v);
    float3 pSum = float3(0,0,0);
    float wSum = 0.0;
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
            float w = bU[i] * bV[j] * cp[i * 3 + j].weight;
            pSum += cp[i * 3 + j].pos * w;
            wSum += w;
        }
    }
    return pSum / max(wSum, 0.00001);
}

// ... (Logic for getNURBSSDF and sceneSDF follows same pattern as your GLSL) ...

float4 PS(PS_INPUT input) : SV_Target {
    float2 uv_scr = (input.pos.xy - 0.5 * u_resolution.xy) / min(u_resolution.y, u_resolution.x);
    
    // Top-down camera
    float3 ro = float3(2.0, 10.0, 2.0);
    float3 target = float3(2.0, 0.0, 2.0);
    float3 f = normalize(target - ro);
    float3 r = normalize(cross(float3(0, 0, -1), f));
    float3 u = cross(f, r);
    float3 rd = normalize(f * 2.0 + uv_scr.x * r + uv_scr.y * u);

    // Raymarching loop (Reduced steps for performance)
    float t = 0.0;
    for(int i = 0; i < 64; i++) {
        // [Insert SDF Logic here]
    }
    
    return float4(0.1, 0.1, 0.1, 1.0); // Output
}