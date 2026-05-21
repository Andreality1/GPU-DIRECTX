// pixel.hlsl

cbuffer ShaderData : register(b0) {
    float u_time;
    float3 padding; 
};

struct PS_INPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD;
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

// --- MATH HELPERS ---

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

float dfLine(float3 p, float3 a, float3 b) {
    float3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

float dfSphere(float3 p, float3 center, float radius) {
    return length(p - center) - radius;
}

float3 getBasis(float t) {
    float invT = 1.0 - t;
    return float3(invT * invT, 2.0 * t * invT, t * t);
}

float3 getPatchPoint(float u, float v, ControlPoint cp[9]) {
    float3 bU = getBasis(u);
    float3 bV = getBasis(v);
    float3 pSum = float3(0.0, 0.0, 0.0);
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

float solveNURBS(float3 p, ControlPoint cp[9], out float2 outUV) {
    float2 uv = float2(0.5, 0.5);
    float minDistSq = 1e10;
    const int GRID = 4; 
    for(int i = 0; i <= GRID; i++) {
        for(int j = 0; j <= GRID; j++) {
            float2 testUV = float2(float(i)/float(GRID), float(j)/float(GRID));
            float3 pS = getPatchPoint(testUV.x, testUV.y, cp);
            float3 diff = p - pS;
            float d2 = dot(diff, diff);
            if(d2 < minDistSq) { minDistSq = d2; uv = testUV; }
        }
    }
    for(int k = 0; k < 5; k++) {
        float3 pS = getPatchPoint(uv.x, uv.y, cp);
        float e = 0.001;
        float3 du = (getPatchPoint(uv.x + e, uv.y, cp) - pS) / e;
        float3 dv = (getPatchPoint(uv.x, uv.y + e, cp) - pS) / e;
        float3 r = pS - p;
        float a = dot(du, du);
        float b = dot(du, dv);
        float c = dot(dv, dv);
        float det = a * c - b * b;
        if (abs(det) < 1e-7) break; 
        float2 delta = float2(dot(r, du) * c - dot(r, dv) * b, 
                             dot(r, dv) * a - dot(r, du) * b) / det;
        uv = clamp(uv - delta * 0.5, 0.0, 1.0); 
    }
    outUV = uv;
    return length(p - getPatchPoint(uv.x, uv.y, cp));
}

float getControlVisuals(float3 p, ControlPoint cp[9], out float dPoints) {
    float dNet = 1e10;
    dPoints = 1e10;
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
            dPoints = min(dPoints, dfSphere(p, cp[i*3+j].pos, 0.18));
            if (i < 2) dNet = min(dNet, dfLine(p, cp[i*3+j].pos, cp[(i+1)*3+j].pos));
            if (j < 2) dNet = min(dNet, dfLine(p, cp[i*3+j].pos, cp[i*3+(j+1)].pos));
        }
    }
    return dNet - 0.015;
}

// --- SCENE ---

Hit sceneSDF(float3 p) {
    float oscillation = sin(u_time * 2.0) * 3.0;
    float w_circ = 0.70710678;
    
    // 1. SLAB
    float3 pSlabFold = float3(abs(p.x), p.y - oscillation, abs(p.z));
    ControlPoint cpSlab[9];
    float R_anim = 3.0 * (0.75 + 0.25 * sin(u_time * 2.0)); 
    float m = 0.001;
    cpSlab[0].pos=float3(m,0,0); cpSlab[0].weight=1.; cpSlab[1].pos=float3(m,0,m); cpSlab[1].weight=1.; cpSlab[2].pos=float3(0,0,m); cpSlab[2].weight=1.;
    cpSlab[3].pos=float3(R_anim*.5,0,0); cpSlab[3].weight=1.; cpSlab[4].pos=float3(R_anim*.5,0,R_anim*.5); cpSlab[4].weight=w_circ; cpSlab[5].pos=float3(0,0,R_anim*.5); cpSlab[5].weight=1.;
    cpSlab[6].pos=float3(R_anim,0,0); cpSlab[6].weight=1.; cpSlab[7].pos=float3(R_anim,0,R_anim); cpSlab[7].weight=w_circ; cpSlab[8].pos=float3(0,0,R_anim); cpSlab[8].weight=1.;

    float2 uvSlab;
    float dSlabSurf = solveNURBS(pSlabFold, cpSlab, uvSlab);
    dSlabSurf = max(dSlabSurf - 0.05, abs(p.y - oscillation) - 0.4);
    float dSlabPoints;
    float dSlabNet = getControlVisuals(pSlabFold, cpSlab, dSlabPoints);

    // 2. PILLAR
    float3 pPillFold = float3(abs(p.x), p.y, abs(p.z));
    if (pPillFold.z > pPillFold.x) pPillFold.xz = pPillFold.zx;
    ControlPoint cpPill[9];
    float radius = 3.0; float halfH = 2.0;   
    for(int i = 0; i < 3; i++) {
        float y = (float(i) - 1.0) * halfH;
        cpPill[i*3+0].pos = float3(radius, y, 0.0); cpPill[i*3+0].weight = 1.0;
        cpPill[i*3+1].pos = float3(radius, y, radius); cpPill[i*3+1].weight = w_circ;
        cpPill[i*3+2].pos = float3(0.0,    y, radius); cpPill[i*3+2].weight = 1.0;
    }

    float2 uvPill;
    float dPillSurf = solveNURBS(pPillFold, cpPill, uvPill) - 0.1;
    float dPillPoints;
    float dPillNet = getControlVisuals(pPillFold, cpPill, dPillPoints);

    // 3. COMPOSITION
    float k = 0.8;
    float h = clamp(0.5 + 0.5 * (dPillSurf - dSlabSurf) / k, 0.0, 1.0);
    float dScene = lerp(dPillSurf, dSlabSurf, h) - k * h * (1.0 - h);
    
    Hit res;
    res.dist = dScene; res.uv = lerp(uvPill, uvSlab, h); res.id = lerp(2.0, 1.0, h);

    if (dSlabNet < res.dist) { res.dist = dSlabNet; res.uv = float2(0,0); res.id = 3.0; }
    if (dPillNet < res.dist) { res.dist = dPillNet; res.uv = float2(0,0); res.id = 4.0; }
    float allPoints = min(dSlabPoints, dPillPoints);
    if (allPoints < res.dist) { res.dist = allPoints; res.uv = float2(0,0); res.id = 5.0; }

    return res;
}

