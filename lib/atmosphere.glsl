#ifndef ATMOSPHERE_GLSL
#define ATMOSPHERE_GLSL

#include "settings.glsl"
#include "common.glsl"
#include "biome.glsl"
#include "lightning.glsl"

/*
 * ==============================================================================
 *  PHYSICALLY BASED ATMOSPHERIC SCATTERING & CELESTIAL ILLUMINATION
 *  - Spherical planetary geometry (Earth Rp=6360km, Ratm=6460km)
 *  - Wavelength-dependent Rayleigh scattering (lambda = 680, 550, 440 nm)
 *  - Mie aerosol scattering with Henyey-Greenstein forward phase
 *  - Chappuis band stratospheric ozone absorption (twilight Blue Hour)
 *  - Analytical Chapman function for spherical optical air mass
 *  - Natural Earth shadow projection & Belt of Venus anti-solar twilight arch
 *  - Physically based direct solar transmittance & spectrum (Tsun)
 *  - Directional hemispherical diffuse skylight for terrain, water and clouds
 * ==============================================================================
 */

// Planetary atmosphere constants
const float ATM_PLANET_RADIUS   = 6360.0; // km (Earth radius)
const float ATM_TOP_RADIUS      = 6460.0; // km (Top of atmosphere: 100km thickness)
const float ATM_SCALE_RAYLEIGH  = 8.0;    // km (Rayleigh molecular scale height)
const float ATM_SCALE_MIE       = 1.2;    // km (Mie aerosol scale height)
const float ATM_OZONE_CENTER    = 25.0;   // km (Chappuis ozone layer center altitude)
const float ATM_OZONE_THICKNESS = 15.0;   // km (Ozone layer half-thickness)

// Physical scattering & extinction coefficients at sea level (km^-1)
// Standard RGB wavelengths: Red=680nm, Green=550nm, Blue=440nm
const vec3 ATM_BETA_RAYLEIGH    = vec3(5.802e-3, 13.558e-3, 33.100e-3);
const vec3 ATM_BETA_MIE_SCAT    = vec3(3.996e-3);
const vec3 ATM_BETA_MIE_EXT     = vec3(3.996e-3 / 0.9); // Albedo ~0.9
const vec3 ATM_BETA_OZONE       = vec3(0.650e-3, 1.881e-3, 0.085e-3); // Chappuis band

// Solar irradiance constant (calibrated for game dynamic range & ACES tonemapping)
const vec3 ATM_SOLAR_IRRADIANCE = vec3(1.00, 0.98, 0.95) * 16.0 * SUN_ILLUMINANCE;

// --- Phase Functions ---
float rayleighPhase(float cosTheta) {
    return (3.0 / (16.0 * PI)) * (1.0 + cosTheta * cosTheta);
}

float dualHgPhase(float cosTheta, float g1, float g2, float k) {
    return doubleHgPhase(cosTheta, g1, g2, k);
}

float atmosphericMiePhase(float cosTheta, float g) {
    float g2 = g * g;
    float num = 3.0 * (1.0 - g2) * (1.0 + cosTheta * cosTheta);
    float denom = 8.0 * PI * (2.0 + g2) * pow(max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4), 1.5);
    return num / denom;
}

// Analytical Chapman air mass function for spherical atmosphere
float chapmanAirMass(float x, float cosZenith) {
    float c = max(cosZenith, 0.0);
    float sqrtTerm = sqrt(0.63661977 / x); // sqrt(2 / (pi * x))
    return 1.0 / (c + sqrtTerm * ((1.0 - c) / (1.0 + 0.5 * c)));
}

