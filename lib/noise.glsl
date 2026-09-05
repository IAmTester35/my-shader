#ifndef NOISE_GLSL
#define NOISE_GLSL

/*
 * ==============================================================================
 *  HIGH-PRECISION PROCEDURAL & BLUE NOISE LIBRARY (GLSL 120 COMPLIANT)
 *  Features:
 *   1. C2-continuous Gradient Noise 2D & 3D (Quintic Hermite)
 *   2. FBM (Fractal Brownian Motion) multi-octave synthesis
 *   3. Voronoi / Cellular 2D & 3D noise (Worley / Perlin-Worley)
 *   4. High-Frequency Noise & Dithering System:
 *      - Procedural high-frequency Interleaved Gradient Noise (Jorge Jimenez IGN)
 *      - Triangular Probability Density Function (TPDF) shaping (Christoph Peters)
 *      - Procedural raymarching jittering (eliminates volumetric slice banding)
 *      - TPDF sRGB dithering to eliminate 8-bit color quantization banding
 * ==============================================================================
 */

// --- 1. PSEUDO-RANDOM HASH FUNCTIONS (Dave Hoskins "Hash without Sine") ---
// Deterministic pseudo-random mappings using fract multiplication and vector dot-products
// Magic constants: 0.1031 scale spreads bits across mantissa; 33.33 offset breaks periodic alignment

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float hash31(vec3 p) {
    vec3 p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 hash33(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

// 2D Unit Gradient Generator
vec2 grad2(vec2 p) {
    float a = hash21(p) * 6.28318530718;
    return vec2(cos(a), sin(a));
}

// Uniform 3D Unit Gradient Generator (Archimedes spherical projection: strictly isotropic, eliminates cube-corner clustering)
vec3 grad3(vec3 p) {
    vec2 h = hash22(p.xy + p.z * 37.1);
    float z = h.x * 2.0 - 1.0;
    float phi = h.y * 6.28318530718;
    float r = sqrt(max(0.0, 1.0 - z * z));
    return vec3(r * cos(phi), r * sin(phi), z);
}

// --- 2. C2-CONTINUOUS GRADIENT NOISE (PERLIN / QUINTIC HERMITE) ---
// Replaces low-quality value noise to eliminate square/grid and plateau artifacts

// 2D Gradient Noise with Quintic Hermite interpolation: f^3 * (f * (f * 6 - 15) + 10)
float gradientNoise2D(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    float d00 = dot(grad2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
    float d10 = dot(grad2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
    float d01 = dot(grad2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
    float d11 = dot(grad2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));

    float n = mix(mix(d00, d10, u.x), mix(d01, d11, u.x), u.y);
    return n * 0.70710678 + 0.5; // Map [-sqrt(0.5), sqrt(0.5)] to [0, 1]
}

// 3D Gradient Noise with Quintic Hermite interpolation
float gradientNoise3D(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    float d000 = dot(grad3(i + vec3(0.0, 0.0, 0.0)), f - vec3(0.0, 0.0, 0.0));
    float d100 = dot(grad3(i + vec3(1.0, 0.0, 0.0)), f - vec3(1.0, 0.0, 0.0));
    float d010 = dot(grad3(i + vec3(0.0, 1.0, 0.0)), f - vec3(0.0, 1.0, 0.0));
    float d110 = dot(grad3(i + vec3(1.0, 1.0, 0.0)), f - vec3(1.0, 1.0, 0.0));
    float d001 = dot(grad3(i + vec3(0.0, 0.0, 1.0)), f - vec3(0.0, 0.0, 1.0));
    float d101 = dot(grad3(i + vec3(1.0, 0.0, 1.0)), f - vec3(1.0, 0.0, 1.0));
    float d011 = dot(grad3(i + vec3(0.0, 1.0, 1.0)), f - vec3(0.0, 1.0, 1.0));
    float d111 = dot(grad3(i + vec3(1.0, 1.0, 1.0)), f - vec3(1.0, 1.0, 1.0));

    float x00 = mix(d000, d100, u.x);
    float x10 = mix(d010, d110, u.x);
    float x01 = mix(d001, d101, u.x);
    float x11 = mix(d011, d111, u.x);

    float y0 = mix(x00, x10, u.y);
    float y1 = mix(x01, x11, u.y);

    float n = mix(y0, y1, u.z);
    return n * 0.57735027 + 0.5; // Map [-sqrt(3)/2, sqrt(3)/2] to [0, 1]
}

// --- 3. FRACTAL BROWNIAN MOTION (FBM) ---

// 2D Fractal Brownian Motion - 4 octaves with decorrelated rotation
float fbm2D(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 rot = mat2(0.80, 0.60, -0.60, 0.80);
    for (int i = 0; i < 4; ++i) {
        v += a * gradientNoise2D(p);
        p = rot * p * 2.02;
        a *= 0.5;
    }
    return v;
}

// 2D Fractal Brownian Motion - 6 octaves (high detail for clouds/lunar maria)
float fbm2D_Detailed(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 rot = mat2(0.80, 0.60, -0.60, 0.80);
    for (int i = 0; i < 6; ++i) {
        v += a * gradientNoise2D(p);
        p = rot * p * 2.05;
        a *= 0.5;
    }
    return v;
}

// High-performance early-out 3D FBM for volumetric cloud raymarching
// Bypasses upper octaves when local density cannot reach cloud threshold
float fbm3D_Fast(vec3 p, float cutoff) {
    float v = 0.5 * gradientNoise3D(p);
    p = p * 2.02 + vec3(1.23, 2.45, 3.67);
    v += 0.25 * gradientNoise3D(p);
    
    // Analytical upper bound of remaining octaves:
    // Octave 3 (0.125) + Octave 4 (0.0625) = 0.1875.
    // Since gradientNoise3D outputs in [0, 1], maximum possible upper-octave addition is strictly 0.1875.
    const float REMAINING_OCTAVES_BOUND = 0.1875;
    if (v + REMAINING_OCTAVES_BOUND < cutoff) return v;
    
    p = p * 2.02 + vec3(1.23, 2.45, 3.67);
    v += 0.125 * gradientNoise3D(p);
    p = p * 2.02 + vec3(1.23, 2.45, 3.67);
    v += 0.0625 * gradientNoise3D(p);
    return v;
}

// Voronoi / Cellular 2D noise (craters, star clusters)
float voronoi2D(vec2 p) {
    vec2 n = floor(p);
    vec2 f = fract(p);
    float minDist = 1.0;

    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = hash22(n + g);
            vec2 diff = g + o - f;
            float d = length(diff);
            minDist = min(minDist, d);
        }
    }
    return minDist;
}

// Fast 3D Worley / Cellular Noise (Adaptive 2x2x2 neighborhood centered on sample point)
// Eliminates cell boundary discontinuities without performance penalty
float worley3D_Fast(vec3 p) {
    vec3 id = floor(p);
    vec3 fd = fract(p);
    vec3 base = step(0.5, fd) - vec3(1.0); // -1 or 0 depending on closest octant
    float minDist = 2.0;
    for (int z = 0; z <= 1; ++z) {
        for (int y = 0; y <= 1; ++y) {
            for (int x = 0; x <= 1; ++x) {
                vec3 g = base + vec3(float(x), float(y), float(z));
                vec3 o = hash33(id + g);
                vec3 diff = g + o - fd;
                minDist = min(minDist, dot(diff, diff));
            }
        }
    }
    return clamp(sqrt(minDist), 0.0, 1.0);
}

// 3D Cellular Worley Noise (3x3x3 neighborhood for high-fidelity cloud crowns)
float worley3D(vec3 p) {
    vec3 id = floor(p);
    vec3 fd = fract(p);
    float minDist = 1.0;
    for (int z = -1; z <= 1; ++z) {
        for (int y = -1; y <= 1; ++y) {
            for (int x = -1; x <= 1; ++x) {
                vec3 g = vec3(float(x), float(y), float(z));
                vec3 o = hash33(id + g);
                vec3 diff = g + o - fd;
                minDist = min(minDist, dot(diff, diff));
            }
        }
    }
    return clamp(sqrt(minDist), 0.0, 1.0);
}

// Perlin-Worley 3D synthesis: combines FBM macro density with Worley cellular erosion
// to create the iconic billowy cauliflower shapes of Cumulus and Cumulonimbus clouds
float perlinWorley3D(vec3 p, float cutoff) {
    float perlin = fbm3D_Fast(p, cutoff);
    // Remap active cloud density range [0.22, 0.67] to [0, 1] (slope = 1.0 / (0.67 - 0.22) = 2.22)
    float vNorm = saturate((perlin - 0.22) * 2.22);
    // Invert cellular Worley distance to carve convex billow crowns
    float worley = 1.0 - worley3D_Fast(p * 2.4 + vec3(0.5, 0.2, 0.8));
    // Affine combination: 0.68 * vNorm + 0.52 * worley - 0.20 strictly sums to 1.00 at peak
    float pw = saturate(vNorm * 0.68 + worley * 0.52 - 0.20);
    return pw;
}

// WMO Genera Pattern: Cirrocumulus (Cc - Mây ti tích chuẩn WMO Cloud Atlas)
// Mô phỏng chuẩn ảnh chụp thực tế: các luống sóng dập dềnh (undulatus)
// kết hợp búp mây đối lưu Worley tơi xốp, bị xói mòn bởi nhiễu fractal băng tuyết,
// và hòa tan mềm mại về phía chân trời không bị méo/moiré.
float cirrocumulusRipples2D(vec2 p, float rayDirY) {
    // 1. Chuyển hệ trục theo hướng luồng gió tầng cao
    const float cosW = 0.95;
    const float sinW = 0.31;
    
    // Gió uốn lượn phi tuyến (Turbulent wind shear domain warp)
    vec2 warp = vec2(
        fbm2D(p * 2.0 + vec2(1.4, 5.2)),
        fbm2D(p * 2.0 + vec2(8.1, 2.7))
    ) * 0.12;
    vec2 wp = p + warp;
    
    float wpWind = wp.x * cosW + wp.y * sinW;
    float wpPerp = -wp.x * sinW + wp.y * cosW;

    // 2. Chống moiré / suy giảm tần số cao gần chân trời (Horizon distance anti-aliasing)
    float nyquistFade = clamp((rayDirY - 0.08) / 0.22, 0.0, 1.0);

    // 3. Sóng trọng lực khí quyển (Undulatus wave rolls)
    float wavePhase = wpPerp * 65.0 + fbm2D(wp * 3.5) * 2.5;
    float waveRolls = sin(wavePhase) * 0.5 + 0.5;
    waveRolls = mix(0.5, waveRolls, nyquistFade);

    // 4. Búp mây đối lưu Worley (Continuous cellular Worley billows)
    // Anisotropic aspect ratio (35.2 vs 32.0) models wind-stretched cirrocumulus cloudlets
    vec2 cellUV = vec2(wpWind * 35.2, wpPerp * 32.0);
    float minD = voronoi2D(cellUV);
    // Cell contraction scale 1.35 concentrates density into rounded compact billows
    float worleyBillow = clamp(1.0 - minD * 1.35, 0.0, 1.0);
    worleyBillow = mix(0.4, worleyBillow, nyquistFade);

    // 5. Xói mòn sợi băng fractal (Multi-octave FBM erosion)
    float fbmCarve = fbm2D(wp * 40.0);
    float fineIce = gradientNoise2D(wp * 90.0) * 0.18;
    float fbmDetail = mix(0.2, fbmCarve * 0.65 + fineIce, nyquistFade);

    // Tổng hợp: Búp mây tụ dọc theo các luống sóng và bị xé sợi
    float cloudConvection = worleyBillow * 0.60 + waveRolls * 0.40;
    // 0.32 threshold transition width produces sharp yet anti-aliased cloud boundaries
    float density = clamp((cloudConvection * 1.25 - fbmDetail - 0.12) / 0.32, 0.0, 1.0);
    density = density * density * (3.0 - 2.0 * density);

    // 6. Màn mây vĩ mô (Broad Stratiformis sheet)
    float sheetNoise = fbm2D(p * 0.75 + vec2(2.1, 4.5));
    float sheetMask = clamp((sheetNoise - 0.24) / 0.32, 0.0, 1.0);
    sheetMask = sheetMask * sheetMask * (3.0 - 2.0 * sheetMask);

    // 7. Chân trời quang đãng: mây ti tích tiêu tán dần về phía chân trời theo mẫu ảnh thực tế
    float horizonFade = clamp((rayDirY - 0.18) / 0.25, 0.0, 1.0);
    horizonFade = horizonFade * horizonFade * (3.0 - 2.0 * horizonFade);
    sheetMask *= horizonFade;

    return clamp(density * sheetMask * 1.6, 0.0, 1.0);
}

// WMO Genera Pattern: Cirrus (Ci - Mây ti sợi lông vũ hữu cơ vắt ngang vòm trời)
// Khắc phục triệt để lỗi sọc xước / răng cưa bằng nhiễu ridged fractal uốn xoáy phi tuyến
float cirrusFilament2D(vec2 p, vec2 windDir) {
    vec2 perp = vec2(-windDir.y, windDir.x);
    // Uốn cong sợi mây theo trường xoáy gió quyển tầng cao (Curl-domain warp)
    vec2 warp = vec2(
        fbm2D(p * 1.8 + vec2(3.1, 7.4)),
        fbm2D(p * 1.8 + vec2(5.8, 2.3))
    ) * 0.35;
    vec2 wp = p + warp;

    float wLong = dot(wp, windDir);
    float wCross = dot(wp, perp);
    vec2 streamUV = vec2(wLong * 0.65, wCross * 1.8);

    // Dải sợi băng mảnh mai (Ridged ice fallstreaks / virga)
    float fiber1 = 1.0 - abs(fbm2D(streamUV * 2.2) * 2.0 - 1.0);
    float fiber2 = 1.0 - abs(fbm2D(streamUV * 4.5 + vec2(fiber1 * 0.5, 0.0)) * 2.0 - 1.0);

    // Mảng mây ti hữu cơ phân bố tự nhiên trên vòm trời (không phủ kín toàn bộ)
    float mask = saturate((fbm2D(p * 0.85 + vec2(1.2, 4.7)) - 0.28) / 0.42);
    mask = mask * mask * (3.0 - 2.0 * mask);

    float cirrus = saturate(fiber1 * 0.65 + fiber2 * 0.45) * mask;
    return cirrus;
}

// WMO Genera Pattern: Altocumulus (Ac - Mây trung tích đàn cừu trôi tầng trung)
// Mid-tropospheric (2,000 - 6,000m) stratiformis/perlucidus convective rolls ("mackerel sky" / sheep-herd)
// Modulates two cellular Voronoi harmonics with transverse atmospheric gravity wave oscillations
float altocumulusRolls2D(vec2 p) {
    // Macro and meso cellular cloudlet distributions
    float v1 = 1.0 - voronoi2D(p * 3.8);
    float v2 = 1.0 - voronoi2D(p * 7.5);
    // Transverse undulatus gravity wave oscillation coupled to cloudlet cores
    float wave = sin(p.x * 10.0 + p.y * 5.0 + v1 * 2.5) * 0.5 + 0.5;
    // Energy-conserving weighting (0.55 + 0.25 + 0.20 = 1.00)
    return saturate(v1 * 0.55 + v2 * 0.25 + wave * 0.20);
}

// --- 4. MOMENTS IN GRAPHICS (CHRISTOPH PETERS) BLUE NOISE & DITHERING ---

// Converts uniform [0, 1] noise into a symmetric triangular distribution on [-1, 1] (TPDF)
// with maximum probability density at 0, per Christoph Peters (Moments in Graphics)
vec3 toTriangularPDF(vec3 u) {
    u = u * 2.0 - 1.0;
    return sign(u) * (vec3(1.0) - sqrt(max(vec3(0.0), vec3(1.0) - abs(u))));
}

// Procedural high-frequency Blue Noise approximation (Interleaved Gradient Noise)
// Provides blue-noise spectral properties without memory lookups
float blueNoiseIGN(vec2 screenPos, float frameCount) {
    vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(screenPos + frameCount * vec2(47.0, 17.0), magic.xy)));
}

