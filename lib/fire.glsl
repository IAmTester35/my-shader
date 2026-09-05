#ifndef FIRE_GLSL
#define FIRE_GLSL

#include "settings.glsl"
#include "common.glsl"
#include "noise.glsl"

/*
 * ==============================================================================
 *  THERMODYNAMIC FIRE & IONIZATION PLASMA SYSTEM (Cinematic Optics Edition)
 *  - ACES-Calibrated Filmic Blackbody Radiance (1000K - 2200K equivalent curve)
 *  - Stylized Ionization Radical Plasma for Soul Fire (CH / C2 Swan Band Spectral Analogue)
 *  - Multi-Octave Buoyant Thermal Convection & Flame Tongue Licking
 *  - Micro-Ember Detachment & Upward Drafting Cellular Spark Field
 *  - Cinematic Peripheral Screen Fire Vignette (Clear center, licking edge flames)
 *  - Full HDR Optical Integration for ACES Filmic Tonemapping
 * ==============================================================================
 */

// ------------------------------------------------------------------------------
// 1. Spectral Emission & Color Palettes (SSOC)
// ------------------------------------------------------------------------------

// Unified 3-tier spectral color ramp generator for combustion and ionized plasma.
// Evaluates outer cooling fringe, intermediate reaction zone, and incandescent core.
vec3 sampleFlameSpectralRamp(
    float t,
    vec3 colEdge,
    vec3 colBody,
    vec3 colCore,
    vec2 edgeBand,
    vec2 bodyBand,
    vec2 coreBand,
    float edgeDamping,
    float coreHdrMultiplier
) {
    float edge = smoothstep(edgeBand.x, edgeBand.y, t);
    float body = smoothstep(bodyBand.x, bodyBand.y, t);
    float core = smoothstep(coreBand.x, coreBand.y, t);

    vec3 color = mix(colEdge * edgeDamping, colBody, body);
    color = mix(color, colCore, core);

    if (coreHdrMultiplier > 0.0) {
        // Quadratic HDR radiance boost in peak reaction zone
        color += colCore * (core * core * coreHdrMultiplier);
    }

    return color * edge;
}

// Planckian Blackbody emission gradient for normal hydrocarbon/wood fire
// Note: While natural open woodfires peak around 1000K - 1400K, this curve is
// artistically extended to an incandescent 2200K equivalent core to force ACES
// filmic tonemapping to roll over saturated yellows into natural desaturated white highlights.
vec3 getBlackbodyFlameColor(float t) {
    // Outer cooling soot fringe (1000K - 1200K): Deep smoldering crimson
    const vec3 COL_EDGE = vec3(0.85, 0.12, 0.02);
    // Intermediate combustion zone (1400K - 1700K): Saturated amber-orange
    const vec3 COL_BODY = vec3(1.20, 0.55, 0.08);
    // Incandescent inner reaction core (>2000K graded): Brilliant white-yellow HDR highlight
    const vec3 COL_CORE = vec3(2.40, 2.10, 1.40);

    #ifdef FIRE_BLACKBODY_CORE
    float hdrMultiplier = 1.8;
    #else
    float hdrMultiplier = 0.0;
    #endif

    return sampleFlameSpectralRamp(
        t,
        COL_EDGE,
        COL_BODY,
        COL_CORE,
        vec2(0.02, 0.35),
        vec2(0.20, 0.70),
        vec2(0.60, 0.95),
        0.70,
        hdrMultiplier
    );
}

// Ionization spectral emission for Soul Fire
// Stylized fantasy plasma palette inspired by high-excitation radical emission bands:
// methylidyne CH (431 nm indigo) and diatomic carbon C2 Swan bands (470-516 nm cyan/turquoise).
vec3 getSoulFirePlasmaColor(float t) {
    // Outer corona: Deep indigo/ultramarine boundary
    const vec3 COL_EDGE = vec3(0.04, 0.22, 0.65);
    // Intermediate plasma: Vibrant spectral cyan/turquoise
    const vec3 COL_BODY = vec3(0.10, 0.82, 1.15);
    // Inner ionized core: Incandescent electric violet-white HDR
    const vec3 COL_CORE = vec3(1.30, 2.10, 2.80);

    return sampleFlameSpectralRamp(
        t,
        COL_EDGE,
        COL_BODY,
        COL_CORE,
        vec2(0.02, 0.30),
        vec2(0.18, 0.65),
        vec2(0.55, 0.92),
        0.80,
        2.0
    );
}

