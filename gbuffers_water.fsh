#version 120

varying vec2 texCoord;
varying vec2 lmcoord;
varying vec4 vertexColor;
varying vec3 normal;
varying vec3 worldPos;

uniform sampler2D texture;
uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 fogColor;
uniform float rainStrength;
uniform float frameTimeCounter;
uniform int biome_category;
uniform int biome;

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/noise.glsl"
#include "lib/biome.glsl"
#include "lib/atmosphere.glsl"
#include "lib/weather.glsl"

void main() {
    vec4 tex = texture2D(texture, texCoord) * vertexColor;
    if (tex.a < 0.05) discard;

    vec3 sunDir = getSunDirWorld(sunPosition, gbufferModelViewInverse);
    vec3 moonDir = getMoonDirWorld(moonPosition, gbufferModelViewInverse);

    float sunHeight  = dot(sunDir, WORLD_UP);
    float moonHeight = dot(moonDir, WORLD_UP);
    float stormLightning = getStormLightningFlash(rainStrength, frameTimeCounter);
    float stormAzimuth = getStormLightningAzimuth(frameTimeCounter);

    // Smooth biome transition
    BiomeAtmosphere biomeAtm = getSmoothBiomeAtmosphere(biome_category, biome, fogColor);

    // Procedural animated surface waves
    vec2 waveCoord = worldPos.xz * 0.45;
    float t = frameTimeCounter * 1.2;
    float w1 = sin(waveCoord.x * 2.2 + waveCoord.y * 1.5 + t) * 0.06;
    float w2 = cos(-waveCoord.x * 1.8 + waveCoord.y * 2.6 + t * 0.8) * 0.06;
    vec3 waveNormal = normalize(normal + vec3(w1, 0.0, w2));

    vec3 viewDir = normalize(-worldPos);
    float NdotV = clamp(dot(waveNormal, viewDir), 0.0, 1.0);

    float F0 = 0.04;
    float fresnel = F0 + (1.0 - F0) * pow(1.0 - NdotV, 5.0);

    // Sky and sun reflections with smoothly blended biome atmospheric coloring
    vec3 reflectDir = reflect(-viewDir, waveNormal);
    vec3 reflectedSky = calculateAtmosphericSky(reflectDir, sunDir, moonDir, WORLD_UP, rainStrength, stormLightning, stormAzimuth, biomeAtm);

    // Specular sun glint
    vec3 sunHalf = normalize(viewDir + sunDir);
    float sunSpec = pow(max(dot(waveNormal, sunHalf), 0.0), 160.0);
    vec3 sunSpecularLight = getSunColor(sunHeight, rainStrength) * sunSpec * 6.5;

    // Specular moon glint
    vec3 moonHalf = normalize(viewDir + moonDir);
    float moonSpec = pow(max(dot(waveNormal, moonHalf), 0.0), 100.0);
    vec3 moonSpecularLight = getMoonColor(moonHeight, rainStrength) * moonSpec * 3.2;

    vec3 waterBodyColor = mix(vec3(0.06, 0.22, 0.38) * biomeAtm.fogTint, tex.rgb, 0.45);
    vec3 waterLit = waterBodyColor * (0.3 + 0.7 * lmcoord.y);

    vec3 finalWater = mix(waterLit, reflectedSky, fresnel * 0.85);
    finalWater += (sunSpecularLight + moonSpecularLight) * lmcoord.y;

    gl_FragColor = vec4(finalWater, max(tex.a, fresnel * 0.65));
}
