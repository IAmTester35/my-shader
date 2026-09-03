#ifndef BIOME_GLSL
#define BIOME_GLSL

#include "settings.glsl"
#include "common.glsl"

/*
 * ==============================================================================
 *  SMOOTH BIOME AWARENESS & CLIMATE TRANSITIONS (OptiFine / Iris)
 *  Smoothly blends sky scattering, clouds, celestials, and weather across biome borders
 *  using Minecraft's continuously interpolated fogColor (Biome Blend)
 * ==============================================================================
 */

// OptiFine / Iris Biome Category Constants
#define CAT_NONE          0
#define CAT_TAIGA         1
#define CAT_EXTREME_HILLS 2
#define CAT_JUNGLE        3
#define CAT_MESA          4
#define CAT_PLAINS        5
#define CAT_SAVANNA       6
#define CAT_ICY           7
#define CAT_THE_END       8
#define CAT_BEACH         9
#define CAT_FOREST       10
#define CAT_OCEAN        11
#define CAT_DESERT       12
#define CAT_RIVER        13
#define CAT_SWAMP        14
#define CAT_MUSHROOM     15
#define CAT_NETHER       16

struct BiomeAtmosphere {
    vec3  skyTint;           // Multiplier for Rayleigh/Mie sky scattering
    vec3  fogTint;           // Horizon and mist color modulation
    float hazeDensity;       // Aerosol / dust / humidity level
    float cloudCoverage;     // Biome cloud formation modifier
    float auroraStrength;    // Polar northern lights visibility
    float sandstormFactor;   // Dust storm during rain in arid biomes
    bool  isCold;            // Frozen ocean, snowy plains, taiga
    bool  isArid;            // Desert, badlands, savanna
    bool  isHumid;           // Jungle, swamp
};

// Smooth linear interpolation between two BiomeAtmosphere states
BiomeAtmosphere mixBiomeAtmosphere(BiomeAtmosphere a, BiomeAtmosphere b, float t) {
    BiomeAtmosphere res;
    float weight = clamp(t, 0.0, 1.0);

    res.skyTint         = mix(a.skyTint, b.skyTint, weight);
    res.fogTint         = mix(a.fogTint, b.fogTint, weight);
    res.hazeDensity     = mix(a.hazeDensity, b.hazeDensity, weight);
    res.cloudCoverage   = mix(a.cloudCoverage, b.cloudCoverage, weight);
    res.auroraStrength  = mix(a.auroraStrength, b.auroraStrength, weight);
    res.sandstormFactor = mix(a.sandstormFactor, b.sandstormFactor, weight);
    res.isCold          = (weight > 0.5) ? b.isCold : a.isCold;
    res.isArid          = (weight > 0.5) ? b.isArid : a.isArid;
    res.isHumid         = (weight > 0.5) ? b.isHumid : a.isHumid;

    return res;
}

// Generate default temperate baseline atmosphere (Plains, Forest, Ocean)
BiomeAtmosphere getDefaultAtmosphere() {
    BiomeAtmosphere b;
    b.skyTint         = vec3(1.0);
    b.fogTint         = vec3(1.0);
    b.hazeDensity     = 1.0;
    b.cloudCoverage   = 1.0;
    b.auroraStrength  = 0.0;
    b.sandstormFactor = 0.0;
    b.isCold          = false;
    b.isArid          = false;
    b.isHumid         = false;
    return b;
}

