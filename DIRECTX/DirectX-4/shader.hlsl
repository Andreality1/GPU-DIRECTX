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
static const float SURF_DIST = 0.005f;
static const float MAX_DIST = 40.0f;

// --- Vertex Shader ---
VS_OUTPUT VSMain(uint vID : SV_VertexID) {
    VS_OUTPUT output;
    output.uv = float2((vID << 1) & 2, vID & 2);
    output.pos = float4(output.uv * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
    return output;
}

// --- MATH HELPERS ---
float smin(float a, float b, float k) {
    float h = clamp(0.5f + 0.5f * (b - a) / k, 0.0f, 1.0f);
    return lerp(b, a, h) - k * h * (1.0f - h);
}

float dfLine(float3 p, float3 a, float3 b) {
    float3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0f, 1.0f);
    return length(pa - ba * h);
}

float dfSphere(float3 p, float3 center, float radius) {
    return length(p - center) - radius;
}

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

float solveNURBS(float3 p, ControlPoint cp[9], out float2 outUV) {
    float2 uv = float2(0.5f, 0.5f);
    float minDistSq = 1e10f;
    const int GRID = 4; 
    for(int i = 0; i <= GRID; i++) {
        for(int j = 0; j <= GRID; j++) {
            float2 testUV = float2(float(i)/float(GRID), float(j)/float(GRID));
            float3 pS = getPatchPoint(testUV.x, testUV.y, cp);
            float d2 = dot(p - pS, p - pS);
            if(d2 < minDistSq) { minDistSq = d2; uv = testUV; }
        }
    }
    for(int k = 0; k < 5; k++) {
        float3 pS = getPatchPoint(uv.x, uv.y, cp);
        float e = 0.001f;
        float3 du = (getPatchPoint(uv.x + e, uv.y, cp) - pS) / e;
        float3 dv = (getPatchPoint(uv.x, uv.y + e, cp) - pS) / e;
        float3 r = pS - p;
        float a = dot(du, du);
        float b = dot(du, dv);
        float c = dot(dv, dv);
        float det = a * c - b * b;
        if (abs(det) < 1e-7f) break; 
        float2 delta = float2(dot(r, du) * c - dot(r, dv) * b, 
                             dot(r, dv) * a - dot(r, du) * b) / det;
        uv = clamp(uv - delta * 0.5f, 0.0f, 1.0f); 
    }
    outUV = uv;
    return length(p - getPatchPoint(uv.x, uv.y, cp));
}

float getControlVisuals(float3 p, ControlPoint cp[9], out float dPoints) {
    float dNet = 1e10f;
    dPoints = 1e10f;
    float netThickness = 0.015f;
    float pointRadius = 0.18f;

    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
            dPoints = min(dPoints, dfSphere(p, cp[i*3+j].pos, pointRadius));
            if (i < 2) dNet = min(dNet, dfLine(p, cp[i*3+j].pos, cp[(i+1)*3+j].pos));
            if (j < 2) dNet = min(dNet, dfLine(p, cp[i*3+j].pos, cp[i*3+(j+1)].pos));
        }
    }
    return dNet - netThickness;
}

// --- SCENE ---

