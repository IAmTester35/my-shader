#version 120

varying vec3 worldPos;

uniform mat4 gbufferModelViewInverse;

void main() {
    gl_Position = ftransform();
    
    // Transform vertex position into camera-relative world space
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    worldPos = (gbufferModelViewInverse * viewPos).xyz;
}