float3 getNormal(float3 p) {
    float2 e = float2(0.005, 0.0);
    return normalize(float3(
        sceneSDF(p + e.xyy).dist - sceneSDF(p - e.xyy).dist,
        sceneSDF(p + e.yxy).dist - sceneSDF(p - e.yxy).dist,
        sceneSDF(p + e.yyx).dist - sceneSDF(p - e.yyx).dist
    ));
}

float4 main(PS_INPUT input) : SV_Target {
    float2 uv_s = input.uv * float2(1.33, 1.0);
    
    float t_cam = u_time * 0.15;
    float3 ro = float3(cos(t_cam) * 14.0, 8.0, sin(t_cam) * 14.0);
    float3 tar = float3(0, 1.0, 0);
    float3 f = normalize(tar - ro);
    float3 r = normalize(cross(float3(0,1,0), f));
    float3 u = cross(f, r);
    float3 rd = normalize(f * 2.0 + uv_s.x * r + uv_s.y * u);

    float d = 0.0;
    Hit hit;
    // Set steps slightly lower for NURBS performance
    for(int i = 0; i < 80; i++) { 
        hit = sceneSDF(ro + d * rd);
        if(abs(hit.dist) < 0.005 || d > 40.0) break;
        d += hit.dist * 0.6; 
    }

    float3 bg = float3(0.01, 0.01, 0.02);
    float3 col = bg;

    if(d < 40.0) {
        if (hit.id >= 3.0) {
            if (hit.id == 3.0) col = float3(1.0, 0.4, 0.1);      
            else if (hit.id == 4.0) col = float3(0.0, 1.0, 0.8); 
            else if (hit.id == 5.0) col = float3(1.0, 0.9, 0.2); 
        } else {
            float3 p = ro + d * rd;
            float3 n = getNormal(p);
            float3 l = normalize(float3(1, 2, 1));
            float diff = max(dot(n, l), 0.0);
            
            // Fixed checkerboard and pattern logic with HLSL equivalents
            float3 colSlab = lerp(float3(0.2, 0.2, 0.25), float3(0.3, 0.3, 0.4), abs(fmod(floor(hit.uv.x*8.) + floor(hit.uv.y*8.), 2.0)));
            float3 colPillar = lerp(float3(0.1, 0.4, 0.8), float3(1.0, 1.0, 1.0), (step(0.95, frac(hit.uv.x * 4.0)) + step(0.95, frac(hit.uv.y * 4.0))) * 0.4);
            
            float slabWeight = clamp(2.0 - hit.id, 0.0, 1.0);
            float3 albedo = lerp(colPillar, colSlab, slabWeight);
            
            col = albedo * (diff + 0.15);
            float spec = pow(max(dot(reflect(-l, n), -rd), 0.0), 32.0);
            col += spec * 0.4;
        }
        col = lerp(col, bg, 1.0 - exp(-0.0005 * d * d));
    }

    // Gamma correction
    return float4(pow(max(col, 0.0), 0.4545), 1.0);
}