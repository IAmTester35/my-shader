#version 120

varying vec2 texCoord;

uniform sampler2D colortex0;

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/tonemap.glsl"

void main() {
    vec4 sceneColor = texture2D(colortex0, texCoord);
    vec3 postProcessed = applyPostProcessing(sceneColor.rgb, texCoord);
    gl_FragColor = vec4(postProcessed, 1.0);
}