// Analytical optical depth from atmospheric point p along lightDir to space
void getAtmosphericOpticalDepths(vec3 p, vec3 lightDir, out float optR, out float optM, out float optO) {
    float r = length(p);
    float h = r - ATM_PLANET_RADIUS;
    vec3 up = p / r;
    float cosZenith = dot(lightDir, up);

    float xR = r / ATM_SCALE_RAYLEIGH;
    float xM = r / ATM_SCALE_MIE;
    float tauZenithR = ATM_SCALE_RAYLEIGH * exp(-max(h, 0.0) / ATM_SCALE_RAYLEIGH);
    float tauZenithM = ATM_SCALE_MIE      * exp(-max(h, 0.0) / ATM_SCALE_MIE);
    float tauZenithO = ATM_OZONE_THICKNESS * max(0.0, 1.0 - abs(h - ATM_OZONE_CENTER) / ATM_OZONE_THICKNESS);

    if (cosZenith >= 0.0) {
        optR = tauZenithR * chapmanAirMass(xR, cosZenith);
        optM = tauZenithM * chapmanAirMass(xM, cosZenith);
        float airMassOzone = 1.0 / sqrt(cosZenith * cosZenith + 2.0 * (ATM_OZONE_CENTER / ATM_PLANET_RADIUS));
        optO = ATM_OZONE_THICKNESS * airMassOzone;
    } else {
        float sinZenith = sqrt(max(1.0 - cosZenith * cosZenith, 0.0));
        float rTan = r * sinZenith;
        if (rTan < ATM_PLANET_RADIUS) {
            // Blocked by planetary sphere (Earth shadow)
            optR = 1e6;
            optM = 1e6;
            optO = 1e6;
            return;
        }
        float hTan = rTan - ATM_PLANET_RADIUS;
        float xTanR = rTan / ATM_SCALE_RAYLEIGH;
        float xTanM = rTan / ATM_SCALE_MIE;
        float tauTanR = ATM_SCALE_RAYLEIGH * exp(-hTan / ATM_SCALE_RAYLEIGH);
        float tauTanM = ATM_SCALE_MIE      * exp(-hTan / ATM_SCALE_MIE);

        float horizMassR = chapmanAirMass(xTanR, 0.0);
        float horizMassM = chapmanAirMass(xTanM, 0.0);
        float backMassR  = chapmanAirMass(xR, -cosZenith);
        float backMassM  = chapmanAirMass(xM, -cosZenith);

        optR = 2.0 * tauTanR * horizMassR - tauZenithR * backMassR;
        optM = 2.0 * tauTanM * horizMassM - tauZenithM * backMassM;

        float airMassOzone = 1.0 / sqrt(cosZenith * cosZenith + 2.0 * (ATM_OZONE_CENTER / ATM_PLANET_RADIUS));
        optO = 2.0 * ATM_OZONE_THICKNESS * (1.0 / sqrt(2.0 * (ATM_OZONE_CENTER / ATM_PLANET_RADIUS))) - ATM_OZONE_THICKNESS * airMassOzone;
    }
}

// Atmospheric transmittance along light ray
vec3 getAtmosphericTransmittance(vec3 p, vec3 lightDir, vec3 betaR, vec3 betaM_ext, vec3 betaO) {
    float optR, optM, optO;
    getAtmosphericOpticalDepths(p, lightDir, optR, optM, optO);
    if (optR > 1e5) return vec3(0.0);
    vec3 tau = betaR * optR + betaM_ext * optM + betaO * optO;
    return exp(-tau);
}

// --- Physically Based Direct Solar Illumination ---
vec3 getSunColor(float sunHeight, float rain) {
    if (sunHeight < -0.09) return vec3(0.0);

    vec3 betaR     = ATM_BETA_RAYLEIGH * (RAYLEIGH_SCALE * ATMOSPHERE_DENSITY);
    vec3 betaM_ext = ATM_BETA_MIE_EXT  * (MIE_TURBIDITY * ATMOSPHERE_DENSITY);
    vec3 betaO     = ATM_BETA_OZONE    * (OZONE_SCALE * ATMOSPHERE_DENSITY);

    vec3 p = vec3(0.0, ATM_PLANET_RADIUS + 0.5, 0.0);
    float h = clamp(sunHeight, -0.07, 1.0);
    vec3 sunDir = normalize(vec3(sqrt(max(1.0 - h * h, 0.0)), h, 0.0));

    vec3 transmittance = getAtmosphericTransmittance(p, sunDir, betaR, betaM_ext, betaO);
    float horizonCutoff = smoothstep(-0.07, 0.02, sunHeight);

    vec3 directSun = (ATM_SOLAR_IRRADIANCE * 0.14) * transmittance * horizonCutoff;
    directSun *= (1.0 - rain * 0.85);

    return max(directSun, vec3(0.0));
}

