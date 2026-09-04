#version 120

varying vec2 texCoord;
varying vec2 lmcoord;
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
    vec3 upVector = normalize(upPosition);

    float sunHeight = dot(sunDir, upVector);
    float moonHeight = dot(moonDir, upVector);
    float stormLightning = getStormLightningFlash(rainStrength, frameTimeCounter);

    // Smooth biome transition
    BiomeAtmosphere biomeAtm = getSmoothBiomeAtmosphere(biome_category, biome, fogColor);

    // Light colors from celestial bodies & sky
    vec3 sunLight  = getSunColor(sunHeight, rainStrength);
    vec3 moonLight = getMoonColor(moonHeight, rainStrength);
    vec3 skyLight  = getAtmosphericFogColor(normalize(worldPos), sunDir, moonDir, upVector, rainStrength, stormLightning, biomeAtm);

    // Lightmap brightness (sky light & torch light)
    float skyLightmap   = clamp(lmcoord.y * 1.1, 0.0, 1.0);
    float blockLightmap = clamp(lmcoord.x * 1.2, 0.0, 1.0);
    vec3 torchLightColor = vec3(1.0, 0.65, 0.3) * blockLightmap * 1.5;

    // Ambient raindrop illumination with optical forward scattering (glistening when facing sun/moon)
    vec3 particleDir = normalize(worldPos);
    float cosSun  = max(dot(particleDir, sunDir), 0.0);
    float cosMoon = max(dot(particleDir, moonDir), 0.0);
    float forwardSun  = 1.0 + pow(cosSun, 6.0) * 3.5;
    float forwardMoon = 1.0 + pow(cosMoon, 4.0) * 2.0;

    vec3 ambient = skyLight * skyLightmap * 0.8 + torchLightColor;
    vec3 directLight = (sunLight * forwardSun + moonLight * forwardMoon) * skyLightmap;
    vec3 totalLight = ambient + directLight;

    #ifdef STORM_LIGHTNING
    if (stormLightning > 0.01) {
        totalLight += vec3(0.9, 0.95, 1.15) * stormLightning * 2.5 * skyLightmap;
    }
    #endif

    vec4 shadedParticle = shadeRainParticle(tex, totalLight, frameTimeCounter, biomeAtm);
    gl_FragColor = shadedParticle;
}
