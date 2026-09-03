#ifndef CLOUDS_GLSL
#define CLOUDS_GLSL

#include "settings.glsl"
#include "common.glsl"
#include "noise.glsl"
#include "atmosphere.glsl"
#include "biome.glsl"

/*
 * ==============================================================================
 *  TRUE VOLUMETRIC 3D RAYMARCHED CLOUDS (HIGH-END PC EDITION)
 *  Physical Beer-Lambert law, dual-lobe phase scattering, powder-sugar effect,
 *  and biome-specific cloud formations
 * ==============================================================================
 */

struct CloudResult {
    vec4 color;       // rgb = integrated radiance, a = optical opacity (1.0 - transmittance)
};

// 3D Cloud Density Evaluation Function
float sampleCloudDensity3D(vec3 worldPos, float relHeight, float rain, float timeSec, BiomeAtmosphere biomeAtm) {
    // Height gradient: smooth bell-shaped curve peaking at ~35-45% of cloud layer
    float heightGradient = smoothstep(0.0, 0.25, relHeight) * (1.0 - smoothstep(0.65, 1.0, relHeight));
    if (heightGradient <= 0.001) return 0.0;

    // Wind drift offset
    vec3 wind = vec3(timeSec * 0.018, 0.0, timeSec * 0.008) * CLOUD_SPEED;
    vec3 p = (worldPos + wind * 40.0) * 0.0018;

    // Base fractal shape (Low-frequency 3D noise)
    float baseFbm = fbm3D(p);
    
    // Coverage threshold adapted to biome and rain
    float baseCoverage = mix(0.48 / CLOUD_DENSITY, 0.20, rain * 0.85);
    baseCoverage = mix(baseCoverage * 1.4, baseCoverage * 0.75, saturate(biomeAtm.cloudCoverage - 0.5));

    float density = smoothstep(baseCoverage, baseCoverage + 0.35, baseFbm);
    density *= heightGradient;

    // High-frequency erosion detail (adds billowy wisps and fluffy edges)
    if (density > 0.02) {
        float detailFbm = fbm2D(p.xz * 4.5 + vec2(relHeight * 2.0, 0.0));
        density = saturate(density - (1.0 - detailFbm) * 0.28);
    }

    return density;
}