// --- Physically Based Direct Lunar Illumination ---
vec3 getMoonColor(float moonHeight, float rain) {
    if (moonHeight < -0.09) return vec3(0.0);

    vec3 betaR     = ATM_BETA_RAYLEIGH * (RAYLEIGH_SCALE * ATMOSPHERE_DENSITY);
    vec3 betaM_ext = ATM_BETA_MIE_EXT  * (MIE_TURBIDITY * ATMOSPHERE_DENSITY);
    vec3 betaO     = ATM_BETA_OZONE    * (OZONE_SCALE * ATMOSPHERE_DENSITY);

    vec3 p = vec3(0.0, ATM_PLANET_RADIUS + 0.5, 0.0);
    float h = clamp(moonHeight, -0.07, 1.0);
    vec3 moonDir = normalize(vec3(sqrt(max(1.0 - h * h, 0.0)), h, 0.0));

    vec3 transmittance = getAtmosphericTransmittance(p, moonDir, betaR, betaM_ext, betaO);
    float horizonCutoff = smoothstep(-0.07, 0.02, moonHeight);

    vec3 directMoon = vec3(0.20, 0.32, 0.52) * 0.26 * transmittance * horizonCutoff;
    directMoon *= (1.0 - rain * 0.85);

    return max(directMoon, vec3(0.0));
}

