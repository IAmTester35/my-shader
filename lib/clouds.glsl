#ifndef CLOUDS_GLSL
#define CLOUDS_GLSL

#include "settings.glsl"
#include "common.glsl"
#include "noise.glsl"
#include "atmosphere.glsl"
#include "biome.glsl"

/*
 * ==============================================================================
 *  WMO 10 GENERA VOLUMETRIC 3D CLOUD SYSTEM (METEOROLOGICAL STANDARD)
 *  Physical Beer-Lambert law, dual-lobe phase scattering, powder-sugar effect,
 *  Perlin-Worley 3D cellular clusters, 22° ice crystal halo, and dynamic
 *  transitions between the 10 World Meteorological Organization cloud genera:
 *    High Tier (>6000m):     Cirrus (Ci), Cirrocumulus (Cc), Cirrostratus (Cs)
 *    Mid Tier (2000-6000m):   Altocumulus (Ac), Altostratus (As)
 *    Low Tier (<2000m):       Stratocumulus (Sc), Stratus (St), Nimbostratus (Ns)
 *    Vertical Development:   Cumulus (Cu), Cumulonimbus (Cb)
 * ==============================================================================
 */

// WMO Genera Identifiers
#define GENUS_AUTO          0
#define GENUS_CIRRUS        1
#define GENUS_CIRROCUMULUS  2
#define GENUS_CIRROSTRATUS  3
#define GENUS_ALTOCUMULUS   4
#define GENUS_ALTOSTRATUS   5
#define GENUS_STRATOCUMULUS 6
#define GENUS_STRATUS       7
#define GENUS_NIMBOSTRATUS  8
#define GENUS_CUMULUS       9
#define GENUS_CUMULONIMBUS  10

struct CloudResult {
    vec4 color;           // rgb = integrated radiance, a = optical opacity (1.0 - transmittance)
    float transmittance;  // accumulated transmittance for exact physical radiance transport
};

// Dynamic WMO Cloud Genus selector based on weather and biome
int getActiveCloudGenus(float rain, float stormLightning, BiomeAtmosphere biomeAtm) {
    #if CLOUD_WMO_GENUS > 0
    return CLOUD_WMO_GENUS;
    #else
    if (rain >= 0.85 || stormLightning > 0.01) {
        return GENUS_CUMULONIMBUS; // Thunderstorm -> Cumulonimbus anvil
    } else if (rain >= 0.45) {
        return GENUS_NIMBOSTRATUS; // Heavy overcast rain -> Nimbostratus
    } else if (rain >= 0.15) {
        return (biomeAtm.isHumid) ? GENUS_STRATOCUMULUS : GENUS_ALTOSTRATUS;
    } else if (biomeAtm.isHumid) {
        return GENUS_CUMULUS;      // Humid warm weather -> rich Cumulus
    } else if (biomeAtm.isCold) {
        return GENUS_CIRROCUMULUS; // Alpine / cold -> Cirrocumulus / Cirrus
    } else {
        return GENUS_CUMULUS;      // Standard fair weather -> Cumulus
    }
    #endif
}

