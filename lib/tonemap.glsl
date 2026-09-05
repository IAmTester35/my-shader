#ifndef TONEMAP_GLSL
#define TONEMAP_GLSL

#include "settings.glsl"
#include "common.glsl"
#include "noise.glsl"

/*
 * ==============================================================================
 *  POST-PROCESSING, COLOR GRADING & ACES TONEMAPPING
 * ==============================================================================
 */

// ACES Filmic Tone Mapping curve (Krzysztof Narkowicz approximation)
vec3 toneMapACES(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Adjust color saturation
vec3 adjustSaturation(vec3 color, float sat) {
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    return mix(vec3(luma), color, sat);
}

// Cinematic vignette effect
vec3 applyVignette(vec3 color, vec2 uv) {
    #ifdef VIGNETTE
    vec2 coord = (uv - 0.5) * vec2(1.0, 0.85);
    float dist = dot(coord, coord);
    float vig = 1.0 - smoothstep(0.25, 0.8, dist * (1.0 + VIGNETTE_STRENGTH * 2.0));
    return color * vig;
    #else
    return color;
    #endif
}

// Full post-processing pass pipeline
vec3 applyPostProcessing(vec3 hdrColor, vec2 uv) {
    // 1. Exposure adjustment
    vec3 color = hdrColor * EXPOSURE;

    // 2. Linear HDR color grading & saturation (preserves highlight roll-off without gamut clipping)
    color = adjustSaturation(color, SATURATION);

    // 3. Tonemapping (ACES Filmic with natural desaturating highlight rolloff)
    #ifdef TONEMAP_ACES
    color = toneMapACES(color);
    #else
    // Reinhard fallback
    color = color / (color + vec3(1.0));
    #endif

    // 4. Subtle gamma correction (linear to sRGB)
    color = pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));

    // 5. Vignette
    color = applyVignette(color, uv);

    // 6. Moments in Graphics Blue Noise TPDF Dithering (Christoph Peters)
    // Eliminates 8-bit quantization banding on sky gradients and volumetric atmosphere
    color = applyBlueNoiseDither(color, gl_FragCoord.xy, 0.0);

    return color;
}

#endif // TONEMAP_GLSL
