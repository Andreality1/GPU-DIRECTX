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

float3 getPalette(float t) {
    float3 a = float3(0.5, 0.5, 0.5);
    float3 b = float3(0.5, 0.5, 0.5);
    float3 c = float3(1.0, 1.0, 1.0);
    float3 d = float3(0.0, 0.33, 0.67); 
    return a + b * cos(6.28318 * (c * t + d));
}

float2 sdBezier(float3 p, float3 A, float3 B, float3 C) {    
    float3 a = B - A;
    float3 b = A - 2.0 * B + C;
    float3 c = a * 2.0;
    float3 d = A - p;
    float kk = 1.0 / max(dot(b, b), 0.00001);
    float kx = kk * dot(a, b);
    float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);      
    float resT = 0.0;
    float p1 = ky - kx * kx;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * p1 * p1 * p1;
    if(h >= 0.0) { 
        h = sqrt(h);
        float2 x = (float2(h, -h) - q) / 2.0;
        float2 uv = sign(x) * pow(abs(x), float2(0.3333, 0.3333));
        resT = clamp(uv.x + uv.y - kx, 0.0, 1.0);
    } else {
        float z = sqrt(-p1);
        float v = acos(clamp(q / (p1 * z * 2.0), -1.0, 1.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.7320508;
        float3 t = clamp(float3(m + m, -n - m, n - m) - kx, 0.0, 1.0);
        float d1 = length(d + (c + b * t.x) * t.x);
        float d2 = length(d + (c + b * t.y) * t.y);
        resT = (d1 < d2) ? t.x : t.y;
    }
    return float2(length(d + (c + b * resT) * resT), resT);
}

float3x3 rotateY(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return float3x3(c, 0, s, 0, 1, 0, -s, 0, c);
}

float4 main(PS_INPUT input) : SV_Target {
    // --- FALLBACK UV LOGIC ---
    float2 uv;
    if (u_resolution.x > 1.0 && u_resolution.y > 1.0) {
        // Use high-precision screen space if resolution is valid
        uv = (input.pos.xy / u_resolution.xy) * 2.0 - 1.0;
    } else {
        // Fallback to vertex UVs if resolution is missing/0
        uv = input.uv * 2.0 - 1.0;
    }
    
    uv.y = -uv.y; // Correct Y orientation
    float aspect = (u_resolution.y > 1.0) ? (u_resolution.x / u_resolution.y) : 1.33;
    uv.x *= aspect;

    // Camera and Scene
    float3 ro = float3(0.0, 0.0, -4.5); 
    float3 rd = normalize(float3(uv, 1.2)); 
    float3x3 rot = rotateY(u_time * 0.6);

    float3 p0 = mul(rot, float3(-1.5, -0.5 + sin(u_time), 0.5)) + float3(0,0,3.5);
    float3 p1 = mul(rot, float3(0.0, 1.5, 0.0)) + float3(0,0,3.5);
    float3 p2 = mul(rot, float3(1.5, -0.5, -0.5)) + float3(0,0,3.5);

    float t = 0.0;
    float curve_t = 0.0;
    bool hit = false;
    
    for(int i = 0; i < 64; i++) {
        float2 res = sdBezier(ro + rd * t, p0, p1, p2);
        float d = res.x - 0.2;
        if(d < 0.001) { hit = true; curve_t = res.y; break; }
        t += d;
        if(t > 20.0) break;
    }

    float3 col = float3(0.01, 0.01, 0.03);
    if(hit) {
        float3 hueCol = getPalette(curve_t + u_time * 0.2);
        float rim = pow(1.0 - max(0.0, dot(-rd, float3(0,0,1))), 3.0);
        col = hueCol * exp(-0.1 * t) + (rim * 0.4 * hueCol);
    }

    return float4(pow(max(col, 0.0), 0.4545), 1.0);
    // return float4(input.uv.x, input.uv.y, 0.0, 1.0);
}