// --- Physical Atmospheric Sky Radiance ---
vec3 calculateAtmosphericSky(vec3 rayDir, vec3 sunDir, vec3 moonDir, vec3 upVector, float rain, LightningStrike strike, BiomeAtmosphere biomeAtm) {
    // Physical scattering and absorption coefficients modulated by biome & settings
    float biomeHaze = biomeAtm.hazeDensity;
    vec3 betaR     = ATM_BETA_RAYLEIGH * (RAYLEIGH_SCALE * ATMOSPHERE_DENSITY);
    vec3 betaM_scat= ATM_BETA_MIE_SCAT * (MIE_TURBIDITY * ATMOSPHERE_DENSITY * biomeHaze);
    vec3 betaM_ext = ATM_BETA_MIE_EXT  * (MIE_TURBIDITY * ATMOSPHERE_DENSITY * biomeHaze);
    vec3 betaO     = ATM_BETA_OZONE    * (OZONE_SCALE * ATMOSPHERE_DENSITY);

    #ifndef RAYLEIGH_SCATTERING
    betaR = vec3(0.0);
    #endif
    #ifndef MIE_SCATTERING
    betaM_scat = vec3(0.0);
    betaM_ext = vec3(0.0);
    #endif
    #ifndef OZONE_ABSORPTION
    betaO = vec3(0.0);
    #endif

    // Observer position inside planetary shell (sea-level + 0.5km altitude)
    vec3 p = vec3(0.0, ATM_PLANET_RADIUS + 0.5, 0.0);

    // Ray-sphere intersections
    float b = 2.0 * dot(rayDir, p);
    float c_top = dot(p, p) - (ATM_TOP_RADIUS * ATM_TOP_RADIUS);
    float d_top = max(b * b - 4.0 * c_top, 0.0);
    float tAtm = (-b + sqrt(d_top)) * 0.5;

    float c_bot = dot(p, p) - (ATM_PLANET_RADIUS * ATM_PLANET_RADIUS);
    float d_bot = b * b - 4.0 * c_bot;
    float tGround = -1.0;
    if (d_bot >= 0.0) {
        float tCand = (-b - sqrt(d_bot)) * 0.5;
        if (tCand > 0.0) tGround = tCand;
    }
    float tMax = (tGround > 0.0) ? tGround : tAtm;

    // Celestial angles and phase functions
    float cosThetaSun  = dot(rayDir, sunDir);
    float cosThetaMoon = dot(rayDir, moonDir);
    float sunElev      = dot(sunDir, upVector);
    float moonElev     = dot(moonDir, upVector);

    float phaseRSun  = rayleighPhase(cosThetaSun);
    float phaseMSun  = atmosphericMiePhase(cosThetaSun, 0.78);
    float phaseRMoon = rayleighPhase(cosThetaMoon);
    float phaseMMoon = atmosphericMiePhase(cosThetaMoon, 0.78);

    // Transmittance to observer
    vec3 sunTransObs  = getAtmosphericTransmittance(p, sunDir, betaR, betaM_ext, betaO);
    vec3 moonTransObs = getAtmosphericTransmittance(p, moonDir, betaR, betaM_ext, betaO);

    vec3 sunL0  = ATM_SOLAR_IRRADIANCE * (1.0 - rain * 0.85);
    vec3 moonL0 = ATM_SOLAR_IRRADIANCE * 0.00035 * (1.0 - rain * 0.85);

    // Multiple scattering ambient fill with stratospheric twilight glow
    #ifdef SKY_MULTI_SCATTERING
    vec3 twilightGlow = vec3(0.045, 0.085, 0.26) * (1.0 - smoothstep(-0.15, 0.04, abs(sunElev + 0.04)));
    vec3 multiScatterAmbient = (sunL0 * sunTransObs * max(sunElev, 0.0) + twilightGlow + vec3(0.005, 0.009, 0.024)) * 0.28 * MULTI_SCATTER_SCALE;
    #else
    vec3 multiScatterAmbient = vec3(0.005, 0.009, 0.024);
    #endif

    // Primary view raymarch integration (14 steps with power spacing)
    const int VIEW_STEPS = 14;
    vec3 optView = vec3(0.0);
    vec3 inScatter = vec3(0.0);

    for (int i = 0; i < VIEW_STEPS; ++i) {
        float fracA = float(i) / float(VIEW_STEPS);
        float fracB = float(i + 1) / float(VIEW_STEPS);
        float distA = tMax * pow(fracA, 1.25);
        float distB = tMax * pow(fracB, 1.25);
        float segLen = distB - distA;
        float midDist = (distA + distB) * 0.5;

        vec3 pSample = p + rayDir * midDist;
        float hSample = length(pSample) - ATM_PLANET_RADIUS;
        float rR = exp(-max(hSample, 0.0) / ATM_SCALE_RAYLEIGH);
        float rM = exp(-max(hSample, 0.0) / ATM_SCALE_MIE);
        float rO = max(0.0, 1.0 - abs(hSample - ATM_OZONE_CENTER) / ATM_OZONE_THICKNESS);

        vec3 optStep = (betaR * rR + betaM_ext * rM + betaO * rO) * segLen;
        optView += optStep;
        vec3 tView = exp(-optView);

        // Sunlight single scattering
        vec3 tSunSample = getAtmosphericTransmittance(pSample, sunDir, betaR, betaM_ext, betaO);
        vec3 sSun = (tSunSample * sunL0) * (betaR * rR * phaseRSun + betaM_scat * rM * phaseMSun);

        // Stratospheric twilight illumination when sun is just below horizon (Blue Hour)
        if (sunElev < 0.02 && sunElev > -0.18 && hSample > 10.0) {
            float straElev = sunElev + (hSample / ATM_PLANET_RADIUS);
            if (straElev > -0.04) {
                float straFactor = smoothstep(-0.18, 0.01, sunElev) * exp(-(hSample - 25.0)*(hSample - 25.0) / 130.0);
                vec3 straCol = vec3(0.18, 0.34, 0.95) * 2.2 * (1.0 - smoothstep(0.0, 0.09, abs(sunElev + 0.04)));
                sSun += straCol * (betaR * rR * 1.6 + betaO * rO * 2.8) * straFactor;
            }
        }

        // Moonlight single scattering
        vec3 tMoonSample = getAtmosphericTransmittance(pSample, moonDir, betaR, betaM_ext, betaO);
        vec3 sMoon = (tMoonSample * moonL0) * (betaR * rR * phaseRMoon + betaM_scat * rM * phaseMMoon);

        // Multiple scattering ambient
        vec3 sMS = multiScatterAmbient * (betaR * rR * 0.20 + betaM_scat * rM * 0.08);

        inScatter += (sSun + sMoon + sMS) * tView * segLen;
    }

    #ifdef SKY_GROUND_FOG
    // Ground bounce if looking below horizon
    if (tGround > 0.0) {
        vec3 groundNormal = normalize(p + rayDir * tGround);
        float NdotSun = max(dot(groundNormal, sunDir), 0.0);
        vec3 groundColor = vec3(0.08, 0.12, 0.06) * biomeAtm.skyTint;
        vec3 groundIllum = (sunL0 * sunTransObs * NdotSun + multiScatterAmbient) * groundColor;
        inScatter += groundIllum * exp(-optView);
    }
    #endif

    // Permanent atmospheric night airglow
    vec3 airglow = vec3(0.005, 0.009, 0.024) * (biomeAtm.isCold ? 1.25 : 1.0) * exp(-optView.r * 0.4);
    inScatter += airglow;

    // Apply Biome color grading tint
    inScatter *= biomeAtm.skyTint;

    #ifdef DYNAMIC_WEATHER
    // Dynamic Weather Overcast & Sandstorm
    if (rain > 0.0) {
        #ifdef DESERT_SANDSTORM
        if (biomeAtm.isArid) {
            float dayFactor = clamp(sunElev * 4.0 + 0.2, 0.0, 1.0);
            vec3 sandstormColor = vec3(0.78, 0.52, 0.28) * mix(0.15, 1.0, dayFactor);
            inScatter = mix(inScatter, sandstormColor, rain * 0.92);
        } else
        #endif
        {
            float dayFactor = clamp(sunElev * 4.0 + 0.2, 0.0, 1.0);
            vec3 overcastDay   = vec3(0.28, 0.30, 0.34) * biomeAtm.fogTint;
            vec3 overcastNight = vec3(0.018, 0.022, 0.032);
            vec3 overcast = mix(overcastNight, overcastDay, dayFactor);
            inScatter = mix(inScatter, overcast, rain * 0.90);
        }
    }
    #endif

    #ifdef STORM_LIGHTNING
    if (strike.isTriggered && strike.intensity > 0.005) {
        vec3 boltRadiance = evaluateProceduralLightningBolt(rayDir, strike);
        vec3 airGlow = evaluateAtmosphericLightningGlow(rayDir, strike);
        float azimMatch = max(dot(normalize(rayDir.xz + vec2(1e-4)), strike.strikeDir.xz), 0.0);
        float horizonFlash = pow(azimMatch, 5.0) * exp(-abs(rayDir.y) * 9.0) * 0.22;
        vec3 bounceGlow = strike.sheathColor * horizonFlash * strike.intensity;
        inScatter += boltRadiance + airGlow + bounceGlow;
    }
    #endif

    return max(inScatter * SKY_RADIANCE_SCALE, vec3(0.0));
}

