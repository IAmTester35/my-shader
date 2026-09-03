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

// Clamp scalar/vector to [0.0, 1.0]
float saturate(float x) {
    return clamp(x, 0.0, 1.0);
}

vec2 saturate(vec2 x) {
    return clamp(x, vec2(0.0), vec2(1.0));
}

vec3 saturate(vec3 x) {
    return clamp(x, vec3(0.0), vec3(1.0));
}

vec4 saturate(vec4 x) {
    return clamp(x, vec4(0.0), vec4(1.0));
}

// Remap value from [inMin, inMax] to [outMin, outMax]
float remap(float val, float inMin, float inMax, float outMin, float outMax) {
    return outMin + (val - inMin) * (outMax - outMin) / (inMax - inMin);
}

float remapClamped(float val, float inMin, float inMax, float outMin, float outMax) {
    return clamp(remap(val, inMin, inMax, outMin, outMax), min(outMin, outMax), max(outMin, outMax));
}

// Convert non-linear depth buffer value [0..1] to linear eye-space distance
float linearizeDepth(float depth, float nearPlane, float farPlane) {
    return (2.0 * nearPlane) / (farPlane + nearPlane - depth * (farPlane - nearPlane));
}

// Screen coordinate [0..1] and depth [0..1] to view/camera space position
vec3 screenToView(vec2 screenCoord, float depth, mat4 projInv) {
    vec4 ndc = vec4(screenCoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = projInv * ndc;
    return viewPos.xyz / viewPos.w;
}

// View space position to world space position relative to camera
vec3 viewToWorld(vec3 viewPos, mat4 modelViewInv) {
    return (modelViewInv * vec4(viewPos, 1.0)).xyz;
}

// Screen UV to normalized world ray direction
vec3 getScreenRayDir(vec2 uv, mat4 projInv, mat4 modelViewInv) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    vec4 viewPos = projInv * ndc;
    vec3 viewDir = normalize(viewPos.xyz / viewPos.w);
    return normalize((modelViewInv * vec4(viewDir, 0.0)).xyz);
}

// Calculate normalized sun and moon vectors in world space
// OptiFine sunPosition is given in eye/view space
vec3 getSunDirWorld(vec3 sunPosEye, mat4 modelViewInv) {
    return normalize((modelViewInv * vec4(normalize(sunPosEye), 0.0)).xyz);
}

vec3 getMoonDirWorld(vec3 moonPosEye, mat4 modelViewInv) {
    return normalize((modelViewInv * vec4(normalize(moonPosEye), 0.0)).xyz);
}

// Calculate celestial rotation factor (0.0 at sunrise, 0.25 at noon, 0.5 at sunset, 0.75 at midnight)
float getDayFraction(int worldTimeTicks) {
    return fract(float(worldTimeTicks) / 24000.0);
}

// Smooth day/night blend weights
// dayWeight: 1.0 at noon, 0.0 at midnight
// sunsetWeight: 1.0 during golden hour/twilight
// nightWeight: 1.0 at midnight, 0.0 at noon
struct CelestialWeights {
    float day;
    float sunset;
    float night;
    float sunHeight;
};

CelestialWeights getCelestialWeights(vec3 sunDirWorld, vec3 upVector) {
    CelestialWeights w;
    w.sunHeight = dot(sunDirWorld, upVector);
    
    // Day transition: sunHeight > -0.05
    w.day = smoothstep(-0.08, 0.15, w.sunHeight);
    
    // Sunset transition: peaks around horizon (-0.12 to 0.12)
    float sunsetPeak = 1.0 - smoothstep(0.0, 0.18, abs(w.sunHeight));
    w.sunset = sunsetPeak * sunsetPeak;
    
    // Night transition: sunHeight < 0.0
    w.night = 1.0 - w.day;
    
    return w;
}

#endif // COMMON_GLSL
