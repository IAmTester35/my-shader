#version 120

varying vec2 texCoord;
varying vec2 lmcoord;
varying vec4 vertexColor;
varying vec3 normal;
varying vec3 worldPos;
varying float blockId;

uniform sampler2D texture;
uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 fogColor;
uniform float rainStrength;
uniform float wetness;
uniform float frameTimeCounter;
uniform int biome_category;
uniform int biome;

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/noise.glsl"
#include "lib/biome.glsl"
#include "lib/atmosphere.glsl"
#include "lib/weather.glsl"
#include "lib/fire.glsl"

void main() {
    vec4 albedo = texture2D(texture, texCoord) * vertexColor;
    if (albedo.a < 0.1) discard;

    // Detect fire or soul fire via block ID and spectral signature fallback
    int bId = int(blockId + 0.5);
    bool isFireBlock = (bId == 10001);
    bool isSoulFireBlock = (bId == 10002);

    bool isSpectralFire = (lmcoord.x > 0.82 && albedo.r > 0.70 && albedo.g > 0.25 && albedo.b < 0.35 && (albedo.r - albedo.b > 0.35));
    bool isSpectralSoulFire = (lmcoord.x > 0.65 && albedo.b > 0.65 && albedo.g > 0.40 && albedo.r < 0.40);

    bool isFire = isFireBlock || isSpectralFire;
    bool isSoulFire = isSoulFireBlock || isSpectralSoulFire;

    #ifdef CINEMATIC_FIRE
    if (isFire || isSoulFire) {
        vec4 shadedFire = shadeBlockFire(albedo, texCoord, worldPos, frameTimeCounter, isSoulFire);
        gl_FragColor = shadedFire;
        return;
    }
    #endif

    vec3 sunDir = getSunDirWorld(sunPosition, gbufferModelViewInverse);
    vec3 moonDir = getMoonDirWorld(moonPosition, gbufferModelViewInverse);

    float sunHeight  = dot(sunDir, WORLD_UP);
    float moonHeight = dot(moonDir, WORLD_UP);
    float stormLightning = getStormLightningFlash(rainStrength, frameTimeCounter);

    // Smooth biome transition
    BiomeAtmosphere biomeAtm = getSmoothBiomeAtmosphere(biome_category, biome, fogColor);

    // Darken wet surfaces when exposed to rain (smoothly disabled in deserts)
    albedo.rgb = applyWetnessToAlbedo(albedo.rgb, wetness * lmcoord.y, biomeAtm);

    // Directional sunlight and moonlight
    float NdotSun  = max(dot(normal, sunDir), 0.0);
    float NdotMoon = max(dot(normal, moonDir), 0.0);

    vec3 sunLight  = getSunColor(sunHeight, rainStrength) * NdotSun;
    vec3 moonLight = getMoonColor(moonHeight, rainStrength) * NdotMoon;

    float skyExposure = smoothstep(0.70, 1.0, lmcoord.y);
    vec3 directLight = (sunLight + moonLight) * skyExposure;

    // Ambient lighting matching atmospheric sky color & smooth biome
    vec3 skyAmbient = getAtmosphericFogColor(normal, sunDir, moonDir, WORLD_UP, rainStrength, stormLightning, biomeAtm);
    skyAmbient *= (0.22 + 0.40 * lmcoord.y);

    // Warm block light (torches, lanterns)
    vec3 torchLight = vec3(1.0, 0.65, 0.30) * pow(lmcoord.x, 1.8) * 1.5;

    // Base eye adaptation minimum ambient
    vec3 minAmbient = vec3(0.04, 0.045, 0.06);

    #ifdef STORM_LIGHTNING
    if (stormLightning > 0.005) {
        LightningStrike strike = evaluateLightningState(rainStrength, frameTimeCounter);
        if (strike.isTriggered && strike.intensity > 0.005) {
            vec3 strikeLightDir = normalize(strike.strikeDir + vec3(0.0, 0.45, 0.0));
            float NdotStrike = max(dot(normal, strikeLightDir), 0.0);
            float upward = max(dot(normal, WORLD_UP) * 0.5 + 0.5, 0.0);
            float strikeDiffuse = mix(upward, NdotStrike, 0.65);
            directLight += (strike.coreColor * 0.08 + strike.sheathColor * 1.5) * strike.intensity * strikeDiffuse * skyExposure * 2.2;
        }
    }
    #endif

    vec3 finalLight = directLight + skyAmbient + torchLight + minAmbient;
    gl_FragColor = vec4(albedo.rgb * finalLight, albedo.a);
}