// Evaluate target climate parameters for a specific biome category
BiomeAtmosphere getTargetBiomeAtmosphere(int biomeCat, int biomeId) {
    BiomeAtmosphere b = getDefaultAtmosphere();

    // Desert (12) & Badlands / Mesa (4)
    if (biomeCat == CAT_DESERT || biomeCat == CAT_MESA) {
        b.isArid = true;
        b.cloudCoverage = 0.35;
        b.hazeDensity = 1.6;
        b.auroraStrength = 0.0;
        b.sandstormFactor = 1.0;
        if (biomeCat == CAT_MESA) {
            b.skyTint = vec3(1.05, 0.95, 0.90);
            b.fogTint = vec3(1.15, 0.85, 0.72);
        } else {
            b.skyTint = vec3(1.02, 1.00, 0.92);
            b.fogTint = vec3(1.12, 1.04, 0.88);
        }
    }
    // Icy (7) & Taiga (1)
    else if (biomeCat == CAT_ICY || biomeCat == CAT_TAIGA) {
        b.isCold = true;
        b.hazeDensity = 0.65;
        b.auroraStrength = 1.8;
        b.cloudCoverage = (biomeCat == CAT_ICY) ? 0.75 : 1.15;
        b.skyTint = vec3(0.92, 0.97, 1.08);
        b.fogTint = vec3(0.88, 0.94, 1.05);
    }
    // Jungle (3) & Swamp (14)
    else if (biomeCat == CAT_JUNGLE || biomeCat == CAT_SWAMP) {
        b.isHumid = true;
        b.hazeDensity = 1.7;
        b.cloudCoverage = 1.4;
        b.auroraStrength = 0.0;
        if (biomeCat == CAT_SWAMP) {
            b.skyTint = vec3(0.92, 0.96, 0.88);
            b.fogTint = vec3(0.85, 0.92, 0.80);
        } else {
            b.skyTint = vec3(0.96, 1.00, 0.98);
            b.fogTint = vec3(0.94, 1.02, 0.95);
        }
    }
    // Mountains / Extreme Hills (2)
    else if (biomeCat == CAT_EXTREME_HILLS) {
        b.hazeDensity = 0.75;
        b.cloudCoverage = 1.1;
        b.auroraStrength = 0.85;
        b.skyTint = vec3(0.95, 0.98, 1.04);
        b.fogTint = vec3(0.92, 0.95, 1.02);
    }
    // Savanna (6)
    else if (biomeCat == CAT_SAVANNA) {
        b.isArid = true;
        b.cloudCoverage = 0.60;
        b.hazeDensity = 1.25;
        b.skyTint = vec3(1.02, 0.98, 0.94);
        b.fogTint = vec3(1.08, 0.98, 0.86);
    }

    return b;
}

// Master Function: Computes a smoothly interpolated BiomeAtmosphere across chunk borders
// Uses Minecraft's continuous vanilla fogColor (smoothly blended over 3x3 to 15x15 blocks)
BiomeAtmosphere getSmoothBiomeAtmosphere(int biomeCat, int biomeId, vec3 fogCol) {
    BiomeAtmosphere baseAtm = getDefaultAtmosphere();

    #ifndef BIOME_ADAPTATION
    return baseAtm;
    #endif

    BiomeAtmosphere targetAtm = getTargetBiomeAtmosphere(biomeCat, biomeId);

    // Normalize chromaticity of Minecraft's vanilla fogColor
    float maxLuma = max(max(fogCol.r, fogCol.g), max(fogCol.b, 0.001));
    vec3 normFog = fogCol / maxLuma;

    float transitionWeight = 1.0;

    // Detect climate transition blend weights using continuous chromatic gradient
    if (targetAtm.isArid) {
        // Desert/Mesa: Red chromaticity is significantly higher than Blue
        float warmth = normFog.r - normFog.b;
        transitionWeight = smoothstep(0.01, 0.20, warmth);
    } else if (targetAtm.isCold) {
        // Cold/Icy: Blue chromaticity is elevated relative to Red
        float coldness = normFog.b - normFog.r * 0.95;
        transitionWeight = smoothstep(-0.06, 0.12, coldness);
    } else if (targetAtm.isHumid) {
        // Jungle/Swamp: Green chromaticity is elevated relative to Blue
        float greenness = normFog.g - normFog.b;
        transitionWeight = smoothstep(-0.02, 0.15, greenness);
    } else if (targetAtm.auroraStrength > 0.0) {
        // Mountains
        float elevation = normFog.b - normFog.r * 0.92;
        transitionWeight = smoothstep(-0.04, 0.14, elevation);
    }

    // Smoothly blend between temperate baseline and specific biome target
    return mixBiomeAtmosphere(baseAtm, targetAtm, transitionWeight);
}

#endif // BIOME_GLSL
