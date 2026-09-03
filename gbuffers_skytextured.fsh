#version 120

varying vec2 texCoord;
varying vec4 vertexColor;
varying vec3 worldPos;

uniform sampler2D texture;
uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform vec3 fogColor;
uniform float rainStrength;
uniform float frameTimeCounter;
uniform int moonPhase;
uniform int biome_category;
uniform int biome;

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/noise.glsl"
#include "lib/biome.glsl"
#include "lib/atmosphere.glsl"
#include "lib/celestials.glsl"

void main() {
    vec3 rayDir = normalize(worldPos);
    vec3 sunDir = getSunDirWorld(sunPosition, gbufferModelViewInverse);
    vec3 moonDir = getMoonDirWorld(moonPosition, gbufferModelViewInverse);
    vec3 upVector = normalize(upPosition);

    float sunHeight = dot(sunDir, upVector);
    float dotSun  = dot(rayDir, sunDir);
    float dotMoon = dot(rayDir, moonDir);

    // Smoothly interpolated biome climate profile
    BiomeAtmosphere biomeAtm = getSmoothBiomeAtmosphere(biome_category, biome, fogColor);

    vec4 finalColor = vec4(0.0);

    // Quad local centered coordinates [-1..1]
    vec2 localCoord = texCoord * 2.0 - 1.0;
    float distToCenter = length(localCoord);

    if (dotSun > dotMoon) {
        // === SUN RENDERING ===
        #ifdef ENABLE_SUN
        if (rainStrength < 0.95 && sunHeight > -0.18) {
            vec3 noonColor    = vec3(1.00, 0.98, 0.94) * 5.2;
            vec3 sunsetColor  = vec3(1.00, 0.45, 0.08) * 4.2;
            vec3 horizonColor = vec3(0.96, 0.16, 0.02) * 3.4;

            if (biomeAtm.isArid) {
                sunsetColor = mix(sunsetColor, vec3(1.00, 0.32, 0.04) * 4.4, biomeAtm.sandstormFactor);
            }

            float sunsetT  = clamp(1.0 - sunHeight * 4.0, 0.0, 1.0);
            float horizonT = clamp(-sunHeight * 8.0 + 0.4, 0.0, 1.0);
            vec3 currentSunColor = mix(noonColor, sunsetColor, sunsetT);
            currentSunColor = mix(currentSunColor, horizonColor, horizonT);

            float discRadius = 0.65 * SUN_SIZE;
            vec3 sunEmission = vec3(0.0);
            float alpha = 0.0;

            // 1. Sharp solar disc with limb darkening
            if (distToCenter < discRadius) {
                float r = distToCenter / discRadius;
                #ifdef SUN_LIMB_DARKENING
                float mu = sqrt(max(1.0 - r * r, 0.0));
                float limbDarkening = 0.35 + 0.65 * pow(mu, 0.65);
                #else
                float limbDarkening = 1.0;
                #endif
                float edgeAA = smoothstep(1.0, 0.94, r);
                sunEmission += currentSunColor * limbDarkening * edgeAA;
                alpha = max(alpha, edgeAA);
            }

            // 2. Solar Corona (intense inner glow)
            if (SUN_CORONA_INTENSITY > 0.001) {
                float coronaGlow = exp(-distToCenter * 4.0) * SUN_CORONA_INTENSITY * 0.85;
                sunEmission += currentSunColor * coronaGlow;
                alpha = max(alpha, clamp(coronaGlow, 0.0, 1.0));
            }

            // 3. Wide solar glare halo
            #ifdef SUN_GLARE
            float glare = 0.25 / (1.0 + distToCenter * distToCenter * 6.0) * biomeAtm.hazeDensity;
            sunEmission += currentSunColor * glare;
            alpha = max(alpha, clamp(glare, 0.0, 1.0));
            #endif

            // 4. Solar diffraction starburst spikes
            #ifdef SOLAR_DIFFRACTION_SPIKES
            vec2 rotCoord = vec2(localCoord.x + localCoord.y, localCoord.x - localCoord.y) * 0.7071;
            float sp1 = exp(-abs(rotCoord.x) * 12.0) / (abs(rotCoord.y) * 2.0 + 1.0);
            float sp2 = exp(-abs(rotCoord.y) * 12.0) / (abs(rotCoord.x) * 2.0 + 1.0);
            float spike = (sp1 + sp2) * exp(-distToCenter * 2.5) * 0.45;
            sunEmission += currentSunColor * spike;
            alpha = max(alpha, clamp(spike, 0.0, 1.0));
            #endif

            sunEmission *= (1.0 - rainStrength * 0.90);
            finalColor = vec4(sunEmission, alpha * (1.0 - rainStrength * 0.90));
        }
        #endif
    } else {
        // === MOON RENDERING ===
        #ifdef ENABLE_MOON
        if (rainStrength < 0.92 && sunHeight < 0.18) {
            float nightFactor = clamp(-sunHeight * 8.0, 0.0, 1.0);
            float discRadius = 0.65 * MOON_SIZE;
            vec3 moonBaseColor = vec3(0.90, 0.94, 1.0);
            vec3 moonEmission = vec3(0.0);
            float alpha = 0.0;

            if (distToCenter < discRadius) {
                float r = distToCenter / discRadius;
                float edgeAA = smoothstep(1.0, 0.93, r);

                float normalZ = sqrt(max(1.0 - r * r, 0.0));
                vec3 sphereNormal = vec3(localCoord / discRadius, normalZ);

                // Detailed lunar maria & crater ejecta rays
                #ifdef MOON_SURFACE_DETAIL
                vec2 surfaceUV = (localCoord / discRadius) * 1.5 + vec2(1.2, 0.8);
                float maria = fbm2D_Detailed(surfaceUV * 2.4);
                float craterRays = voronoi2D(surfaceUV * 4.2);
                float albedo = mix(0.52, 1.08, smoothstep(0.36, 0.70, maria));
                albedo += (1.0 - smoothstep(0.0, 0.12, craterRays)) * 0.28;
                #else
                float albedo = 1.0;
                #endif

                // 8-Phase lunar cycle
                #ifdef MOON_PHASES
                float phaseAngle = float(moonPhase) * (TWO_PI / 8.0);
                vec3 phaseLightDir = normalize(vec3(-sin(phaseAngle), 0.0, cos(phaseAngle)));
                float NdotL = dot(sphereNormal, phaseLightDir);
                float illumination = smoothstep(-0.06, 0.06, NdotL);

                #ifdef MOON_EARTHSHINE
                illumination += 0.05 * (1.0 - illumination);
                #endif
                #else
                float illumination = 1.0;
                #endif

                moonEmission += moonBaseColor * albedo * illumination * 2.6 * edgeAA;
                alpha = max(alpha, edgeAA);
            }

            // Lunar atmospheric halo / ice crystal ring (smoothly blended in cold biomes)
            #ifdef MOON_HALO
            float haloGlow = exp(-distToCenter * 2.8) * 0.30 * MOON_HALO_INTENSITY;
            haloGlow *= mix(1.0, 1.8, biomeAtm.auroraStrength / 1.8);
            vec3 haloColor = vec3(0.55, 0.72, 1.0);
            moonEmission += haloColor * haloGlow;
            alpha = max(alpha, clamp(haloGlow * 1.5, 0.0, 1.0));
            #endif

            moonEmission *= nightFactor * (1.0 - rainStrength * 0.90);
            finalColor = vec4(moonEmission, alpha * nightFactor * (1.0 - rainStrength * 0.90));
        }
        #endif
    }

    gl_FragColor = finalColor;
}
