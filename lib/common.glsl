#ifndef COMMON_GLSL
#define COMMON_GLSL

/*
 * ==============================================================================
 *  COMMON MATH, CONSTANTS & COORDINATE TRANSFORMS
 * ==============================================================================
 */

const float PI      = 3.14159265358979323846;
const float TWO_PI  = 6.28318530717958647692;
const float HALF_PI = 1.57079632679489661923;
const float INV_PI  = 0.31830988618379067154;

const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);

// Clamp scalar/vector to [0.0, 1.0]
float saturate(float x) {
    return clamp(x, 0.0, 1.0);
}

vec3 saturate(vec3 x) {
    return clamp(x, vec3(0.0), vec3(1.0));
}

// Screen coordinate [0..1] and depth [0..1] to view/camera space position
vec3 screenToView(vec2 screenCoord, float depth, mat4 projInv) {
    vec4 ndc = vec4(screenCoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = projInv * ndc;
    float safeW = abs(viewPos.w) > 1e-6 ? viewPos.w : (viewPos.w >= 0.0 ? 1e-6 : -1e-6);
    return viewPos.xyz / safeW;
}

// Screen UV to normalized world ray direction
vec3 getScreenRayDir(vec2 uv, mat4 projInv, mat4 modelViewInv) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    vec4 viewPos = projInv * ndc;
    float safeW = abs(viewPos.w) > 1e-6 ? viewPos.w : (viewPos.w >= 0.0 ? 1e-6 : -1e-6);
    vec3 viewDir = normalize(viewPos.xyz / safeW);
    return normalize((modelViewInv * vec4(viewDir, 0.0)).xyz);
}

// Calculate normalized sun and moon vectors in world space
// OptiFine sunPosition is given in eye/view space
vec3 getSunDirWorld(vec3 sunPosEye, mat4 modelViewInv) {
    vec3 eyeNorm = length(sunPosEye) > 1e-4 ? normalize(sunPosEye) : vec3(0.0, 1.0, 0.0);
    return normalize((modelViewInv * vec4(eyeNorm, 0.0)).xyz);
}

vec3 getMoonDirWorld(vec3 moonPosEye, mat4 modelViewInv) {
    vec3 eyeNorm = length(moonPosEye) > 1e-4 ? normalize(moonPosEye) : vec3(0.0, -1.0, 0.0);
    return normalize((modelViewInv * vec4(eyeNorm, 0.0)).xyz);
}

// Henyey-Greenstein scattering phase function
float hgPhase(float cosTheta, float g) {
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * cosTheta, 0.001), 1.5));
}

float doubleHgPhase(float cosTheta, float g1, float g2, float k) {
    return mix(hgPhase(cosTheta, g1), hgPhase(cosTheta, g2), k);
}

#endif // COMMON_GLSL
