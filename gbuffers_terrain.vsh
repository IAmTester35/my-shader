#version 120

varying vec2 texCoord;
varying vec2 lmcoord;
varying vec4 vertexColor;
varying vec3 normal;

uniform mat4 gbufferModelViewInverse;

void main() {
    gl_Position = ftransform();
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vertexColor = gl_Color;
    
    // Normal in eye space converted to world space
    normal = normalize((gbufferModelViewInverse * vec4(gl_NormalMatrix * gl_Normal, 0.0)).xyz);
}
