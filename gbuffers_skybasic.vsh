#version 120

varying vec3 worldPos;
varying vec4 vertexColor;

uniform mat4 gbufferModelViewInverse;

void main() {
    gl_Position = ftransform();
    vertexColor = gl_Color;
    
    // Transform vertex position into camera-relative world space
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    worldPos = (gbufferModelViewInverse * viewPos).xyz;
}