// 8-parameter compatibility wrapper
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

// --- Directional Hemispherical Sky Ambient & Atmospheric Fog Color ---
vec3 getAtmosphericFogColor(vec3 rayDir, vec3 sunDir, vec3 moonDir, vec3 upVector, float rain, LightningStrike strike, BiomeAtmosphere biomeAtm) {
    vec3 horizonDir = normalize(vec3(rayDir.x, max(rayDir.y * 0.25, 0.02), rayDir.z));
    LightningStrike fogStrike = strike;
    fogStrike.isTriggered = false; // Never render geometric bolt into diffuse ambient!

    // Horizon sky radiance in view/normal direction (matches distance fog perfectly)
    vec3 fogColor = calculateAtmosphericSky(horizonDir, sunDir, moonDir, upVector, rain, fogStrike, biomeAtm);

    // If used as ambient normal irradiance on upward-facing surface, blend in zenith sky
    if (rayDir.y > 0.05) {
        vec3 zenithColor = calculateAtmosphericSky(upVector, sunDir, moonDir, upVector, rain, fogStrike, biomeAtm);
        fogColor = mix(fogColor, zenithColor, smoothstep(0.05, 0.85, rayDir.y) * 0.65);
    } else if (rayDir.y < -0.05) {
        // Downward-facing surfaces receive subtle ground reflection
        fogColor *= mix(1.0, 0.35, clamp(-rayDir.y * 1.5, 0.0, 1.0));
    }

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
