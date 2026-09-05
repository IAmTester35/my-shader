#ifndef FIRE_GLSL
#define FIRE_GLSL

#include "settings.glsl"
#include "common.glsl"
#include "noise.glsl"

/*
 * ==============================================================================
 *  THERMODYNAMIC FIRE & IONIZATION PLASMA SYSTEM (Cinematic Optics Edition)
 *  - Planckian Blackbody Radiation & Color Temperature Gradient (1000K - 2200K)
 *  - High-Energy Ionization Plasma for Soul Fire (Swan band CH/C2 Radicals)
 *  - Rayleigh-Bénard Buoyant Thermal Convection & Multi-Octave Flame Licks
 *  - Micro-Ember Detachment & Upward Drafting Particle Field
 *  - Cinematic Peripheral Screen Fire Vignette (Clear center, licking edge flames)
 *  - Full HDR Optical Integration for ACES Filmic Tonemapping
 * ==============================================================================
 */

// ------------------------------------------------------------------------------
// 1. Blackbody Thermodynamics & Spectral Emission
// ------------------------------------------------------------------------------

// Analytical Planckian Blackbody emission gradient for normal hydrocarbon/wood fire
// t: Normalized flame intensity [0.0 (outer soot) .. 1.0 (incandescent core)]
vec3 getBlackbodyFlameColor(float t) {
    float core = smoothstep(0.60, 0.95, t);
    float body = smoothstep(0.20, 0.70, t);
    float edge = smoothstep(0.02, 0.35, t);

    // Outer cooling fringe (1000K - 1200K): Deep smoldering crimson/cherry-red
    vec3 colEdge = vec3(0.85, 0.12, 0.02);

    // Intermediate combustion zone (1400K - 1700K): Rich saturated amber-orange
    vec3 colBody = vec3(1.20, 0.55, 0.08);

    // Incandescent inner core (>2000K): Brilliant white-yellow with HDR punch
    vec3 colCore = vec3(2.40, 2.10, 1.40);

    vec3 flame = mix(colEdge * 0.7, colBody, body);
    flame = mix(flame, colCore, core);

    #ifdef FIRE_BLACKBODY_CORE
    // Extra HDR radiance for the hottest reaction zone to bloom naturally through ACES
    flame += colCore * (core * core * 1.8);
    #endif

    return flame * edge;
}

// Analytical Ionization Spectral emission for Soul Fire (Swan Band Emission)
// High-energy radical emissions (4500K - 8000K plasma luminescence)
vec3 getSoulFirePlasmaColor(float t) {
    float core = smoothstep(0.55, 0.92, t);
    float body = smoothstep(0.18, 0.65, t);
    float edge = smoothstep(0.02, 0.30, t);

    // Outer corona: Deep indigo/ultramarine boundary
    vec3 colEdge = vec3(0.04, 0.22, 0.65);

    // Intermediate plasma: Vibrant spectral cyan/turquoise
    vec3 colBody = vec3(0.10, 0.82, 1.15);

    // Inner ionized core: Incandescent electric violet-white HDR
    vec3 colCore = vec3(1.30, 2.10, 2.80);

    vec3 plasma = mix(colEdge * 0.8, colBody, body);
    plasma = mix(plasma, colCore, core);

    plasma += colCore * (core * core * 2.0);

    return plasma * edge;
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
    float upwardSpeed = 4.2;
    float t = timeSec * upwardSpeed;

    #ifdef FIRE_TURBULENCE
    // Upward coordinate scaling (stretched along thermal plume)
    vec2 p = vec2(uv.x * 3.2 + seed * 17.3, uv.y * 2.4 - t);

    // 1st Octave: Primary buoyant convective vortices
    float n1 = gradientNoise2D(p);

    // 2nd Octave: High-frequency swirling eddies & turbulent shear
    vec2 p2 = vec2(uv.x * 6.5 - seed * 9.1, uv.y * 5.0 - t * 1.6);
    float n2 = gradientNoise2D(p2);

    // 3rd Octave: Micro-flicker
    vec2 p3 = vec2(uv.x * 12.0 + t * 0.8, uv.y * 10.0 - t * 2.4);
    float n3 = gradientNoise2D(p3);

    // Combine multi-octave turbulence
    float turbulence = n1 * 0.55 + n2 * 0.30 + n3 * 0.15;
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
// 3. Micro-Ember Detachment & Floating Sparks
// ------------------------------------------------------------------------------

// Evaluates tiny glowing sparks breaking away from the flame and drifting upward
float calculateFloatingEmbers(vec2 uv, float timeSec, float seed) {
    #ifndef FIRE_EMBERS
    return 0.0;
    #endif

    float emberSpeed = 2.8;
    float t = timeSec * emberSpeed;

    vec2 emberCoord = vec2(uv.x * 8.0 + seed * 31.7, uv.y * 4.0 - t);
    vec2 cell = floor(emberCoord);
    vec2 fractCoord = fract(emberCoord);

    float spark = 0.0;

    // Check neighboring grid cells for point sparks
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            vec2 c = cell + vec2(float(dx), float(dy));
            vec2 sparkPos = hash22(c + vec2(seed, 4.13));

            // Sinuous horizontal oscillation as spark rises
            sparkPos.x += sin(t * 2.5 + sparkPos.y * 6.28) * 0.25;

            vec2 delta = fractCoord - (vec2(float(dx), float(dy)) + sparkPos);
            float dist = length(delta);

            // Spark size & temporal twinkling
            float sparkSize = 0.08 + hash21(c) * 0.06;
            float twinkle = 0.5 + 0.5 * sin(timeSec * 15.0 + hash21(c + 9.2) * 6.28);

            // Sparks are more abundant above the flame base
            float heightFactor = smoothstep(0.25, 0.95, uv.y);

            if (dist < sparkSize) {
                float intensity = (1.0 - dist / sparkSize) * twinkle * heightFactor;
                spark = max(spark, intensity);
            }
        }
    }

    return spark;
}