// ------------------------------------------------------------------------------
// 2. Procedural Buoyant Thermal Convection (Flame Licks & Tongues)
// ------------------------------------------------------------------------------

// Evaluates procedural fluid flame dynamics on local billboard/block quad coordinates
// uv: Local quad texture coordinates [0..1] (v=0 base, v=1 flame tip)
// timeSec: Global animation time
// seed: Random offset per block or surface
float calculateFlameTongueDynamics(vec2 uv, float timeSec, float seed) {
    // Upward convective buoyancy speed
    const float FLAME_BUOYANCY_SPEED = 4.2;
    float t = timeSec * FLAME_BUOYANCY_SPEED;

    #ifdef FIRE_TURBULENCE
    // 1st Octave: Primary buoyant convective vortices (ascent speed: 1.0 * t)
    vec2 p1 = vec2(uv.x * 3.2 + seed * 17.3, uv.y * 2.4 - t);
    float n1 = gradientNoise2D(p1);

    // 2nd Octave: High-frequency swirling eddies & turbulent shear (ascent speed: 1.6 * t)
    vec2 p2 = vec2(uv.x * 6.5 - seed * 9.1, uv.y * 5.0 - t * 1.6);
    float n2 = gradientNoise2D(p2);

    // 3rd Octave: Micro-flicker with transverse cross-flow shear (horizontal drift: +0.8 * t, vertical ascent: 2.4 * t)
    vec2 p3 = vec2(uv.x * 12.0 + t * 0.8, uv.y * 10.0 - t * 2.4);
    float n3 = gradientNoise2D(p3);

    // Strict partition-of-unity turbulence combination (0.55 + 0.30 + 0.15 = 1.00)
    const vec3 HARMONIC_WEIGHTS = vec3(0.55, 0.30, 0.15);
    float turbulence = n1 * HARMONIC_WEIGHTS.x + n2 * HARMONIC_WEIGHTS.y + n3 * HARMONIC_WEIGHTS.z;
    #else
    float turbulence = 0.5;
    #endif

    // Conical flame envelope: Thicker at base (v=0), tapering to sharp tip (v=1)
    float horizontalDist = abs(uv.x - 0.5) * 2.0;
    float verticalTaper = 1.0 - uv.y * 0.85;

    // Lateral tongue distortion caused by thermal eddies
    float tongueShear = (turbulence - 0.5) * (0.35 + uv.y * 0.55);
    float shapedDist = horizontalDist + tongueShear;

    // Base flame profile
    float flameMask = 1.0 - smoothstep(verticalTaper * 0.3, verticalTaper * 1.1, shapedDist);

    // Tip detachment & intermittent flame licking
    float tipDissolve = smoothstep(0.85, 0.30, uv.y + (turbulence - 0.5) * 0.45);
    flameMask *= tipDissolve;

    return clamp(flameMask * (0.6 + turbulence * 0.8), 0.0, 1.0);
}

// ------------------------------------------------------------------------------
// 3. Cellular Spark Field & Micro-Ember Detachment (SSOC)
// ------------------------------------------------------------------------------

// Unified 3x3 cellular spark field evaluator
// Evaluates point-like incandescent sparks with sinuous buoyancy oscillations and temporal twinkling
float evaluateCellularSparkField(
    vec2 gridCoord,
    vec2 seedOffset,
    float oscTime,
    float oscAmp,
    float baseRadius,
    float radiusVariation,
    float timeSec,
    float twinkleFreq
) {
    vec2 cell = floor(gridCoord);
    vec2 fractCoord = fract(gridCoord);
    float spark = 0.0;

    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            vec2 offset = vec2(float(dx), float(dy));
            vec2 c = cell + offset;
            vec2 pos = hash22(c + seedOffset);

            // Sinuous horizontal oscillation from ascending vortex shedding
            pos.x += sin(oscTime + pos.y * 6.2831853) * oscAmp;

            vec2 delta = fractCoord - (offset + pos);
            float dist = length(delta);

            float radius = baseRadius;
            if (radiusVariation > 0.0) {
                radius += hash21(c) * radiusVariation;
            }

            if (dist < radius) {
                float twinkle = 0.5 + 0.5 * sin(timeSec * twinkleFreq + hash21(c + 9.2) * 6.2831853);
                float intensity = (1.0 - dist / radius) * twinkle;
                spark = max(spark, intensity);
            }
        }
    }

    return spark;
}

