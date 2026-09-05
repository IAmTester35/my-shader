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
 *  Thunderstorm branching lightning, rain fog, desert sandstorms, and wet optics
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

// Raindrop particle optical enhancement
vec4 shadeRainParticle(vec4 baseTexColor, vec3 lightColor, float timeSec, BiomeAtmosphere biomeAtm) {
    #ifndef RAIN_STREAKS
    return baseTexColor;
    #endif

    #ifdef DESERT_SANDSTORM
    if (biomeAtm.isArid) {
        // Render swirling amber dust/sand particles
        vec3 sandColor = vec3(0.85, 0.62, 0.35) * (lightColor * 0.7 + vec3(0.3));
        return vec4(sandColor, baseTexColor.a * 0.65);
    }
    #endif

    vec3 illuminatedRain = baseTexColor.rgb * (lightColor * 1.3 + vec3(0.25, 0.32, 0.38));
    float alpha = baseTexColor.a * 0.78;

    return vec4(illuminatedRain, alpha);
}

#endif // WEATHER_GLSL
