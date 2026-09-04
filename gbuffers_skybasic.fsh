#version 120

varying vec3 worldPos;

uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 fogColor;
uniform float rainStrength;
uniform float frameTimeCounter;
uniform int worldTime;
uniform int biome_category;
uniform int biome;

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/noise.glsl"
#include "lib/biome.glsl"
#include "lib/atmosphere.glsl"
#include "lib/celestials.glsl"
#include "lib/weather.glsl"

void main() {
    vec3 rayDir = normalize(worldPos);
    vec3 sunDir = getSunDirWorld(sunPosition, gbufferModelViewInverse);
    vec3 moonDir = getMoonDirWorld(moonPosition, gbufferModelViewInverse);

    float sunHeight = dot(sunDir, WORLD_UP);
    float stormLightning = getStormLightningFlash(rainStrength, frameTimeCounter);
    float stormAzimuth = getStormLightningAzimuth(frameTimeCounter);

    // Smoothly interpolated biome climate profile (continuous transition across borders)
    BiomeAtmosphere biomeAtm = getSmoothBiomeAtmosphere(biome_category, biome, fogColor);

    // 1. Rayleigh, Mie & Ozone atmospheric sky gradient with smoothly blended biome tint
    vec3 skyColor = calculateAtmosphericSky(rayDir, sunDir, moonDir, WORLD_UP, rainStrength, stormLightning, stormAzimuth, biomeAtm);

    // 2. Stars, Milky Way Galaxy band, Meteors, and Multi-Layer Aurora Borealis (NASA SVS 4851)
    vec3 stars = renderStarsAndMilkyWay(rayDir, sunHeight, rainStrength, frameTimeCounter, worldTime, biomeAtm);
    skyColor += stars;

    gl_FragColor = vec4(skyColor, 1.0);
}