// 3D Cloud Density Evaluation for Low / Mid / Vertical Genera
float sampleCloudDensity3D(vec3 worldPos, float relHeight, int genus, float rain, float timeSec, BiomeAtmosphere biomeAtm) {
    // 0. High-tier ice crystal genera (>6000m) have zero density in the lower convective slab
    if (genus == GENUS_CIRRUS || genus == GENUS_CIRROCUMULUS || genus == GENUS_CIRROSTRATUS) {
        return 0.0;
    }

    // 1. Vertical profile shaping tailored to each WMO genus
    float heightProfile = 0.0;

    if (genus == GENUS_CUMULUS) {
        // Cumulus (Mây tích): Flat dark condensation base (LCL), blooming cauliflower dome
        float baseCut = smoothstep(0.04, 0.14, relHeight);
        float topDome = 1.0 - smoothstep(0.60, 0.92, relHeight);
        heightProfile = baseCut * topDome;
    } else if (genus == GENUS_CUMULONIMBUS) {
        // Cumulonimbus (Mây vũ tích): Giant towering column with huge spreading anvil (incus) at top
        float baseCut = smoothstep(0.02, 0.08, relHeight);
        float body    = 1.0 - smoothstep(0.70, 0.98, relHeight);
        float anvil   = smoothstep(0.68, 0.85, relHeight) * (1.0 - smoothstep(0.92, 1.0, relHeight)) * 1.5;
        heightProfile = baseCut * max(body, anvil);
    } else if (genus == GENUS_STRATOCUMULUS) {
        // Stratocumulus (Mây tầng tích): Low rolling wave sheets, dark flat base
        heightProfile = smoothstep(0.06, 0.20, relHeight) * (1.0 - smoothstep(0.55, 0.85, relHeight));
    } else if (genus == GENUS_STRATUS) {
        // Stratus (Mây tầng): Low uniform blanket near ground
        heightProfile = smoothstep(0.03, 0.15, relHeight) * (1.0 - smoothstep(0.40, 0.65, relHeight));
    } else if (genus == GENUS_NIMBOSTRATUS) {
        // Nimbostratus (Mây vũ tầng): Deep dark light-blocking rain cloud
        heightProfile = smoothstep(0.02, 0.12, relHeight) * (1.0 - smoothstep(0.75, 0.95, relHeight));
    } else if (genus == GENUS_ALTOCUMULUS) {
        // Altocumulus (Mây trung tích): Mid-level fluffy sheep herd layer
        heightProfile = smoothstep(0.25, 0.45, relHeight) * (1.0 - smoothstep(0.65, 0.85, relHeight));
    } else if (genus == GENUS_ALTOSTRATUS) {
        // Altostratus (Mây trung tầng): Translucent watery gray veil
        heightProfile = smoothstep(0.20, 0.38, relHeight) * (1.0 - smoothstep(0.60, 0.78, relHeight));
    } else {
        // Default smooth curve
        heightProfile = smoothstep(0.05, 0.25, relHeight) * (1.0 - smoothstep(0.65, 0.95, relHeight));
    }

    if (heightProfile <= 0.002) return 0.0;

    // 2. Wind drift animation
    vec3 wind = vec3(timeSec * 0.022, 0.0, timeSec * 0.010) * CLOUD_SPEED;
    vec3 p = (worldPos + wind * 40.0) * 0.0016;

    // 3. Macro coverage threshold per genus and weather
    float coverage = 0.50 * CLOUD_COVERAGE;

    if (genus == GENUS_CUMULUS) {
        // Distinct, separated cauliflower puff clusters
        coverage = mix(0.48, 0.60, rain * 0.6) * CLOUD_COVERAGE;
        coverage = mix(coverage * 0.85, coverage * 1.20, saturate(biomeAtm.cloudCoverage - 0.3));
    } else if (genus == GENUS_CUMULONIMBUS) {
        // Massive towering dense thunderhead
        coverage = 0.82 * CLOUD_COVERAGE;
    } else if (genus == GENUS_NIMBOSTRATUS) {
        // Continuous overcast rain sheet
        coverage = 0.88 * CLOUD_COVERAGE;
    } else if (genus == GENUS_STRATOCUMULUS) {
        coverage = 0.62 * CLOUD_COVERAGE;
    } else if (genus == GENUS_ALTOCUMULUS) {
        coverage = 0.55 * CLOUD_COVERAGE;
    } else if (genus == GENUS_ALTOSTRATUS) {
        coverage = 0.70 * CLOUD_COVERAGE;
    } else if (genus == GENUS_STRATUS) {
        coverage = 0.75 * CLOUD_COVERAGE;
    }

    // 4. Perlin-Worley 3D Synthesis: creates natural convective cloud clumps
    float baseFbm = perlinWorley3D(p, 0.20);
    float threshold = 1.0 - coverage;
    if (baseFbm < threshold - 0.05) return 0.0;

    float density = saturate((baseFbm - threshold) / max(coverage, 0.10));
    density *= heightProfile;

    // 5. High-frequency cellular erosion: billowy cauliflower edges
    if (density > 0.02) {
        float detailWorley = 1.0 - worley3D(p * 3.5 + vec3(relHeight * 1.5, 0.0, relHeight * 0.8));
        density = saturate(density - detailWorley * 0.22);
    }

    return density;
}