Hit sceneSDF(float3 p) {
    float oscillation = sin(u_time * 2.0f) * 3.0f;
    float w_circ = 0.70710678f;
    
    // --- 1. SLAB ---
    float3 pSlab = p;
    pSlab.y -= oscillation;
    float3 pSlabFold = float3(abs(pSlab.x), pSlab.y, abs(pSlab.z));
    
    ControlPoint cpSlab[9];
    float R_anim = 3.0f * (0.75f + 0.25f * sin(u_time * 2.0f)); 
    float m = 0.001f;
    cpSlab[0].pos=float3(m,0,0); cpSlab[0].weight=1.; cpSlab[1].pos=float3(m,0,m); cpSlab[1].weight=1.; cpSlab[2].pos=float3(0,0,m); cpSlab[2].weight=1.;
    cpSlab[3].pos=float3(R_anim*.5,0,0); cpSlab[3].weight=1.; cpSlab[4].pos=float3(R_anim*.5,0,R_anim*.5); cpSlab[4].weight=w_circ; cpSlab[5].pos=float3(0,0,R_anim*.5); cpSlab[5].weight=1.;
    cpSlab[6].pos=float3(R_anim,0,0); cpSlab[6].weight=1.; cpSlab[7].pos=float3(R_anim,0,R_anim); cpSlab[7].weight=w_circ; cpSlab[8].pos=float3(0,0,R_anim); cpSlab[8].weight=1.;

    float2 uvSlab;
    float dSlabSurf = solveNURBS(pSlabFold, cpSlab, uvSlab);
    dSlabSurf = max(dSlabSurf - 0.05f, abs(pSlab.y) - 0.4f);
    
    float dSlabPoints;
    float dSlabNet = getControlVisuals(pSlabFold, cpSlab, dSlabPoints);

    // --- 2. PILLAR ---
    float3 pPillFold = float3(abs(p.x), p.y, abs(p.z));
    if (pPillFold.z > pPillFold.x) {
        float tmp = pPillFold.x; pPillFold.x = pPillFold.z; pPillFold.z = tmp;
    }
    
    ControlPoint cpPill[9];
    float radius = 3.0f; float halfH = 2.0f;   
    for(int i = 0; i < 3; i++) {
        float y = (float(i) - 1.0f) * halfH;
        cpPill[i*3+0].pos = float3(radius, y, 0.0f);   cpPill[i*3+0].weight = 1.0f;
        cpPill[i*3+1].pos = float3(radius, y, radius); cpPill[i*3+1].weight = w_circ;
        cpPill[i*3+2].pos = float3(0.0f,   y, radius); cpPill[i*3+2].weight = 1.0f;
    }

    float2 uvPill;
    float dPillSurf = solveNURBS(pPillFold, cpPill, uvPill) - 0.1f;
    float dPillPoints;
    float dPillNet = getControlVisuals(pPillFold, cpPill, dPillPoints);

    // --- 3. COMPOSITION ---
    float k = 0.8f;
    float h = clamp(0.5f + 0.5f * (dPillSurf - dSlabSurf) / k, 0.0f, 1.0f);
    float dScene = smin(dPillSurf, dSlabSurf, k);
    
    Hit res;
    res.dist = dScene;
    res.uv = lerp(uvPill, uvSlab, h);
    res.id = lerp(2.0f, 1.0f, h);

    if (dSlabNet < res.dist) { res.dist = dSlabNet; res.uv = float2(0,0); res.id = 3.0f; }
    if (dPillNet < res.dist) { res.dist = dPillNet; res.uv = float2(0,0); res.id = 4.0f; }

    float allPoints = min(dSlabPoints, dPillPoints);
    if (allPoints < res.dist) { res.dist = allPoints; res.uv = float2(0,0); res.id = 5.0f; }

    return res;
}

float3 getNormal(float3 p) {
    float2 e = float2(0.005f, 0.0f);
    return normalize(float3(
        sceneSDF(p + e.xyy).dist - sceneSDF(p - e.xyy).dist,
        sceneSDF(p + e.yxy).dist - sceneSDF(p - e.yxy).dist,
        sceneSDF(p + e.yyx).dist - sceneSDF(p - e.yyx).dist
    ));
}

float4 PSMain(VS_OUTPUT input) : SV_Target {
    float2 uv_s = (input.uv * 2.0f - 1.0f);
    float aspect = u_resolution.x / u_resolution.y;
    uv_s.x *= aspect;
    
    float t_cam = u_time * 0.15f;
    float3 ro = float3(cos(t_cam) * 14.0f, 8.0f, sin(t_cam) * 14.0f);
    float3 tar = float3(0, 1.0f, 0);
    float3 f = normalize(tar - ro), r = normalize(cross(float3(0,1,0), f)), u = cross(f, r);
    float3 rd = normalize(f * 2.0f + uv_s.x * r + uv_s.y * u);

    float d = 0.0f;
    Hit hit;
    for(int i = 0; i < MAX_STEPS; i++) {
        hit = sceneSDF(ro + d * rd);
        if(abs(hit.dist) < SURF_DIST || d > MAX_DIST) break;
        d += hit.dist * 0.6f; 
    }

    float3 bg = float3(0.01f, 0.01f, 0.02f);
    float3 col = bg;

    if(d < MAX_DIST) {
        if (hit.id >= 3.0f) {
            if (hit.id == 3.0f) col = float3(1.0f, 0.4f, 0.1f);      
            else if (hit.id == 4.0f) col = float3(0.0f, 1.0f, 0.8f); 
            else if (hit.id == 5.0f) col = float3(1.0f, 0.9f, 0.2f); 
        } else {
            float3 p = ro + d * rd;
            float3 n = getNormal(p);
            float3 l = normalize(float3(1, 2, 1));
            float diff = max(dot(n, l), 0.0f);
            
            float3 colSlab = lerp(float3(0.2, 0.2, 0.25), float3(0.3, 0.3, 0.4), abs(fmod(floor(hit.uv.x*8.0f) + floor(hit.uv.y*8.0f), 2.0f)));
            float3 colPillar = lerp(float3(0.1, 0.4, 0.8), float3(1.0, 1.0, 1.0), (step(0.95f, frac(hit.uv.x * 4.0f)) + step(0.95f, frac(hit.uv.y * 4.0f))) * 0.4f);
            
            float slabWeight = clamp(2.0f - hit.id, 0.0f, 1.0f);
            float3 albedo = lerp(colPillar, colSlab, slabWeight);
            
            col = albedo * (diff + 0.15f);
            float spec = pow(max(dot(reflect(-l, n), -rd), 0.0f), 32.0f);
            col += spec * 0.4f;
        }
        col = lerp(col, bg, 1.0f - exp(-0.0005f * d * d));
    }

    return float4(pow(max(col, 0.0f), 0.4545f), 1.0f);
}