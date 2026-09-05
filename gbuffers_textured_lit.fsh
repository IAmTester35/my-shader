#version 120

varying vec2 texCoord;
varying vec2 lmcoord;
varying vec4 vertexColor;

uniform sampler2D texture;
uniform float frameTimeCounter;

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/noise.glsl"
#include "lib/fire.glsl"

void main() {
    vec4 tex = texture2D(texture, texCoord) * vertexColor;
    if (tex.a < 0.05) discard;

    // Detect flame particles (torch flame, campfire flame, soul flame)
    bool isNormalFlame = (lmcoord.x > 0.80 && tex.r > 0.70 && tex.g > 0.25 && tex.b < 0.35 && (tex.r - tex.b > 0.35));
    bool isSoulFlame   = (lmcoord.x > 0.65 && tex.b > 0.65 && tex.g > 0.40 && tex.r < 0.40);

    #ifdef CINEMATIC_FIRE
    if (isNormalFlame || isSoulFlame) {
        float intensity = max(tex.r, max(tex.g, tex.b));
        vec3 flameHDR = isSoulFlame ? getSoulFirePlasmaColor(intensity) : getBlackbodyFlameColor(intensity);
        gl_FragColor = vec4(flameHDR, tex.a);
        return;
    }
    #endif

    // Normal particle lighting with lightmap
    vec3 blockLight = vec3(1.0, 0.65, 0.30) * pow(lmcoord.x, 1.6) * 1.3;
    vec3 skyLight   = vec3(0.5, 0.6, 0.75) * lmcoord.y;
    vec3 totalLight = blockLight + skyLight + vec3(0.12);

    gl_FragColor = vec4(tex.rgb * totalLight, tex.a);
}