// True Volumetric 3D Raymarching Cloud Shader (GLSL 120 Compliant)
CloudResult renderVolumetric3DClouds(vec3 rayDir, vec3 sunDir, vec3 moonDir, vec3 upVector, float rain, LightningStrike strike, float timeSec, BiomeAtmosphere biomeAtm) {
    CloudResult res;
    res.color = vec4(0.0);
    res.transmittance = 1.0;

    #ifndef ENABLE_CLOUDS
    return res;
    #endif

    // Clouds only exist above horizon
    if (rayDir.y <= 0.015) return res;

    // Biome check: Desert / Arid clear sky with 0 clouds (unless rain/sandstorm occurs)
    #if CLOUD_WMO_GENUS == 0
    if (biomeAtm.cloudCoverage < 0.10 && rain < 0.05) return res;
    #endif

    int genus = getActiveCloudGenus(rain, strike.intensity, biomeAtm);

    float sunHeight  = dot(sunDir, upVector);
    float moonHeight = dot(moonDir, upVector);
    float cosSun     = dot(rayDir, sunDir);
    float cosMoon    = dot(rayDir, moonDir);

    // Light source colors
    vec3 sunLight  = getSunColor(sunHeight, rain);
    vec3 moonLight = getMoonColor(moonHeight, rain);
    vec3 skyLight  = getAtmosphericFogColor(rayDir, sunDir, moonDir, upVector, rain, strike, biomeAtm) * 0.85;

    // Multiple scattering phase function: isotropic diffuse scattering + forward silver lining + backscatter glory
    #ifdef CLOUD_SILVER_LINING
    float forwardScat = pow(max(cosSun, 0.0), 8.0) * 2.8;
    float backScat    = pow(max(-cosSun, 0.0), 3.0) * 0.45;
    float phaseSun    = 0.52 + forwardScat + backScat;

    float forwardMoon = pow(max(cosMoon, 0.0), 6.0) * 2.0;
    float phaseMoon   = 0.50 + forwardMoon;
    #else
    float phaseSun  = 0.75;
    float phaseMoon = 0.75;
    #endif

    // Cloud slab bounds (altitude in meters)
    float cloudBottom = 200.0;
    float cloudTop    = (genus == GENUS_CUMULONIMBUS) ? 920.0 : ((genus == GENUS_ALTOCUMULUS || genus == GENUS_ALTOSTRATUS) ? 650.0 : 560.0);
    float layerThickness = cloudTop - cloudBottom;

    // Ray intersection with planar slab
    float tStart = cloudBottom / max(rayDir.y, 0.02);
    float tEnd   = cloudTop    / max(rayDir.y, 0.02);
    tEnd = min(tEnd, tStart + 4200.0); // View horizon distance clamp

    float marchDist = tEnd - tStart;
    const int STEPS = VOLUMETRIC_CLOUD_STEPS;
    float stepSize = marchDist / float(STEPS);

    // Optical integration variables
    float transmittance = 1.0;
    vec3 integratedLight = vec3(0.0);

    // Distance fade towards horizon
    float horizonFade = smoothstep(0.015, 0.08, rayDir.y);
    float maxDistFade  = 1.0 - smoothstep(2400.0, 4800.0, tStart);
    float visibility = horizonFade * maxDistFade;

    if (visibility <= 0.01) return res;

    // Moments in Graphics Blue Noise jitter to eliminate raymarch banding
    float jitter = getRaymarchJitter(gl_FragCoord.xy, timeSec);
    vec3 mainLightDir = (sunHeight > -0.05) ? sunDir : moonDir;

    // Primary Volumetric Raymarch Loop (Tier 1: Low, Mid & Vertical Development)
    for (int i = 0; i < STEPS; ++i) {
        if (transmittance < 0.015) break; // Early ray termination

        float t = tStart + stepSize * (float(i) + jitter);
        vec3 pos = rayDir * t;
        float relHeight = saturate((pos.y - cloudBottom) / layerThickness);

        float density = sampleCloudDensity3D(pos, relHeight, genus, rain, timeSec, biomeAtm);

        if (density > 0.008) {
            // Directional light raymarch for self-shadowing and volumetric depth
            #ifdef CLOUD_SHADOWING
            vec3 lightPos = pos + mainLightDir * 36.0;
            float lightRelH = saturate((lightPos.y - cloudBottom) / layerThickness);
            float lightDensity = sampleCloudDensity3D(lightPos, lightRelH, genus, rain, timeSec, biomeAtm);
            
            // Beer-Lambert attenuation along light ray
            float lightTransmittance = exp(-lightDensity * 3.8);
            // Powder-sugar effect: clouds brighten along illuminated rims
            float powder = 1.0 - exp(-density * 4.5);
            float shadow = mix(lightTransmittance * powder, 1.0, 0.18);
            #else
            float shadow = 0.85;
            #endif

            // Direct directional illumination + ambient multiple scattering
            vec3 directSun  = sunLight * shadow * phaseSun * 1.35;
            vec3 directMoon = moonLight * shadow * phaseMoon * 1.35;

            // Ambient sky light bounce (underside of clouds catches ambient atmospheric light)
            vec3 ambientSky = skyLight * mix(0.55, 1.10, relHeight);
            
            // Sunset crimson edge glow
            float sunsetFactor = clamp(1.0 - abs(sunHeight) * 3.5, 0.0, 1.0);
            vec3 sunsetTint = vec3(1.0, 0.52, 0.28) * sunsetFactor * max(cosSun, 0.0) * 1.8;

            vec3 stepRadiance = directSun + directMoon + ambientSky + sunsetTint;

            // Weather rain & thunderstorm lighting adaptation
            if (rain > 0.0) {
                #ifdef DESERT_SANDSTORM
                if (biomeAtm.isArid) {
                    stepRadiance = mix(stepRadiance, vec3(0.68, 0.45, 0.25), rain * 0.85);
                } else
                #endif
                {
                    // Preserve 3D volume shading while darkening for overcast storm
                    vec3 stormTint = mix(vec3(0.45, 0.48, 0.55), vec3(0.18, 0.20, 0.26), rain);
                    stepRadiance *= stormTint * 1.6;
                }

                #ifdef STORM_LIGHTNING
                if (strike.isTriggered && strike.intensity > 0.005) {
                    stepRadiance += evaluateIntraCloudLighting(pos, density, strike, rayDir);
                }
                #endif
            }

            // Beer-Lambert extinction along view ray
            float extinction = 0.035 * CLOUD_DENSITY;
            float stepTransmittance = exp(-density * extinction * stepSize);
            
            // Energy-conserving radiance accumulation
            integratedLight += stepRadiance * (1.0 - stepTransmittance) * transmittance;
            transmittance   *= stepTransmittance;
        }
    }

    // =========================================================================
    // Tier 2: High-Altitude Ice Crystal Genera (Cirrus, Cirrocumulus, Cirrostratus)
    // =========================================================================
    #if CLOUD_LAYERS >= 2
    #if CLOUD_WMO_GENUS > 0
    bool renderHighTier = (genus == GENUS_CIRRUS || genus == GENUS_CIRROCUMULUS || genus == GENUS_CIRROSTRATUS);
    #else
    bool renderHighTier = (genus != GENUS_CUMULONIMBUS && genus != GENUS_NIMBOSTRATUS && genus != GENUS_STRATUS && rain < 0.45 && !biomeAtm.isArid);
    #endif

    if (renderHighTier && transmittance > 0.05) {
        // Spherical atmospheric shell projection (analytically stable 32-bit float)
        // Eliminates planar stretching near zenith & horizon
        float domeH = 8500.0;
        float cirrusT = (2.0 * domeH) / (sqrt(rayDir.y * rayDir.y + 0.002668) + rayDir.y);
        vec2 cirrusXZ = rayDir.xz * cirrusT;
        vec2 windCirrus = vec2(timeSec * 0.038, -timeSec * 0.015) * CLOUD_SPEED;
        vec2 cirrusP = (cirrusXZ + windCirrus * 35.0) * 0.00018;

        float cirrusD = 0.0;

        if (genus == GENUS_CIRROCUMULUS) {
            // Cirrocumulus (Mây ti tích): Bầu trời vảy cá dập dềnh không bóng xám chuẩn WMO
            cirrusD = cirrocumulusRipples2D(cirrusP, rayDir.y) * 0.65 * CLOUD_COVERAGE;
        } else if (genus == GENUS_CIRROSTRATUS) {
            // Cirrostratus (Mây ti tầng): Màng mây mịn màng bao phủ bầu trời
            float veil = fbm2D(cirrusP * 1.5) * 0.4 + 0.35;
            cirrusD = saturate(veil) * 0.40 * CLOUD_COVERAGE;
        } else {
            // Cirrus (Mây ti): Dải lụa trắng tơi xốp, đuôi ngựa vắt ngang vòm trời
            vec2 windDir = normalize(vec2(0.85, -0.52));
            cirrusD = cirrusFilament2D(cirrusP * 2.2, windDir) * 0.50 * CLOUD_COVERAGE;
        }

        cirrusD *= (1.0 - rain * 1.4);

        if (cirrusD > 0.01) {
            vec3 cirrusLight = sunLight * phaseSun * 0.95 + moonLight * phaseMoon * 0.70 + skyLight * 0.60;

            // Optical 22° Halo around Sun & Moon for Cirrostratus ice crystals
            #ifdef CLOUD_ICE_HALO
            if (genus == GENUS_CIRROSTRATUS) {
                // 22° Ice crystal refraction ring (cos(22°) ≈ 0.92718)
                float haloSunDist  = abs(cosSun  - 0.92718);
                float haloMoonDist = abs(cosMoon - 0.92718);
                float haloSun  = exp(-haloSunDist  * haloSunDist  / 0.00045) * 2.2 * max(sunHeight, 0.0);
                float haloMoon = exp(-haloMoonDist * haloMoonDist / 0.00045) * 1.8 * max(moonHeight, 0.0);

                // Chromatic dispersion (red/orange on inner rim, pale blue on outer rim)
                vec3 sunHaloColor  = vec3(1.1, 0.95, 0.82) * haloSun;
                vec3 moonHaloColor = vec3(0.85, 0.95, 1.1) * haloMoon;
                cirrusLight += sunHaloColor + moonHaloColor;
            }
            #endif

            // Sunset golden/crimson illumination on high ice crystals
            float sunsetHigh = clamp(1.0 - abs(sunHeight + 0.04) * 3.5, 0.0, 1.0);
            cirrusLight += vec3(1.0, 0.58, 0.38) * sunsetHigh * 1.4 * max(cosSun, 0.0);

            float cirrusTrans = exp(-cirrusD * 1.2);
            integratedLight += cirrusLight * (1.0 - cirrusTrans) * transmittance;
            transmittance   *= cirrusTrans;
        }
    }
    #endif

    // Apply horizon distance fade to integrated results
    integratedLight *= visibility;
    float finalTransmittance = mix(1.0, transmittance, visibility);
    float finalOpacity = saturate(1.0 - finalTransmittance);

    res.color = vec4(integratedLight, finalOpacity);
    res.transmittance = finalTransmittance;
    return res;
}

// Compatibility wrapper accepting float stormLightning
CloudResult renderVolumetric3DClouds(vec3 rayDir, vec3 sunDir, vec3 moonDir, vec3 upVector, float rain, float stormLightning, float timeSec, BiomeAtmosphere biomeAtm) {
    LightningStrike strike = evaluateLightningState(rain, timeSec);
    return renderVolumetric3DClouds(rayDir, sunDir, moonDir, upVector, rain, strike, timeSec, biomeAtm);
}

#endif // CLOUDS_GLSL
