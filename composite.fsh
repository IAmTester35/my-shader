#version 120

varying vec2 texCoord;

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform vec3 fogColor;
uniform float rainStrength;
uniform float frameTimeCounter;
uniform float near;
uniform float far;
uniform int biome_category;
uniform int biome;

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/noise.glsl"
#include "lib/biome.glsl"
#include "lib/atmosphere.glsl"
#include "lib/clouds.glsl"
#include "lib/weather.glsl"

void main() {
    vec4 sceneColor = texture2D(colortex0, texCoord);
    float depth = texture2D(depthtex0, texCoord).r;

    vec3 sunDir = getSunDirWorld(sunPosition, gbufferModelViewInverse);
    vec3 moonDir = getMoonDirWorld(moonPosition, gbufferModelViewInverse);
    vec3 upVector = normalize(upPosition);

    float sunHeight = dot(sunDir, upVector);
    float stormLightning = getStormLightningFlash(rainStrength, frameTimeCounter);

    // Smooth continuous biome transition across chunk boundaries
    BiomeAtmosphere biomeAtm = getSmoothBiomeAtmosphere(biome_category, biome, fogColor);

    // Reconstruct world ray direction for current screen pixel
    vec3 rayDir = getScreenRayDir(texCoord, gbufferProjectionInverse, gbufferModelViewInverse);

    vec3 finalColor = sceneColor.rgb;

    if (depth >= 0.9999) {
        // === SKY PIXELS ===
        // True Volumetric 3D Raymarched Clouds with smoothly blended biome adaptations
        CloudResult clouds = renderVolumetric3DClouds(rayDir, sunDir, moonDir, upVector, rainStrength, stormLightning, frameTimeCounter, biomeAtm);
        finalColor = mix(finalColor, clouds.color.rgb, clouds.color.a);
    } else {
        // === TERRAIN & WORLD PIXELS ===
        vec3 viewPos = screenToView(texCoord, depth, gbufferProjectionInverse);
        float distanceToCam = length(viewPos);

        // Biome-aware atmospheric fog color
        vec3 fogAtmColor = getAtmosphericFogColor(rayDir, sunDir, moonDir, upVector, rainStrength, stormLightning, biomeAtm);

        // Distance fog & rain/sandstorm weather fog
        float baseFog = 1.0 - exp(-distanceToCam * 0.0012 * biomeAtm.hazeDensity);
        float rainFog = calculateRainFogFactor(distanceToCam, rainStrength, biomeAtm);
        float totalFog = max(baseFog, rainFog);

        finalColor = mix(finalColor, fogAtmColor, saturate(totalFog));
    }

    // === GOD RAYS / CREPUSCULAR LIGHT SHAFTS (Sun & Moon) ===
    #ifdef GODRAYS
    if (rainStrength < 0.85) {
        bool useSun = (sunHeight > -0.08);
        vec3 lightPosEye = useSun ? sunPosition : moonPosition;
        float lightHeight = useSun ? sunHeight : dot(moonDir, upVector);

        if (lightPosEye.z < 0.0 && lightHeight > -0.10) {
            vec4 lightClip = gbufferProjection * vec4(lightPosEye, 1.0);
            vec3 lightNDC = lightClip.xyz / lightClip.w;
            vec2 lightUV = lightNDC.xy * 0.5 + 0.5;

            if (lightUV.x >= -0.3 && lightUV.x <= 1.3 && lightUV.y >= -0.3 && lightUV.y <= 1.3) {
                vec2 deltaUV = (lightUV - texCoord) / 16.0;
                // Screen-space Blue Noise jitter (Moments in Graphics) to eliminate stepping and white-noise grain
                float jitter = getRaymarchJitter(gl_FragCoord.xy, frameTimeCounter);
                vec2 sampleCoord = texCoord + deltaUV * jitter;

                float rayDensity = 0.0;
                float decay = 1.0;

                for (int i = 0; i < 16; ++i) {
                    sampleCoord += deltaUV;
                    float d = texture2D(depthtex0, sampleCoord).r;
                    if (d >= 0.9999) {
                        rayDensity += decay;
                    }
                    decay *= 0.87;
                }

                rayDensity /= 16.0;

                float edgeFade = smoothstep(-0.2, 0.1, lightUV.x) * smoothstep(1.2, 0.9, lightUV.x) *
                                 smoothstep(-0.2, 0.1, lightUV.y) * smoothstep(1.2, 0.9, lightUV.y);

                vec3 godrayColor;
                if (useSun) {
                    godrayColor = getSunColor(sunHeight, rainStrength);
                    if (biomeAtm.isArid) godrayColor = mix(godrayColor, godrayColor * vec3(1.1, 0.85, 0.65), biomeAtm.sandstormFactor);
                } else {
                    godrayColor = getMoonColor(lightHeight, rainStrength) * 1.8;
                }

                finalColor += godrayColor * rayDensity * edgeFade * 0.55 * GODRAYS_INTENSITY;
            }
        }
    }
    #endif

    gl_FragColor = vec4(finalColor, sceneColor.a);
}