// Raymarching jitter generator:
// Replaces white noise jitter with Moments in Graphics Blue Noise to completely remove slice banding
float getRaymarchJitter(vec2 screenPos, float frameTime) {
    return blueNoiseIGN(screenPos, mod(frameTime * 60.0, 64.0));
}

// Blue Noise TPDF Dithering for post-processing:
// Converts uniform IGN samples to Christoph Peters' triangular distribution (TPDF on [-1, 1])
// and applies quantization dither to eliminate color banding (parametrized by quantization steps)
vec3 applyBlueNoiseDither(vec3 colorSRGB, vec2 screenPos, float frameCount, float quantSteps) {
    vec3 bn = vec3(
        blueNoiseIGN(screenPos, frameCount),
        blueNoiseIGN(screenPos + vec2(13.1, 7.3), frameCount),
        blueNoiseIGN(screenPos + vec2(29.7, 19.5), frameCount)
    );
    vec3 tpdf = toTriangularPDF(bn);
    return clamp(colorSRGB + tpdf / quantSteps, 0.0, 1.0);
}

// 8-bit default overload for final framebuffer quantization (255.0 steps)
vec3 applyBlueNoiseDither(vec3 colorSRGB, vec2 screenPos, float frameCount) {
    return applyBlueNoiseDither(colorSRGB, screenPos, frameCount, 255.0);
}

#endif // NOISE_GLSL
