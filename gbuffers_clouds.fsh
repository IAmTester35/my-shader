#version 120

varying vec4 vertexColor;
varying vec2 texCoord;

uniform sampler2D texture;

#include "lib/settings.glsl"

void main() {
    #ifdef ENABLE_CLOUDS
    // Procedural volumetric clouds are rendered in composite pass
    discard;
    #else
    // Fallback to vanilla clouds if procedural clouds are disabled
    vec4 col = texture2D(texture, texCoord) * vertexColor;
    if (col.a < 0.1) discard;
    gl_FragColor = col;
    #endif
}
