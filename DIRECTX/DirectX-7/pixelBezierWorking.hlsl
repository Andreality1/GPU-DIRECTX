// pixel.hlsl

cbuffer ShaderData : register(b0) {
    float u_time;
    float3 padding; // Matches your working cube's alignment
};

struct PS_INPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD;
};

// Standard Bezier SDF (Safe version)
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
    return float2(length(d+(c+b*res)*res), res);
}

float3 rotateY(float3 p, float a) {
    float s = sin(a);
    float c = cos(a);
    return float3(p.x * c + p.z * s, p.y, p.z * c - p.x * s);
}

float4 main(PS_INPUT input) : SV_Target {
    // 1. Use the EXACT same UV math as the working cube
    float2 uv = input.uv * float2(1.33, 1.0);
    
    // 2. Setup Camera
    float3 ro = float3(0, 0, -5);          
    float3 rd = normalize(float3(uv, 1.5)); 
    
    // 3. Setup Bezier Points (Rotated like the cube)
    float angle = u_time * 0.8;
    float3 p0 = rotateY(float3(-1.5, -0.5, 0.0), angle) + float3(0, 0, 1.0);
    float3 p1 = rotateY(float3( 0.0,  1.5, 0.0), angle) + float3(0, 0, 1.0);
    float3 p2 = rotateY(float3( 1.5, -0.5, 0.0), angle) + float3(0, 0, 1.0);

    // 4. Raymarching Loop
    float t = 0.0;
    for(int i = 0; i < 80; i++) {
        float3 p = ro + rd * t;
        float2 res = sdBezier(p, p0, p1, p2);
        float d = res.x - 0.2; // thickness
        
        if(d < 0.001) {
            // Simple lighting
            float fade = 1.0 - (t / 15.0);
            float3 color = float3(0.2, 0.8, 0.5) * fade; // Greenish curve
            return float4(color, 1.0);
        }
        
        t += d;
        if(t > 20.0) break;
    }

    // 5. Background
    return float4(0.05, 0.05, 0.1, 1.0);
}