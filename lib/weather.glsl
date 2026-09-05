#ifndef WEATHER_GLSL
#define WEATHER_GLSL

#include "settings.glsl"
#include "common.glsl"
#include "noise.glsl"
#include "biome.glsl"
#include "lightning.glsl"

/*
 * ==============================================================================
 *  DYNAMIC WEATHER & PRECIPITATION SYSTEM (BIOME-AWARE)
 *  - Procedural 6-Fold Dendritic Keplerian Snowflakes (D6h Hexagonal Symmetry)
 *  - Aerodynamic Flutter & Chaotic Turbulence for Falling Snow
 *  - Micro-Facet Specular Scintillation (Diamond Dust Sparkle)
 *  - Aerodynamic Sub-Pixel Needle Raindrop Streaks & Optical Glisten
 *  - Thunderstorm Branching Lightning Flash & Chromatic Dispersion
 *  - Biome-Aware Transitions (Desert Sandstorms & Polar Blizzards)
 * ==============================================================================
 */

// Procedural multi-pulse lightning flash trigger during thunderstorms
float getStormLightningFlash(float rain, float timeSec) {
    LightningStrike s = evaluateLightningState(rain, timeSec);
    return s.intensity;
}

// Directional azimuth (in radians [0..2PI]) of the active lightning strike
float getStormLightningAzimuth(float timeSec) {
    LightningStrike s = evaluateLightningState(1.0, timeSec);
    return s.azimuth;
}

// Atmospheric rain / weather fog density calculation
float calculateRainFogFactor(float distanceToCamera, float rain, BiomeAtmosphere biomeAtm) {
    #ifndef DYNAMIC_WEATHER
    return 0.0;
    #endif

    float baseDensity = 0.0018 * RAIN_FOG_DENSITY * biomeAtm.hazeDensity;
    
    #ifdef DESERT_SANDSTORM
    if (biomeAtm.isArid) {
        // Sandstorm fog is thicker near ground
        float sandDensity = baseDensity * (1.0 + rain * 6.5);
        return 1.0 - exp(-distanceToCamera * sandDensity);
    }
    #endif

    float rainFogDensity = baseDensity * (1.0 + rain * 4.8);
    return 1.0 - exp(-distanceToCamera * rainFogDensity);
}

// Wet surface reflection and darkening
vec3 applyWetnessToAlbedo(vec3 albedo, float wetness, BiomeAtmosphere biomeAtm) {
    #ifndef WETNESS_EFFECT
    return albedo;
    #endif

    // Desert does not accumulate wet puddles
    if (biomeAtm.isArid) return albedo;

    float darkeningFactor = mix(1.0, 0.65, wetness);
    return albedo * darkeningFactor;
}

// ------------------------------------------------------------------------------
// Precipitation Classification (Snow vs Rain)
// ------------------------------------------------------------------------------
bool isPrecipitationSnow(vec4 tex, BiomeAtmosphere biomeAtm) {
    // 1. Biome Climate: Frozen / snowy biomes precipitate snow
    if (biomeAtm.isCold) return true;

    // 2. Texture Chromaticity Analysis:
    // Vanilla rain texture is blue-tinted with low red (tex.b > tex.r + 0.05)
    // Vanilla snow texture is achromatic white (tex.r ≈ tex.g ≈ tex.b > 0.65)
    float rgDiff = abs(tex.r - tex.g);
    float rbDiff = abs(tex.r - tex.b);
    bool isWhiteAchromatic = (tex.r > 0.65 && rgDiff < 0.06 && rbDiff < 0.06);

    return isWhiteAchromatic;
}

// ------------------------------------------------------------------------------
// Procedural 6-Fold Dendritic Hexagonal Snowflake (Keplerian D6h Ice Ih)
// ------------------------------------------------------------------------------
float evaluateDendriticSnowflake(vec2 localUV, float timeSec, vec3 worldPos) {
    #ifndef PROCEDURAL_SNOW
    return 1.0;
    #endif

    vec2 p = localUV - vec2(0.5);
    float scale = max(SNOW_CRYSTAL_SIZE, 0.2);
    float r = length(p) * (2.2 / scale);
    if (r > 1.0) return 0.0;

    float phi = atan(p.y, p.x);

    #ifdef SNOW_FLUTTER
    // Aerodynamic flutter & micro-turbulent tumble
    float seed = hash21(floor(worldPos.xz * 2.0) + floor(worldPos.y));
    float flutter = sin(timeSec * 2.2 + seed * 6.28) * 0.45 + cos(timeSec * 1.1 + seed * 3.14) * 0.25;
    phi += flutter;
    #endif

    // Fold polar angle into 60° (PI/3) hexagonal sector
    const float SECTOR = 3.14159265359 / 3.0;
    const float HALF_SECTOR = SECTOR * 0.5;
    float a = abs(mod(phi + HALF_SECTOR, SECTOR) - HALF_SECTOR);

    // Cartesian coordinates along the folded arm
    vec2 folded = vec2(cos(a), sin(a)) * r;
    float x = folded.x; // Radial distance along primary arm
    float y = folded.y; // Lateral distance from arm spine

    // 1. Central Hexagonal Basal Plate
    float hexPlate = step(x + y * 0.57735, 0.20);

    // 2. Primary 6 Dendritic Spine Arms
    float mainSpine = smoothstep(0.040, 0.015, y) * step(x, 0.88);

    // 3. Secondary Dendritic Side Branches (60° Angle from spine)
    // Branch 1 at x = 0.42
    float dBranch1 = abs(y - (x - 0.42) * 1.73205);
    float b1 = smoothstep(0.030, 0.010, dBranch1) * step(0.42, x) * step(x, 0.68) * step(y, 0.22);

    // Branch 2 at x = 0.62
    float dBranch2 = abs(y - (x - 0.62) * 1.73205);
    float b2 = smoothstep(0.026, 0.008, dBranch2) * step(0.62, x) * step(x, 0.82) * step(y, 0.16);

    // Combine structural components
    float snowflake = max(hexPlate, max(mainSpine, max(b1, b2)));

    // Outer edge softening
    snowflake *= smoothstep(0.98, 0.82, r);

    return snowflake;
}

