// pixel.hlsl

cbuffer ShaderData : register(b0) {
    float u_time;
    float3 padding; 
};

struct PS_INPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD;
};

// --- Distance Function ---
float2 sdBezier(float3 p, float3 A, float3 B, float3 C) {    
    float3 a = B - A;
    float3 b = A - 2.0*B + C;
    float3 c = a * 2.0;
    float3 d = A - p;
    float kk = max(dot(b,b), 0.00001);
    float k = 1.0 / kk;
    float kx = k * dot(a,b);
    float ky = k * (2.0*dot(a,a)+dot(d,b)) / 3.0;
    float kz = k * dot(d,a);      
    float res = 0.0;
    float p1 = ky - kx*kx;
    float q = kx*(2.0*kx*kx - 3.0*ky) + kz;
    float h = q*q + 4.0*p1*p1*p1;
    if(h >= 0.0) { 
        h = sqrt(h);
        float2 x = (float2(h,-h)-q)/2.0;
        float2 uv = sign(x)*pow(abs(x), float2(0.333, 0.333));
        res = clamp(uv.x+uv.y-kx, 0.0, 1.0);
    } else {
        float z = sqrt(-p1);
        float v = acos(clamp(q/(p1*z*2.0), -1.0, 1.0))/3.0;
        float m = cos(v);
        float n = sin(v)*1.732;
        float3 t = clamp(float3(m+m,-n-m,n-m)-kx, 0.0, 1.0);
        float d1 = length(d+(c+b*t.x)*t.x);
        float d2 = length(d+(c+b*t.y)*t.y);
        res = d1<d2 ? t.x : t.y;
    }
    // Result.x is distance to surface, Result.y is the 't' parameter along the curve (0-1)
    return float2(length(d+(c+b*res)*res) - 0.2, res);
}

// Wrapper for the Normal calculation
float map(float3 p, float3 p0, float3 p1, float3 p2) {
    return sdBezier(p, p0, p1, p2).x;
}

float3 rotateY(float3 p, float a) {
    float s = sin(a); float c = cos(a);
    return float3(p.x * c + p.z * s, p.y, p.z * c - p.x * s);
}

float4 main(PS_INPUT input) : SV_Target {
    float2 uv = input.uv * float2(1.33, 1.0);
    
    float3 ro = float3(0, 0, -5);          
    float3 rd = normalize(float3(uv, 1.5)); 
    
    // Points rotated like the cube
    float angle = u_time * 0.8;
    float3 p0 = rotateY(float3(-1.5, -0.5, 0.0), angle) + float3(0, 0, 1.0);
    float3 p1 = rotateY(float3( 0.0,  1.5, 0.0), angle) + float3(0, 0, 1.0);
    float3 p2 = rotateY(float3( 1.5, -0.5, 0.0), angle) + float3(0, 0, 1.0);

    float t = 0.0;
    for(int i = 0; i < 80; i++) {
        float3 p = ro + rd * t;
        float2 res = sdBezier(p, p0, p1, p2);
        float d = res.x; 
        
        if(d < 0.001) {
            // --- CUBE-STYLE SHADING START ---
            float3 lightDir = normalize(float3(1, 1, -1));
            float2 e = float2(0.01, 0);
            
            // Calculate Normal (The direction the surface is facing)
            float3 normal = normalize(float3(
                map(p + e.xyy, p0, p1, p2) - map(p - e.xyy, p0, p1, p2),
                map(p + e.yxy, p0, p1, p2) - map(p - e.yxy, p0, p1, p2),
                map(p + e.yyx, p0, p1, p2) - map(p - e.yyx, p0, p1, p2)
            ));
            
            // Diffuse Lighting
            float diff = max(dot(normal, lightDir), 0.0);
            
            // Color based on position along the curve (res.y)
            float3 baseColor = 0.5 + 0.5 * cos(u_time + res.y + float3(0, 2, 4));
            
            float3 finalCol = baseColor * diff + (0.1 * baseColor); // Add ambient
            return float4(finalCol, 1.0);
            // --- CUBE-STYLE SHADING END ---
        }
        
        t += d;
        if(t > 20.0) break;
    }

    return float4(0.05, 0.05, 0.1, 1.0) + (input.uv.y * 0.05);
}