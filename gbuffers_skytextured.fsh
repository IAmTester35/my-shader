#version 120

varying vec2 texCoord;
varying vec4 vertexColor;
varying vec3 worldPos;

uniform sampler2D texture;
uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 fogColor;
uniform float rainStrength;
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

    float sunHeight = dot(sunDir, WORLD_UP);
    bool isSun = dot(rayDir, sunDir) > dot(rayDir, moonDir);

    // Smoothly interpolated biome climate profile
    BiomeAtmosphere biomeAtm = getSmoothBiomeAtmosphere(biome_category, biome, fogColor);

    // Quad local centered coordinates [-1..1]
    vec2 localCoord = texCoord * 2.0 - 1.0;
    float distToCenter = length(localCoord);

    vec4 finalColor = vec4(0.0);

    if (isSun) {
        // === SUN RENDERING ===
        #ifdef ENABLE_SUN
        finalColor = renderSunBillboard(localCoord, distToCenter, sunHeight, rainStrength, biomeAtm);
        #else
        // Fallback to resource-pack / vanilla sun texture
        finalColor = texture2D(texture, texCoord) * vertexColor;
        #endif
    } else {
        // === MOON RENDERING ===
        #ifdef ENABLE_MOON
        finalColor = renderMoonBillboard(localCoord, distToCenter, sunDir, moonDir, WORLD_UP, moonPhase, sunHeight, rainStrength, biomeAtm);
        #else
        // Fallback to resource-pack / vanilla moon texture
        finalColor = texture2D(texture, texCoord) * vertexColor;
        #endif
    }

    gl_FragColor = finalColor;
}
