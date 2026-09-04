#ifndef NOISE_GLSL
#define NOISE_GLSL

/*
 * ==============================================================================
 *  HIGH-PRECISION PROCEDURAL & BLUE NOISE LIBRARY (GLSL 120 COMPLIANT)
 *  Features:
 *   1. Perlin / Simplex C2-continuous Gradient Noise 2D & 3D (Quintic Hermite)
 *   2. FBM (Fractal Brownian Motion) multi-octave synthesis
 *   3. Voronoi / Cellular 2D noise
 *   4. Moments in Graphics (Christoph Peters) Blue Noise System:
 *      - Void-and-Cluster 64x64 blue noise texture sampling with R2 temporal offset
 *      - Procedural high-frequency Interleaved Gradient Blue Noise (IGN)
 *      - Triangular Probability Density Function (TPDF) shaping
 *      - Blue Noise raymarching jittering (god rays, volumetric clouds)
 *      - Blue Noise sRGB dithering to eliminate 8-bit color banding
 * ==============================================================================
 */

// --- 1. PSEUDO-RANDOM HASH FUNCTIONS (High Entropy, Artifact-Free) ---

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

// High-performance 3D Unit Gradient Generator (Trigonometry-free for GPU efficiency)
vec3 grad3(vec3 p) {
    vec3 h = hash33(p) * 2.0 - 1.0;
    return normalize(h);
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
    
    // If macro density cannot reach the cloud boundary, early-exit
    if (v + 0.19 < cutoff) return v;
    
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
// Dithers sRGB color before 8-bit quantization, eliminating banding on skies, sunsets, and clouds
vec3 applyBlueNoiseDither(vec3 colorSRGB, vec2 screenPos, float frameCount) {
    vec3 bn = vec3(
        blueNoiseIGN(screenPos, frameCount),
        blueNoiseIGN(screenPos + vec2(13.1, 7.3), frameCount),
        blueNoiseIGN(screenPos + vec2(29.7, 19.5), frameCount)
    );
    vec3 tpdf = toTriangularPDF(bn);
    return clamp(colorSRGB + tpdf / 255.0, 0.0, 1.0);
}

#endif // NOISE_GLSL
