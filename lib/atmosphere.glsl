#ifndef ATMOSPHERE_GLSL
#define ATMOSPHERE_GLSL

#include "settings.glsl"
#include "common.glsl"
#include "biome.glsl"

/*
 * ==============================================================================
 *  ATMOSPHERIC SCATTERING & SKY DYNAMICS (HIGH-END BIOME-AWARE)
 *  Rayleigh scattering, Ozone Chappuis band, Mie aerosols, dynamic biomes
 * ==============================================================================
 */

// Phase functions
float rayleighPhase(float cosTheta) {
    return (3.0 / (16.0 * PI)) * (1.0 + cosTheta * cosTheta);
}

float hgPhase(float cosTheta, float g) {
    float g2 = g * g;
    return (1.0 / (4.0 * PI)) * ((1.0 - g2) / pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

// Dual-lobe Henyey-Greenstein (strong forward + subtle backscattering glory)
float dualHgPhase(float cosTheta, float g1, float g2, float k) {
    return mix(hgPhase(cosTheta, g1), hgPhase(cosTheta, g2), k);
}

// Forward declarations for celestial light colors
vec3 getSunColor(float sunHeight, float rain);
vec3 getMoonColor(float moonHeight, float rain);

// Sky color evaluation for any view ray in world space (with optional directional lightning azimuth)
vec3 calculateAtmosphericSky(vec3 rayDir, vec3 sunDir, vec3 moonDir, vec3 upVector, float rain, float stormLightning, float stormAzimuth, BiomeAtmosphere biomeAtm) {
    float cosViewUp = dot(rayDir, upVector);
    float cosSun    = dot(rayDir, sunDir);
    float cosMoon   = dot(rayDir, moonDir);
    float sunHeight = dot(sunDir, upVector);
    float moonHeight = dot(moonDir, upVector);

    // View elevation factor
    float viewElevation = max(cosViewUp, 0.0);
    float horizonFactor = pow(1.0 - viewElevation, 4.0);

    // Base Day palette
    vec3 dayZenith   = vec3(0.15, 0.36, 0.84) * biomeAtm.skyTint;
    vec3 dayHorizon  = vec3(0.64, 0.80, 0.96) * biomeAtm.skyTint;

    // Sunset / Sunrise palette
    vec3 sunsetZenith  = vec3(0.10, 0.14, 0.36);
    vec3 sunsetHorizon = vec3(0.98, 0.42, 0.10) * biomeAtm.fogTint;
    vec3 sunsetGolden  = vec3(1.00, 0.74, 0.28);

    #ifdef OZONE_ABSORPTION
    // Chappuis ozone absorption creates the authentic deep purple "blue hour" during twilight
    float twilightFactor = (1.0 - smoothstep(-0.15, 0.05, abs(sunHeight + 0.04)));
    sunsetZenith = mix(sunsetZenith, vec3(0.06, 0.08, 0.28), twilightFactor * 0.7);
    #endif

    // Night palette
    vec3 nightZenith     = vec3(0.005, 0.009, 0.024) * (biomeAtm.isCold ? 1.2 : 1.0);
    vec3 nightHorizon    = vec3(0.016, 0.026, 0.052) * (biomeAtm.isCold ? 1.15 : 1.0);
    vec3 moonlightZenith = vec3(0.012, 0.022, 0.048);

    // Blend weights
    float dayFactor    = smoothstep(-0.06, 0.20, sunHeight);
    float sunsetFactor = (1.0 - smoothstep(0.0, 0.25, abs(sunHeight))) * (1.0 - smoothstep(0.15, 0.35, sunHeight));
    float nightFactor  = 1.0 - dayFactor;

    // Atmosphere density parameter modulates zenith-to-horizon gradient falloff
    float atmDensity = max(ATMOSPHERE_DENSITY, 0.1);
    vec3 daySky = mix(dayHorizon, dayZenith, pow(viewElevation, 0.65 / atmDensity));

    #ifdef RAYLEIGH_SCATTERING
    // Physical Rayleigh scattering phase: brightens forward (near sun) and backward (anti-solar), dips at 90°
    float rPhase = 0.75 + 0.50 * cosSun * cosSun;
    daySky *= mix(1.0, rPhase, clamp(sunHeight * 2.5, 0.0, 1.0));
    #endif

    // Sunset directional glow
    float sunAzimuthGlow = pow(max(cosSun, 0.0), 3.0);
    vec3 sunsetSky = mix(sunsetHorizon, sunsetZenith, pow(viewElevation, 0.5 / atmDensity));
    sunsetSky += sunsetGolden * sunAzimuthGlow * (1.0 - viewElevation);

    vec3 nightSky = mix(nightHorizon, nightZenith, pow(viewElevation, 0.7 / atmDensity));
    nightSky += moonlightZenith * max(cosMoon, 0.0) * 0.5;

    // Composite time-of-day sky
    vec3 skyColor = mix(nightSky, daySky, dayFactor);
    skyColor = mix(skyColor, sunsetSky, sunsetFactor * 0.88);

    #ifdef MIE_SCATTERING
    // Forward Mie scattering (aerosol sun halo)
    if (sunHeight > -0.18) {
        float mieGlow = hgPhase(cosSun, 0.82) * 0.11 * biomeAtm.hazeDensity;
        vec3 mieColor = mix(vec3(1.0, 0.62, 0.22), vec3(1.0, 0.96, 0.90), clamp(sunHeight * 3.0, 0.0, 1.0));
        skyColor += mieColor * mieGlow * clamp((sunHeight + 0.18) * 4.0, 0.0, 1.0);
    }
    // Nocturnal lunar Mie scattering (aerosol moon halo across the night sky)
    if (sunHeight < 0.10 && moonHeight > -0.15) {
        float lunarMie = hgPhase(cosMoon, 0.78) * 0.06 * biomeAtm.hazeDensity;
        vec3 moonMieColor = vec3(0.65, 0.78, 1.0) * getMoonColor(moonHeight, rain);
        skyColor += moonMieColor * lunarMie * clamp((moonHeight + 0.15) * 4.0, 0.0, 1.0) * (1.0 - dayFactor);
    }
    #endif

    #ifdef DYNAMIC_WEATHER
    // Weather & Biome Overcast
    if (rain > 0.0) {
        #ifdef DESERT_SANDSTORM
        if (biomeAtm.isArid) {
            // Desert sandstorm / dust storm: howling ochre & terracotta haze
            vec3 sandstormColor = vec3(0.78, 0.52, 0.28) * mix(0.15, 1.0, dayFactor);
            skyColor = mix(skyColor, sandstormColor, rain * 0.92);
        } else {
            // Standard rain / snow overcast
            vec3 overcastDay   = vec3(0.28, 0.30, 0.34) * biomeAtm.fogTint;
            vec3 overcastNight = vec3(0.018, 0.022, 0.032);
            vec3 overcast = mix(overcastNight, overcastDay, dayFactor);
            overcast *= mix(1.0, 0.68, horizonFactor);
            skyColor = mix(skyColor, overcast, rain * 0.90);
        }
        #else
        vec3 overcastDay   = vec3(0.28, 0.30, 0.34) * biomeAtm.fogTint;
        vec3 overcastNight = vec3(0.018, 0.022, 0.032);
        vec3 overcast = mix(overcastNight, overcastDay, dayFactor);
        overcast *= mix(1.0, 0.68, horizonFactor);
        skyColor = mix(skyColor, overcast, rain * 0.90);
        #endif

        #ifdef STORM_LIGHTNING
        if (stormLightning > 0.01) {
            vec3 lightningColor = vec3(0.88, 0.94, 1.15) * 3.0;
            float dirFactor = 0.85;
            if (stormAzimuth > -50.0) {
                vec2 strikeDir = vec2(cos(stormAzimuth), sin(stormAzimuth));
                vec2 rayXZ = normalize(rayDir.xz + vec2(1e-5));
                dirFactor = 0.35 + 0.65 * max(dot(rayXZ, strikeDir), 0.0);
            }
            skyColor = mix(skyColor, lightningColor, stormLightning * dirFactor * 0.90);
        }
        #endif
    }
    #endif

    #ifdef SKY_GROUND_FOG
    // Atmospheric ground fade near bottom
    if (cosViewUp < 0.0) {
        float belowHorizon = clamp(-cosViewUp * 3.5, 0.0, 1.0);
        vec3 groundFogColor = mix(skyColor * 0.35, vec3(0.002, 0.004, 0.008), 0.7);
        skyColor = mix(skyColor, groundFogColor, belowHorizon);
    }
    #endif

    return max(skyColor, vec3(0.0));
}

// 7-parameter compatibility wrapper
vec3 calculateAtmosphericSky(vec3 rayDir, vec3 sunDir, vec3 moonDir, vec3 upVector, float rain, float stormLightning, BiomeAtmosphere biomeAtm) {
    return calculateAtmosphericSky(rayDir, sunDir, moonDir, upVector, rain, stormLightning, -100.0, biomeAtm);
}

// Distance fog color matching atmospheric scattering and biome
vec3 getAtmosphericFogColor(vec3 rayDir, vec3 sunDir, vec3 moonDir, vec3 upVector, float rain, float stormLightning, BiomeAtmosphere biomeAtm) {
    vec3 horizonDir = normalize(vec3(rayDir.x, max(rayDir.y * 0.25, 0.02), rayDir.z));
    return calculateAtmosphericSky(horizonDir, sunDir, moonDir, upVector, rain, stormLightning, biomeAtm);
}

// Direct celestial light colors
vec3 getSunColor(float sunHeight, float rain) {
    vec3 middaySun = vec3(1.00, 0.98, 0.92) * 1.5;
    vec3 sunsetSun = vec3(1.00, 0.42, 0.08) * 1.2;
    vec3 nightSun  = vec3(0.0);

    float dayFactor = clamp(sunHeight * 4.0, 0.0, 1.0);
    vec3 light = mix(sunsetSun, middaySun, dayFactor);
    light = mix(nightSun, light, clamp((sunHeight + 0.05) * 10.0, 0.0, 1.0));
    
    light *= (1.0 - rain * 0.75);
    return light;
}

vec3 getMoonColor(float moonHeight, float rain) {
    vec3 moonLight = vec3(0.25, 0.38, 0.60) * 0.22;
    moonLight *= clamp((moonHeight + 0.05) * 10.0, 0.0, 1.0);
    moonLight *= (1.0 - rain * 0.80);
    return moonLight;
}

#endif // ATMOSPHERE_GLSL