// ------------------------------------------------------------------------------
// Procedural Aerodynamic Sub-Pixel Needle Raindrop Streaks
// ------------------------------------------------------------------------------
float evaluateRainNeedleStreak(vec2 localUV) {
    #ifndef PROCEDURAL_RAIN
    return 1.0;
    #endif

    // Horizontal Gaussian cross-section (fine needle)
    float distX = abs(localUV.x - 0.5);
    const float NEEDLE_SIGMA = 0.055;
    float needleProfile = exp(- (distX * distX) / (2.0 * NEEDLE_SIGMA * NEEDLE_SIGMA));

    // Vertical aerodynamic tapering: sharp tapered tail at top, leading bead near bottom
    float y = clamp(localUV.y, 0.0, 1.0);
    float verticalTaper = pow(y, 0.8) * pow(1.0 - y, 0.4) * 2.2;

    return clamp(needleProfile * verticalTaper, 0.0, 1.0);
}

// ------------------------------------------------------------------------------
// Master Precipitation Shading (Rain, Snow, Desert Sandstorm)
// ------------------------------------------------------------------------------
vec4 shadePrecipitationParticle(vec4 baseTex, vec2 uv, vec3 totalLight, vec3 directLight, 
                                float forwardSun, float forwardMoon, float timeSec, 
                                vec3 worldPos, BiomeAtmosphere biomeAtm) {
    #ifndef RAIN_STREAKS
    return baseTex;
    #endif

    // Local quad coordinates [0..1]
    vec2 localUV = fract(uv);

    // --- 1. DESERT / ARID BIOMES: SWIRLING SANDSTORM ---
    #ifdef DESERT_SANDSTORM
    if (biomeAtm.isArid) {
        vec3 sandDust = vec3(0.88, 0.64, 0.38) * (totalLight * 0.75 + vec3(0.28));
        float dustNoise = gradientNoise2D(localUV * 4.0 + worldPos.xz * 0.2);
        float sandAlpha = baseTex.a * (0.50 + dustNoise * 0.35);
        return vec4(sandDust, sandAlpha);
    }
    #endif

    // --- 2. COLD BIOMES / WHITE FLAKES: PROCEDURAL DENDRITIC SNOW ---
    if (isPrecipitationSnow(baseTex, biomeAtm)) {
        float crystalMask = evaluateDendriticSnowflake(localUV, timeSec, worldPos);

        #ifdef PROCEDURAL_SNOW
        if (crystalMask < 0.02) return vec4(0.0);
        #endif

        // Icy crystalline subsurface scattering color
        vec3 snowAlbedo = vec3(0.95, 0.98, 1.08);
        vec3 snowShaded = snowAlbedo * (totalLight * 0.90 + vec3(0.12, 0.16, 0.22));

        #ifdef SNOW_DIAMOND_DUST
        // Diamond dust micro-facet specular glint
        float sparkleSeed = hash21(floor(worldPos.xz * 3.0) + floor(worldPos.y * 2.0));
        float sparklePhase = sin(timeSec * 9.0 + sparkleSeed * 6.28318);
        float sparkle = pow(max(sparklePhase, 0.0), 10.0) * step(0.68, sparkleSeed);
        snowShaded += (directLight + vec3(1.2)) * (sparkle * 2.8);
        #endif

        #ifdef PROCEDURAL_SNOW
        float alpha = crystalMask * 0.88;
        #else
        float alpha = baseTex.a * 0.82;
        #endif

        return vec4(snowShaded, alpha);
    }

    // --- 3. TEMPERATE BIOMES: AERODYNAMIC NEEDLE RAIN ---
    float needleMask = evaluateRainNeedleStreak(localUV);

    #ifdef PROCEDURAL_RAIN
    if (needleMask < 0.02) return vec4(0.0);
    #endif

    // Forward Mie scattering glisten when backlit by sun/moon
    #ifdef RAIN_MIE_GLISTEN
    float glisten = pow(forwardSun, 1.1) + pow(forwardMoon, 1.1);
    #else
    float glisten = 1.0;
    #endif

    vec3 waterTint = vec3(0.78, 0.88, 0.98);
    vec3 rainIlluminated = waterTint * (totalLight * 1.15 + vec3(0.20, 0.26, 0.32));
    rainIlluminated += directLight * (glisten * 0.35);

    #ifdef PROCEDURAL_RAIN
    float rainAlpha = needleMask * 0.76;
    #else
    float rainAlpha = baseTex.a * 0.78;
    #endif

    return vec4(rainIlluminated, rainAlpha);
}

// Backward compatibility alias for any existing call sites
vec4 shadeRainParticle(vec4 baseTexColor, vec3 lightColor, float timeSec, BiomeAtmosphere biomeAtm) {
    return shadePrecipitationParticle(baseTexColor, vec2(0.5), lightColor, lightColor, 1.0, 1.0, timeSec, vec3(0.0), biomeAtm);
}

#endif // WEATHER_GLSL