// True Volumetric 3D Raymarching Cloud Shader
CloudResult renderVolumetric3DClouds(vec3 rayDir, vec3 sunDir, vec3 moonDir, vec3 upVector, float rain, float stormLightning, float timeSec, BiomeAtmosphere biomeAtm) {
    CloudResult res;
    res.color = vec4(0.0);

    #ifndef ENABLE_CLOUDS
    return res;
    #endif

    // Clouds only exist above horizon
    if (rayDir.y <= 0.02) return res;

    // Biome check: Desert with 0 clouds
    if (biomeAtm.cloudCoverage < 0.1 && rain < 0.1) return res;

    float sunHeight  = dot(sunDir, upVector);
    float moonHeight = dot(moonDir, upVector);
    float cosSun     = dot(rayDir, sunDir);
    float cosMoon    = dot(rayDir, moonDir);

    // Light colors
    vec3 sunLight  = getSunColor(sunHeight, rain);
    vec3 moonLight = getMoonColor(moonHeight, rain);
    vec3 skyLight  = getAtmosphericFogColor(rayDir, sunDir, moonDir, upVector, rain, stormLightning, biomeAtm) * 0.75;

    // Dual-lobe Henyey-Greenstein phase function (silver lining forward scattering + backscattering)
    #ifdef CLOUD_SILVER_LINING
    float phaseSun  = dualHgPhase(cosSun, 0.78, -0.25, 0.70) * 2.2;
    float phaseMoon = dualHgPhase(cosMoon, 0.70, -0.20, 0.70) * 1.5;
    #else
    float phaseSun = 1.0;
    float phaseMoon = 1.0;
    #endif

    // Cloud slab bounds (altitude in meters/blocks)
    float cloudBottom = 240.0;
    float cloudTop    = 520.0;
    float layerThickness = cloudTop - cloudBottom;

    // Ray intersection with planar slab
    float tStart = cloudBottom / max(rayDir.y, 0.02);
    float tEnd   = cloudTop    / max(rayDir.y, 0.02);
    tEnd = min(tEnd, tStart + 3600.0); // Clamp maximum view distance

    float marchDist = tEnd - tStart;
    const int STEPS = VOLUMETRIC_CLOUD_STEPS;
    float stepSize = marchDist / float(STEPS);

    // Optical integration variables
    float transmittance = 1.0;
    vec3 integratedLight = vec3(0.0);

    // Distance fade towards horizon
    float horizonFade = smoothstep(0.02, 0.12, rayDir.y);
    float maxDistFade  = 1.0 - smoothstep(1800.0, 4200.0, tStart);
    float visibility = horizonFade * maxDistFade;

    if (visibility <= 0.01) return res;

    // Volumetric Raymarch Loop
    for (int i = 0; i < STEPS; ++i) {
        if (transmittance < 0.02) break; // Early ray termination

        // Moments in Graphics Blue Noise jitter along view ray to eliminate slice banding
        float jitter = getRaymarchJitter(gl_FragCoord.xy, timeSec);
        float t = tStart + stepSize * (float(i) + jitter);
        vec3 pos = rayDir * t;
        float relHeight = saturate((pos.y - cloudBottom) / layerThickness);

        float density = sampleCloudDensity3D(pos, relHeight, rain, timeSec, biomeAtm);

        if (density > 0.005) {
            // Secondary light ray march towards the sun for self-shadowing
            #ifdef CLOUD_SHADOWING
            vec3 lightPos = pos + sunDir * 28.0;
            float lightRelH = saturate((lightPos.y - cloudBottom) / layerThickness);
            float lightDensity = sampleCloudDensity3D(lightPos, lightRelH, rain, timeSec, biomeAtm);
            
            // Beer-Lambert attenuation along light ray
            float lightTransmittance = exp(-lightDensity * 3.5);
            // Powder-sugar effect: clouds brighten around edges and avoid pitch black interiors
            float powder = 1.0 - exp(-density * 4.0);
            float shadow = mix(lightTransmittance * powder, 1.0, 0.18);
            #else
            float shadow = 0.85;
            #endif

            // Directional scattering + ambient multiple scattering
            vec3 directSun  = sunLight * shadow * phaseSun;
            vec3 directMoon = moonLight * shadow * phaseMoon;
            
            // Sunset crimson edge glow
            float sunsetFactor = clamp(1.0 - abs(sunHeight) * 4.0, 0.0, 1.0);
            vec3 sunsetTint = vec3(1.0, 0.52, 0.32) * sunsetFactor * max(cosSun, 0.0);

            vec3 stepRadiance = directSun + directMoon + skyLight + sunsetTint;

            // Weather rain & storm darkening
            if (rain > 0.0) {
                #ifdef DESERT_SANDSTORM
                if (biomeAtm.isArid) {
                    stepRadiance = mix(stepRadiance, vec3(0.65, 0.42, 0.22), rain * 0.90);
                } else {
                    stepRadiance = mix(stepRadiance, vec3(0.18, 0.20, 0.24), rain * 0.88);
                }
                #else
                stepRadiance = mix(stepRadiance, vec3(0.18, 0.20, 0.24), rain * 0.88);
                #endif

                #ifdef STORM_LIGHTNING
                if (stormLightning > 0.01) {
                    stepRadiance += vec3(0.92, 0.96, 1.15) * stormLightning * 3.2;
                }
                #endif
            }

            // Beer-Lambert extinction along view ray
            float extinction = 0.08 * CLOUD_DENSITY;
            float stepTransmittance = exp(-density * extinction * stepSize * 0.025);
            
            // Energy-conserving radiance integration
            integratedLight += stepRadiance * (1.0 - stepTransmittance) * transmittance;
            transmittance   *= stepTransmittance;
        }
    }

    // High-altitude cirrus layer (Layer 2)
    #if CLOUD_LAYERS >= 2
    if (rain < 0.65 && !biomeAtm.isArid) {
        float cirrusH = 580.0;
        float cirrusT = cirrusH / max(rayDir.y, 0.02);
        vec2 cirrusXZ = rayDir.xz * cirrusT;
        vec2 windCirrus = vec2(timeSec * 0.035, -timeSec * 0.012) * CLOUD_SPEED;
        float cirrusNoise = fbm2D((cirrusXZ + windCirrus * 30.0) * 0.0007);
        float cirrusD = smoothstep(0.50, 0.80, cirrusNoise) * 0.32 * (1.0 - rain * 1.5);

        if (cirrusD > 0.01) {
            vec3 cirrusLight = sunLight * 0.95 + moonLight * 0.7 + skyLight * 0.5;
            integratedLight += cirrusLight * cirrusD * transmittance;
            transmittance   *= (1.0 - cirrusD);
        }
    }
    #endif

    float finalOpacity = saturate((1.0 - transmittance) * visibility);
    res.color = vec4(integratedLight, finalOpacity);
    return res;
}

#endif // CLOUDS_GLSL
