// Must be 16-byte aligned to match C++ struct
cbuffer ShaderData : register(b0) {
    float u_time;
    float3 padding; 
};

struct PS_INPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD;
};

// --- Helpers ---

float2 rotate(float2 p, float a) {
    float s = sin(a), c = cos(a);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// 2D Triangle Distance Function
float sdTriangle(float2 p, float2 p0, float2 p1, float2 p2) {
    float2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
    float2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                       float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

// --- Scene ---

float map(float3 p) {
    // 1. Floor: Now correctly at the bottom (y = -1.0)
    float d = p.y + 1.0;
    
    // 2. Spinning Triangle
    float3 pTri = p;
    // Rotate triangle around the Y axis
    pTri.xz = rotate(pTri.xz, u_time * 2.0);
    
    // Define vertices (Pointing UP: Top is +1.0, Bottom is -0.5)
    float2 v1 = float2(0.0, 1.0);     // Top Peak
    float2 v2 = float2(-0.8, -0.5);  // Bottom Left
    float2 v3 = float2(0.8, -0.5);   // Bottom Right
    
    float dist2D = sdTriangle(pTri.xy, v1, v2, v3);
    
    // Give it a tiny bit of thickness so it's visible to the ray
    float triangle3D = max(dist2D, abs(pTri.z) - 0.01);
    
    return min(d, triangle3D);
}

float3 getNormal(float3 p) {
    float2 e = float2(0.001, 0.0);
    return normalize(float3(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

// --- Main ---

float4 main(PS_INPUT input) : SV_TARGET {
    // CRITICAL FIX: (1.0, -1.0) flips the Y-axis so +Y is UP and -Y is DOWN
    float2 uv = (input.uv * 2.0 - 1.0) * float2(1.0, -1.0);
    uv.x *= 1.77; // Aspect ratio adjustment

    // Camera setup
    float3 ro = float3(0.0, 0.5, -3.0);
    float3 rd = normalize(float3(uv, 1.2));
    
    float t = 0.0;
    for(int i = 0; i < 100; i++) {
        float3 p = ro + rd * t;
        float d = map(p);
        if(d < 0.001 || t > 20.0) break;
        t += d;
    }

    float3 col = float3(0.05, 0.05, 0.1); // Background color
    
    if(t < 20.0) {
        float3 p = ro + rd * t;
        float3 n = getNormal(p);
        
        // Lighting
        float3 lightDir = normalize(float3(1.0, 2.0, -1.0));
        float diff = max(dot(n, lightDir), 0.2);
        
        // Color: Gray for floor, Rainbow for Triangle
        float3 baseCol = (p.y > -0.98) ? (n * 0.5 + 0.5) : float3(0.2, 0.2, 0.2);
        col = baseCol * diff;
    }

    return float4(col, 1.0);
}