// Evaluates tiny glowing sparks breaking away from the flame and drifting upward
float calculateFloatingEmbers(vec2 uv, float timeSec, float seed) {
    #ifndef FIRE_EMBERS
    return 0.0;
    #endif

    const float EMBER_SPEED = 2.8;
    float t = timeSec * EMBER_SPEED;

    // Upward drafting particle coordinate grid
    vec2 emberCoord = vec2(uv.x * 8.0 + seed * 31.7, uv.y * 4.0 - t);
    float spark = evaluateCellularSparkField(
        emberCoord,
        vec2(seed, 4.13),
        t * 2.5,
        0.25,
        0.08,
        0.06,
        timeSec,
        15.0
    );

    // Detached sparks concentrate primarily above the combustion zone
    float heightFactor = smoothstep(0.25, 0.95, uv.y);
    return spark * heightFactor;
}

// ------------------------------------------------------------------------------
// 4. World Block Fire Master Shading (Terrain & Campfires)
// ------------------------------------------------------------------------------

// Ratio between procedural noise dynamics (65%) and vanilla sprite luminance (35%)
// Retains vanilla block silhouette while driving organic convection
const float FIRE_PROCEDURAL_BLEND = 0.65;

// Contrast expansion factor for combustion dynamic range
const float FIRE_CONTRAST_EXPANSION = 1.30;

// Shading function for world block fire in gbuffers_terrain
// baseTex: Sampled vanilla texture (used for quad coordinates & sprite boundary)
// uv: Texture coordinates
// worldCoord: World space coordinate of the block
// timeSec: Animation time
// isSoulFire: True if soul fire / soul campfire
vec4 shadeBlockFire(vec4 baseTex, vec2 uv, vec3 worldCoord, float timeSec, bool isSoulFire) {
    #ifndef CINEMATIC_FIRE
    return baseTex;
    #endif

    // Derive procedural seed from block world position
    float seed = hash21(floor(worldCoord.xz) + floor(worldCoord.y) * 31.0);

    // Local quad UV within the 16x16 sprite tile
    vec2 localUV = fract(uv);

    // Evaluate procedural thermal plume
    float flameDensity = calculateFlameTongueDynamics(localUV, timeSec, seed);

    // Blend procedural dynamics with base sprite structure to preserve block geometry
    float combinedIntensity = mix(baseTex.r, flameDensity, FIRE_PROCEDURAL_BLEND);
    combinedIntensity = clamp(combinedIntensity * FIRE_CONTRAST_EXPANSION, 0.0, 1.0);

    // Compute spectral HDR radiance
    vec3 flameHDR;
    if (isSoulFire) {
        #ifdef SOUL_FIRE_SPECTRAL
        flameHDR = getSoulFirePlasmaColor(combinedIntensity);
        #else
        flameHDR = getBlackbodyFlameColor(combinedIntensity);
        #endif
    } else {
        flameHDR = getBlackbodyFlameColor(combinedIntensity);
    }

    // Add incandescent micro-embers
    float embers = calculateFloatingEmbers(localUV, timeSec, seed);
    if (embers > 0.01) {
        const vec3 SOUL_EMBER_COLOR = vec3(0.4, 1.6, 2.5);
        const vec3 BLACKBODY_EMBER_COLOR = vec3(3.0, 1.8, 0.6);
        vec3 emberColor = isSoulFire ? SOUL_EMBER_COLOR : BLACKBODY_EMBER_COLOR;
        flameHDR += emberColor * embers * 3.5;
    }

    float finalAlpha = clamp(flameDensity * 1.2 + embers, 0.0, 1.0);
    finalAlpha = max(finalAlpha, baseTex.a * 0.85);

    return vec4(flameHDR, finalAlpha);
}

