#ifndef ATMOSPHERE_GLSL
#define ATMOSPHERE_GLSL

#include "settings.glsl"
#include "common.glsl"
#include "biome.glsl"
#include "lightning.glsl"

/*
 * ==============================================================================
 *  ATMOSPHERIC SCATTERING & SKY DYNAMICS (HIGH-END BIOME-AWARE)
 *  Rayleigh scattering, Ozone Chappuis band, Mie aerosols, dynamic biomes
 * ==============================================================================
 */

// Phase functions
float rayleighPhase(float cosTheta) {
    return 0.75 + 0.50 * cosTheta * cosTheta;
}

// Dual-lobe Henyey-Greenstein (strong forward + subtle backscattering glory)
float dualHgPhase(float cosTheta, float g1, float g2, float k) {
    return doubleHgPhase(cosTheta, g1, g2, k);
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

// Sky color evaluation for any view ray in world space (Primary implementation with LightningStrike)
vec3 calculateAtmosphericSky(vec3 rayDir, vec3 sunDir, vec3 moonDir, vec3 upVector, float rain, LightningStrike strike, BiomeAtmosphere biomeAtm) {
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
    daySky *= mix(1.0, rayleighPhase(cosSun), clamp(sunHeight * 2.5, 0.0, 1.0));
    #endif

    // Sunset directional glow
    float sunAzimuthGlow = pow(max(cosSun, 0.0), 3.0);
    vec3 sunsetSky = mix(sunsetHorizon, sunsetZenith, pow(viewElevation, 0.5 / atmDensity));
    sunsetSky += sunsetGolden * sunAzimuthGlow * (1.0 - viewElevation);

    #ifdef BELT_OF_VENUS
    // Belt of Venus & Earth's shadow on the anti-solar horizon (looking away from sunset/sunrise)
    if (abs(sunHeight) < 0.22) {
        float antiSolar = max(-cosSun, 0.0);
        float venusPink = pow(antiSolar, 4.0) * (1.0 - smoothstep(0.08, 0.32, viewElevation));
        float earthShadow = pow(antiSolar, 6.0) * (1.0 - smoothstep(0.0, 0.08, viewElevation));
        sunsetSky = mix(sunsetSky, vec3(0.85, 0.45, 0.52), venusPink * 0.45);
        sunsetSky = mix(sunsetSky, vec3(0.08, 0.12, 0.26), earthShadow * 0.60);
    }
    #endif

    #ifdef SKY_MULTI_SCATTERING
    // Higher-order atmospheric multiple scattering: fills shadowed sky with realistic secondary blue/gold ambient
    vec3 multiScatter = mix(vec3(0.04, 0.09, 0.22), vec3(0.12, 0.15, 0.20), viewElevation) * max(sunHeight + 0.15, 0.0);
    daySky += multiScatter * 0.35;
    #endif

    // Night sky
    vec3 nightSky = mix(nightHorizon, nightZenith, pow(viewElevation, 0.7 / atmDensity));

    // Combine Day, Sunset, and Night sky layers
    vec3 skyColor = mix(nightSky, daySky, dayFactor);
    skyColor = mix(skyColor, sunsetSky, sunsetFactor);

    // Moon atmospheric glow (Mie lunar halo)
    #ifdef MOON_HALO
    if (moonHeight > -0.20 && nightFactor > 0.05) {
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
        } else
        #endif
        {
            // Standard rain / snow overcast
            vec3 overcastDay   = vec3(0.28, 0.30, 0.34) * biomeAtm.fogTint;
            vec3 overcastNight = vec3(0.018, 0.022, 0.032);
            vec3 overcast = mix(overcastNight, overcastDay, dayFactor);
            overcast *= mix(1.0, 0.68, horizonFactor);
            skyColor = mix(skyColor, overcast, rain * 0.90);
        }
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

    #ifdef STORM_LIGHTNING
    if (strike.isTriggered && strike.intensity > 0.005) {
        // 1. Tia sét hình học fractal sắc nét (core + sheath + branches)
        vec3 boltRadiance = evaluateProceduralLightningBolt(rayDir, strike);

        // 2. Quầng tán xạ ion hóa Mie tập trung quanh vị trí sét
        vec3 airGlow = evaluateAtmosphericLightningGlow(rayDir, strike);

        // 3. Phản quang chân trời góc nhìn trực diện (tập trung theo phương vị sét, tán xạ dịu mắt)
        float azimMatch = max(dot(normalize(rayDir.xz + vec2(1e-4)), strike.strikeDir.xz), 0.0);
        float horizonFlash = pow(azimMatch, 5.0) * exp(-abs(rayDir.y) * 9.0) * 0.22;
        vec3 bounceGlow = strike.sheathColor * horizonFlash * strike.intensity;

        skyColor += boltRadiance + airGlow + bounceGlow;
    }
    #endif

    return max(skyColor, vec3(0.0));
}

// 8-parameter compatibility wrapper (for legacy calls)
vec3 calculateAtmosphericSky(vec3 rayDir, vec3 sunDir, vec3 moonDir, vec3 upVector, float rain, float stormLightning, float stormAzimuth, BiomeAtmosphere biomeAtm) {
    LightningStrike strike;
    strike.isTriggered = (stormLightning > 0.005);
    strike.intensity = stormLightning;
    strike.returnStroke = stormLightning;
    strike.azimuth = (stormAzimuth > -50.0) ? stormAzimuth : 0.0;
    strike.elevation = 0.20;
    strike.strikeDir = normalize(vec3(cos(strike.azimuth) * cos(0.20), sin(0.20), sin(strike.azimuth) * cos(0.20)));
    strike.seed = hash11(strike.azimuth * 47.19 + 3.1);
    strike.strikeType = LIGHTNING_TYPE_CG;
    strike.coreColor = vec3(1.15, 1.25, 1.50) * 55.0;
    strike.sheathColor = vec3(0.35, 0.72, 1.30);
    return calculateAtmosphericSky(rayDir, sunDir, moonDir, upVector, rain, strike, biomeAtm);
}

// 7-parameter compatibility wrapper
vec3 calculateAtmosphericSky(vec3 rayDir, vec3 sunDir, vec3 moonDir, vec3 upVector, float rain, float stormLightning, BiomeAtmosphere biomeAtm) {
    return calculateAtmosphericSky(rayDir, sunDir, moonDir, upVector, rain, stormLightning, -100.0, biomeAtm);
}

// Distance fog color matching atmospheric scattering and biome (pure diffuse fog, no bolt geometry)
vec3 getAtmosphericFogColor(vec3 rayDir, vec3 sunDir, vec3 moonDir, vec3 upVector, float rain, LightningStrike strike, BiomeAtmosphere biomeAtm) {
    vec3 horizonDir = normalize(vec3(rayDir.x, max(rayDir.y * 0.25, 0.02), rayDir.z));
    LightningStrike fogStrike = strike;
    fogStrike.isTriggered = false; // Never render geometric bolt into fog or cloud ambient light!
    vec3 fogColor = calculateAtmosphericSky(horizonDir, sunDir, moonDir, upVector, rain, fogStrike, biomeAtm);

    #ifdef STORM_LIGHTNING
    if (strike.isTriggered && strike.intensity > 0.005) {
        float fogFlash = pow(max(dot(horizonDir, strike.strikeDir) * 0.5 + 0.5, 0.0), 3.0);
        fogColor += strike.sheathColor * (fogFlash * 0.40 + 0.10) * strike.intensity * LIGHTNING_INTENSITY;
    }
    #endif

    return fogColor;
}

vec3 getAtmosphericFogColor(vec3 rayDir, vec3 sunDir, vec3 moonDir, vec3 upVector, float rain, float stormLightning, BiomeAtmosphere biomeAtm) {
    LightningStrike s;
    s.isTriggered = (stormLightning > 0.005);
    s.intensity = stormLightning;
    s.sheathColor = vec3(0.35, 0.72, 1.30);
    s.strikeDir = vec3(0.0, 0.20, 1.0);
    return getAtmosphericFogColor(rayDir, sunDir, moonDir, upVector, rain, s, biomeAtm);
}

#endif // ATMOSPHERE_GLSL
