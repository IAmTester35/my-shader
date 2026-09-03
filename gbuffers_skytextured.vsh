#version 120

varying vec2 texCoord;
varying vec4 vertexColor;
varying vec3 worldPos;

uniform mat4 gbufferModelViewInverse;

void main() {
    gl_Position = ftransform();
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vertexColor = gl_Color;

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    worldPos = (gbufferModelViewInverse * viewPos).xyz;
}
