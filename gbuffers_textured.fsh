#version 120

varying vec2 texCoord;
varying vec4 vertexColor;

uniform sampler2D texture;
uniform float frameTimeCounter;
uniform float viewWidth;
uniform float viewHeight;

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/noise.glsl"
#include "lib/fire.glsl"

void main() {
    vec4 tex = texture2D(texture, texCoord) * vertexColor;
    if (tex.a < 0.05) discard;

    // Detect if this is the vanilla screen fire overlay quad
    bool isScreenFire = (tex.r > 0.65 && tex.g > 0.20 && tex.b < 0.35 && (tex.r - tex.b > 0.35));

    #ifdef CINEMATIC_SCREEN_FIRE
    if (isScreenFire) {
        vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
        vec4 vignette = renderScreenFireVignette(screenUV, frameTimeCounter);
        if (vignette.a < 0.01) discard;
        gl_FragColor = vignette;
        return;
    }
    #endif

    gl_FragColor = tex;
}