// ------------------------------------------------------------------------------
// 4. World Block Fire Master Shading (Terrain & Campfires)
// ------------------------------------------------------------------------------

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
    float combinedIntensity = mix(baseTex.r, flameDensity, 0.65);
    combinedIntensity = clamp(combinedIntensity * 1.3, 0.0, 1.0);

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
        vec3 emberColor = isSoulFire ? vec3(0.4, 1.6, 2.5) : vec3(3.0, 1.8, 0.6);
        flameHDR += emberColor * embers * 3.5;
    }

    float finalAlpha = clamp(flameDensity * 1.2 + embers, 0.0, 1.0);
    finalAlpha = max(finalAlpha, baseTex.a * 0.85);

    return vec4(flameHDR, finalAlpha);
}

// ------------------------------------------------------------------------------
// 5. Cinematic Peripheral Screen Fire Overlay (Camera Burn Effect)
// ------------------------------------------------------------------------------

// Renders an immersive, non-obtrusive peripheral flame vignette when the player is on fire
// uv: Normalized screen-space coordinates [0..1]
// timeSec: Animation time
vec4 renderScreenFireVignette(vec2 uv, float timeSec) {
    #ifndef CINEMATIC_SCREEN_FIRE
    return vec4(0.0);
    #endif

    // 1. Center Clear Zone: Elliptical mask ensuring unobstructed center vision
    vec2 centerOffset = (uv - vec2(0.5, 0.42)) * vec2(1.15, 1.45);
    float radialDist = length(centerOffset);
    float centerClearMask = smoothstep(0.35, 0.72, radialDist);

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

    // 4. Drifting Sparks rising along screen edges
    vec2 sparkUV = vec2(uv.x * 12.0, uv.y * 6.0 - timeSec * 3.0);
    vec2 sparkCell = floor(sparkUV);
    vec2 sparkFract = fract(sparkUV);

    float screenSpark = 0.0;
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            vec2 c = sparkCell + vec2(float(dx), float(dy));
            vec2 pos = hash22(c + 7.82);
            pos.x += sin(timeSec * 4.0 + pos.y * 6.28) * 0.2;

            float d = length(sparkFract - (vec2(float(dx), float(dy)) + pos));
            if (d < 0.09) {
                float tw = 0.5 + 0.5 * sin(timeSec * 20.0 + hash21(c) * 6.28);
                screenSpark = max(screenSpark, (1.0 - d / 0.09) * tw);
            }
        }
    }

    // Sparks only in peripheral vignette area
    screenSpark *= vignetteMask;
    flameColor += vec3(3.2, 2.0, 0.8) * screenSpark * 4.0;

    float alpha = clamp((flameIntensity * 0.85 + screenSpark * 0.95) * SCREEN_FIRE_OPACITY, 0.0, 1.0);

    return vec4(flameColor, alpha);
}

#endif // FIRE_GLSL
