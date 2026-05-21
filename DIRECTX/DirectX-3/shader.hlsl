// shader.hlsl

struct VS_OUTPUT {
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD;
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

cbuffer Constants : register(b0) {
    float u_time;
    float2 u_resolution;
    float2 padding; 
};

static const int MAX_STEPS = 128;
static const float SURF_DIST = 0.001f;
static const float MAX_DIST = 40.0f;

// --- Vertex Shader ---
VS_OUTPUT VSMain(uint vID : SV_VertexID) {
    VS_OUTPUT output;
    output.uv = float2((vID << 1) & 2, vID & 2);
    output.pos = float4(output.uv * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
    return output;
}

// --- HELPER FOR CHROMATIC SCALE ---
float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0f, 2.0f / 3.0f, 1.0f / 3.0f, 3.0f);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0f - K.www);
    return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0f, 1.0f), c.y);
}

// --- NURBS MATHEMATICS ---
float3 getBasis(float t) {
    float invT = 1.0f - t;
    return float3(invT * invT, 2.0f * t * invT, t * t);
}

float3 getPatchPoint(float u, float v, ControlPoint cp[9]) {
    float3 bU = getBasis(u);
    float3 bV = getBasis(v);
    float3 pSum = float3(0, 0, 0);
    float wSum = 0.0f;
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
            float w = bU[i] * bV[j] * cp[i * 3 + j].weight;
            pSum += cp[i * 3 + j].pos * w;
            wSum += w;
        }
    }
    return pSum / max(wSum, 0.00001f);
}

Hit getNURBSSDF(float3 p, ControlPoint cp[9]) {
    float2 uv = float2(0.5f, 0.5f);
    float minDistSq = 1e10f;
    const int GRID = 8; 
    for(int i = 0; i <= GRID; i++) {
        for(int j = 0; j <= GRID; j++) {
            float2 testUV = float2(float(i)/float(GRID), float(j)/float(GRID));
            float3 pS = getPatchPoint(testUV.x, testUV.y, cp);
            float d2 = dot(p - pS, p - pS);
            if(d2 < minDistSq) { minDistSq = d2; uv = testUV; }
        }
    }
    for(int k = 0; k < 6; k++) {
        float3 pS = getPatchPoint(uv.x, uv.y, cp);
        float e = 0.001f;
        float3 du = (getPatchPoint(uv.x + e, uv.y, cp) - pS) / e;
        float3 dv = (getPatchPoint(uv.x, uv.y + e, cp) - pS) / e;
        float3 r = pS - p;
        float a = dot(du, du);
        float b = dot(du, dv);
        float c = dot(dv, dv);
        float det = a * c - b * b;
        float2 delta = float2(dot(r, du) * c - dot(r, dv) * b, 
                             dot(r, dv) * a - dot(r, du) * b) / (det + 1e-6f);
        uv = clamp(uv - delta * 0.5f, 0.0f, 1.0f); 
    }
    float3 pOnSurface = getPatchPoint(uv.x, uv.y, cp);
    Hit h;
    h.dist = length(p - pOnSurface) - 0.02f;
    h.uv = uv;
    h.id = 1.0f;
    return h;
}

Hit sceneSDF(float3 p) {
    ControlPoint cp[9];
    float R = 4.0f;
    float w = 0.70710678f; 
    float micro = 0.0001f; 
    
    cp[0].pos = float3(micro, 0, 0); cp[0].weight = 1.0;
    cp[1].pos = float3(micro, 0, micro); cp[1].weight = 1.0;
    cp[2].pos = float3(0, 0, micro); cp[2].weight = 1.0;
    cp[3].pos = float3(R*0.5, 0, 0); cp[3].weight = 1.0;
    cp[4].pos = float3(R*0.5, 0, R*0.5); cp[4].weight = w;
    cp[5].pos = float3(0, 0, R*0.5); cp[5].weight = 1.0;
    cp[6].pos = float3(R, 0, 0); cp[6].weight = 1.0;
    cp[7].pos = float3(R, 0, R); cp[7].weight = w;
    cp[8].pos = float3(0, 0, R); cp[8].weight = 1.0;

    Hit res = getNURBSSDF(p, cp);
    
    for(int i = 0; i < 9; i++) {
        float d = length(p - cp[i].pos) - 0.15f;
        if(d < res.dist) {
            res.dist = d;
            res.uv = float2(0,0);
            res.id = 2.0f + float(i);
        }
    }
    return res;
}

float3 getNormal(float3 p) {
    float2 e = float2(0.001f, 0.0f);
    return normalize(float3(
        sceneSDF(p + e.xyy).dist - sceneSDF(p - e.xyy).dist,
        sceneSDF(p + e.yxy).dist - sceneSDF(p - e.yxy).dist,
        sceneSDF(p + e.yyx).dist - sceneSDF(p - e.yyx).dist
    ));
}

// --- Pixel Shader ---
float4 PSMain(VS_OUTPUT input) : SV_Target {
    float2 uv_scr = (input.uv * 2.0f - 1.0f);
    float aspect = u_resolution.x / u_resolution.y;
    uv_scr.x *= aspect;
    
    // Top-down camera setup
    float3 ro = float3(2.0f, 10.0f, 2.0f); 
    float3 target = float3(2.0f, 0.0f, 2.0f);
    
    float3 f = normalize(target - ro);
    float3 r = normalize(cross(float3(0, 0, -1), f)); 
    float3 u = cross(f, r);
    float3 rd = normalize(f * 2.0f + uv_scr.x * r + uv_scr.y * u);

    float t = 0.0f;
    Hit hit;
    for(int i = 0; i < MAX_STEPS; i++) {
        hit = sceneSDF(ro + t * rd);
        if(abs(hit.dist) < SURF_DIST || t > MAX_DIST) break;
        t += hit.dist;        
    }

    float3 color = float3(0.015f, 0.015f, 0.02f);

    if(t < MAX_DIST) {
        float3 p = ro + t * rd;
        float3 n = getNormal(p);
        float3 lightDir = normalize(float3(1.0, 2.0, 1.0));
        float diff = max(dot(n, lightDir), 0.0f);
        
        if(hit.id < 1.5f) { 
            float2 grid = floor(hit.uv * 10.0f);
            float checker = fmod(grid.x + grid.y, 2.0f);
            color = lerp(float3(0.08, 0.08, 0.08), float3(0.12, 0.12, 0.12), abs(checker)) * (diff + 0.3f);
        } else { 
            float noteIndex = hit.id - 2.0f; 
            float3 chromaticColor = hsv2rgb(float3(noteIndex / 12.0f, 0.85f, 1.0f));
            color = chromaticColor * (diff + 0.6f) + (chromaticColor * 0.4f);
        }
    }

    return float4(pow(max(color, 0.0f), 0.4545f), 1.0f);
}