// ------------------------------------------------------------------------------
// 5. Cinematic Peripheral Screen Fire Overlay (Camera Burn Effect)
// ------------------------------------------------------------------------------

// Screen vignette clear-zone geometry:
// Center offset (0.50, 0.42) shifts unobstructed opening downward to clear first-person crosshair
const vec2 SCREEN_FIRE_FOCUS_CENTER = vec2(0.50, 0.42);
// Anisotropic scaling factors stretched vertically for 16:9 widescreen viewports
const vec2 SCREEN_FIRE_RADIAL_SCALE = vec2(1.15, 1.45);
// Inner and outer clear-zone transition boundaries
const vec2 SCREEN_FIRE_CLEAR_RANGE = vec2(0.35, 0.72);

// Renders an immersive, non-obtrusive peripheral flame vignette when the player is on fire
// uv: Normalized screen-space coordinates [0..1]
// timeSec: Animation time
vec4 renderScreenFireVignette(vec2 uv, float timeSec) {
    #ifndef CINEMATIC_SCREEN_FIRE
    return vec4(0.0);
    #endif

    // 1. Center Clear Zone: Elliptical mask ensuring unobstructed center crosshair vision
    vec2 centerOffset = (uv - SCREEN_FIRE_FOCUS_CENTER) * SCREEN_FIRE_RADIAL_SCALE;
    float radialDist = length(centerOffset);
    float centerClearMask = smoothstep(SCREEN_FIRE_CLEAR_RANGE.x, SCREEN_FIRE_CLEAR_RANGE.y, radialDist);

    // Focus fire primarily at bottom edge & corners
    float bottomEdge = 1.0 - uv.y; // 1 at bottom, 0 at top
    float bottomInfluence = smoothstep(0.40, 0.95, bottomEdge);

    // Side edges influence
    float sideDist = abs(uv.x - 0.5) * 2.0;
    float sideInfluence = smoothstep(0.60, 0.98, sideDist) * bottomInfluence;

    float vignetteMask = max(bottomInfluence * 0.9, sideInfluence * 0.75) * centerClearMask;
    if (vignetteMask < 0.01) return vec4(0.0);

    // 2. Animated Convective Edge Flames
    float t = timeSec * 3.6;
    float wave1 = sin(uv.x * 14.0 + t * 1.2) * 0.08;
    float wave2 = cos(uv.x * 24.0 - t * 2.0) * 0.04;
    float noiseTurb = gradientNoise2D(vec2(uv.x * 6.0, bottomEdge * 3.0 - t * 0.8)) * 0.16;

    float flameThreshold = 0.55 + wave1 + wave2 + noiseTurb;
    float flameIntensity = smoothstep(flameThreshold, 1.05, bottomEdge + vignetteMask * 0.4);

    // 3. Blackbody Emission along screen border
    vec3 flameColor = getBlackbodyFlameColor(flameIntensity);

    // 4. Drifting Sparks rising along screen edges (SSOC shared spark evaluator)
    const float SCREEN_SPARK_SPEED = 3.0;
    vec2 sparkUV = vec2(uv.x * 12.0, uv.y * 6.0 - timeSec * SCREEN_SPARK_SPEED);
    float screenSpark = evaluateCellularSparkField(
        sparkUV,
        vec2(7.82, 7.82),
        timeSec * 4.0,
        0.20,
        0.09,
        0.0,
        timeSec,
        20.0
    );

    // Sparks only in peripheral vignette area
    screenSpark *= vignetteMask;
    const vec3 SCREEN_SPARK_TINT = vec3(3.2, 2.0, 0.8);
    flameColor += SCREEN_SPARK_TINT * screenSpark * 4.0;

    float alpha = clamp((flameIntensity * 0.85 + screenSpark * 0.95) * SCREEN_FIRE_OPACITY, 0.0, 1.0);

    return vec4(flameColor, alpha);
}

#endif // FIRE_GLSL

