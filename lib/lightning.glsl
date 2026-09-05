#ifndef LIGHTNING_GLSL
#define LIGHTNING_GLSL

#include "settings.glsl"
#include "common.glsl"
#include "noise.glsl"

/*
 * ==============================================================================
 *  PHYSICAL PROCEDURAL LIGHTNING SYSTEM
 *  - Stepped Leader Dynamics & Dielectric Breakdown Model (DBM)
 *  - Dendritic Branching Morphology (30°-45° forward angle, fractal dimension)
 *  - Energy Hierarchy & Starvation (Main Trunk, Dying Filaments, Aborted Leaders)
 *  - 3-Layer Plasma Structure: Ultra-bright Core, Filament Sheath, Soft Corona
 *  - Physical Multi-Peak Return Stroke Temporal Waveform (760ms timeline)
 *  - Incandescent White Plasma Core (>30,000K) & Subtle Atmospheric Scattering
 *  - Cloud-to-Ground (CG), Cloud-to-Cloud / Anvil Crawler (CC), Intra-Cloud (IC)
 * ==============================================================================
 */

// Discharge Classification
#define LIGHTNING_TYPE_CG  0 // Cloud-to-Ground
#define LIGHTNING_TYPE_CC  1 // Cloud-to-Cloud / Anvil Crawler
#define LIGHTNING_TYPE_IC  2 // Intra-Cloud / Sheet Lightning

struct LightningStrike {
    bool isTriggered;
    int strikeType;        // CG, CC, or IC
    float intensity;       // Overall multi-pulse flash intensity [0..1]
    float returnStroke;    // Peak sharp return stroke spike [0..1]
    float azimuth;         // Strike azimuth angle [0..2PI]
    float elevation;       // Center elevation angle [0..PI/2]
    vec3 strikeDir;        // Normalized world direction towards strike center
    vec3 origin;           // World 3D initiation position (meters)
    vec3 impactPos;        // World 3D impact position (ground or cloud target)
    float seed;            // Unique procedural seed for this discharge
    vec3 coreColor;        // Plasma incandescent core emission (>30,000K white HDR)
    vec3 sheathColor;      // Ionization corona color (subtle pale cool ice-blue)
};

// ------------------------------------------------------------------------------
// PRNG & Analytic Geometry Utilities
// ------------------------------------------------------------------------------
float lcgRandom(inout float state) {
    state = fract(sin(state * 127.1 + 311.7) * 43758.5453123);
    return state;
}

float normAngle(float a) {
    while (a > PI) a -= 2.0 * PI;
    while (a < -PI) a += 2.0 * PI;
    return a;
}

float distToSegment2D(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float bLen2 = dot(ba, ba);
    if (bLen2 < 1e-7) return length(pa);
    float h = clamp(dot(pa, ba) / bLen2, 0.0, 1.0);
    return length(pa - ba * h);
}

// ------------------------------------------------------------------------------
// Physical Multi-Stroke Temporal Waveform (760ms Timeline Keyframes)
// ------------------------------------------------------------------------------
void evaluateLightningTimeline(float t_sec, out float flashOut, out float boltOut) {
    float t_ms = t_sec * 1000.0;
    if (t_ms < 0.0 || t_ms >= 760.0) {
        flashOut = 0.0;
        boltOut  = 0.0;
        return;
    }

    float baseFlash = 0.0;
    float baseBolt  = 0.0;

    if (t_ms <= 42.0) {
        float u = t_ms / 42.0;
        baseFlash = mix(1.00, 0.14, u);
        baseBolt  = mix(1.00, 0.38, u);
    } else if (t_ms <= 88.0) {
        float u = (t_ms - 42.0) / 46.0;
        baseFlash = mix(0.14, 0.58, u);
        baseBolt  = mix(0.38, 0.88, u);
    } else if (t_ms <= 155.0) {
        float u = (t_ms - 88.0) / 67.0;
        baseFlash = mix(0.58, 0.07, u);
        baseBolt  = mix(0.88, 0.26, u);
    } else if (t_ms <= 235.0) {
        float u = (t_ms - 155.0) / 80.0;
        baseFlash = mix(0.07, 0.28, u);
        baseBolt  = mix(0.26, 0.52, u);
    } else if (t_ms <= 480.0) {
        float u = (t_ms - 235.0) / 245.0;
        baseFlash = mix(0.28, 0.02, u);
        baseBolt  = mix(0.52, 0.18, u);
    } else {
        float u = (t_ms - 480.0) / 280.0;
        baseFlash = mix(0.02, 0.00, u);
        baseBolt  = mix(0.18, 0.00, u);
    }

    flashOut = baseFlash * exp(-t_ms * 0.0012);
    boltOut  = baseBolt  * exp(-t_ms * 0.0022);
}

// ------------------------------------------------------------------------------
// Lightning Event & State Evaluation
// ------------------------------------------------------------------------------
LightningStrike evaluateLightningState(float rain, float timeSec) {
    LightningStrike s;
    s.isTriggered = false;
    s.intensity = 0.0;
    s.returnStroke = 0.0;
    s.strikeType = LIGHTNING_TYPE_CG;
    s.azimuth = 0.0;
    s.elevation = 0.22;
    s.strikeDir = vec3(0.0, 0.22, 1.0);
    s.origin = vec3(0.0, 260.0, 450.0);
    s.impactPos = vec3(0.0, 64.0, 450.0);
    s.seed = 1.0;
    // Pure incandescent plasma core (>30,000K)
    s.coreColor = vec3(1.0, 1.0, 1.0) * 85.0;
    // Subtle cool ice-blue / faint violet ionization corona
    s.sheathColor = vec3(0.72, 0.82, 1.06);

    #ifndef STORM_LIGHTNING
    return s;
    #endif

    #ifndef DYNAMIC_WEATHER
    return s;
    #endif

    if (rain < 0.60) return s;

    // Thunderstorm cycle interval (~4.2s between events)
    const float cycleDuration = 4.2;
    float timer = timeSec / cycleDuration;
    float cycle = floor(timer);
    float localT = fract(timer) * cycleDuration;

    float cycleSeed = hash11(cycle * 31.415 + 7.89);
    float strikeProbability = mix(0.40, 0.75, saturate((rain - 0.60) / 0.40));
    if (cycleSeed > strikeProbability) return s;

    float strikeStart = hash11(cycle * 17.83 + 2.1) * (cycleDuration - 0.90) + 0.10;
    float dt = localT - strikeStart;

    // Strike lifecycle lasts 0.76s (760ms)
    if (dt < 0.0 || dt > 0.76) return s;

    s.isTriggered = true;
    s.seed = cycleSeed * 883.0 + cycle * 19.1;

    // Classification: CG (45%), CC (32%), IC (23%)
    float typeSeed = hash11(s.seed * 13.37);
    if (typeSeed < 0.45) {
        s.strikeType = LIGHTNING_TYPE_CG;
    } else if (typeSeed < 0.77) {
        s.strikeType = LIGHTNING_TYPE_CC;
    } else {
        s.strikeType = LIGHTNING_TYPE_IC;
    }

    s.azimuth = hash11(cycle * 29.17 + 5.5) * TWO_PI;

    if (s.strikeType == LIGHTNING_TYPE_CG) {
        s.elevation = mix(0.12, 0.24, hash11(s.seed * 5.21));
    } else if (s.strikeType == LIGHTNING_TYPE_CC) {
        s.elevation = mix(0.24, 0.42, hash11(s.seed * 5.21));
    } else {
        s.elevation = mix(0.30, 0.52, hash11(s.seed * 5.21));
    }

    s.strikeDir = normalize(vec3(
        cos(s.azimuth) * cos(s.elevation),
        sin(s.elevation),
        sin(s.azimuth) * cos(s.elevation)
    ));

    float strikeDist = mix(450.0, 850.0, hash11(s.seed * 3.73));
    vec2 strikeXZ = vec2(cos(s.azimuth), sin(s.azimuth)) * strikeDist;

    if (s.strikeType == LIGHTNING_TYPE_CG) {
        s.origin = vec3(strikeXZ.x, 240.0, strikeXZ.y);
        s.impactPos = vec3(strikeXZ.x + (hash11(s.seed * 4.1) - 0.5) * 50.0, 64.0, strikeXZ.y + (hash11(s.seed * 4.2) - 0.5) * 50.0);
    } else if (s.strikeType == LIGHTNING_TYPE_CC) {
        s.origin = vec3(strikeXZ.x - 220.0, 260.0, strikeXZ.y - 120.0);
        s.impactPos = vec3(strikeXZ.x + 220.0, 290.0, strikeXZ.y + 120.0);
    } else {
        s.origin = vec3(strikeXZ.x, 320.0, strikeXZ.y);
        s.impactPos = s.origin + vec3((hash11(s.seed * 7.1) - 0.5) * 240.0, 40.0, (hash11(s.seed * 7.2) - 0.5) * 240.0);
    }

    float flashVal, boltVal;
    evaluateLightningTimeline(dt, flashVal, boltVal);
    s.intensity = flashVal * rain;
    s.returnStroke = boltVal * rain;

    return s;
}

// ------------------------------------------------------------------------------
// Procedural Stepped Leader Bolt Geometry (Cloud-to-Ground & Anvil Crawler)
// ------------------------------------------------------------------------------
// ------------------------------------------------------------------------------
// 4-Pass Physical Plasma Emission Model (Faithful to Atmospheric Discharge Web)
// Pass 1: Outer Corona (x9.5, indigo/cool-blue atmospheric air ionization)
// Pass 2: Mid Corona (x3.6, pale lavender-ice electric sheath)
// Pass 3: Inner Shell (x1.55, bright incandescent bluish-white)
// Pass 4: Plasma Core (x0.62, razor-sharp incandescent white >30,000K)
// ------------------------------------------------------------------------------
vec3 evaluate4PassPlasma(float d0, float d1, float d2, float d3, float d4, float returnStroke, float intensity) {
    // 1. Plasma core: razor-sharp incandescent white (>30,000K, sigma ~ 0.25)
    float c0 = exp(-d0 * d0 * 8.0) * 75.0 * 1.00;
    float c1 = exp(-d1 * d1 * 8.0) * 75.0 * 0.75;
    float c2 = exp(-d2 * d2 * 8.0) * 75.0 * 0.56;
    float c3 = exp(-d3 * d3 * 8.0) * 75.0 * 0.42;
    float c4 = exp(-d4 * d4 * 8.0) * 75.0 * 0.31;
    float totCore = (c0 + c1 + c2 + c3 + c4) * returnStroke;

    // 2. Inner shell: high energy bluish-white ionization sheath (sigma ~ 0.60)
    float in0 = exp(-d0 * d0 * 1.4) * 14.0 * 1.00;
    float in1 = exp(-d1 * d1 * 1.4) * 14.0 * 0.75;
    float in2 = exp(-d2 * d2 * 1.4) * 14.0 * 0.56;
    float in3 = exp(-d3 * d3 * 1.4) * 14.0 * 0.42;
    float in4 = exp(-d4 * d4 * 1.4) * 14.0 * 0.31;
    float totInner = (in0 + in1 + in2 + in3 + in4) * intensity;

    // 3. Mid corona: lavender-ice electric glow (sigma ~ 1.40)
    float mid0 = exp(-d0 * d0 * 0.25) * 3.0 * 1.00;
    float mid1 = exp(-d1 * d1 * 0.25) * 3.0 * 0.75;
    float mid2 = exp(-d2 * d2 * 0.25) * 3.0 * 0.56;
    float mid3 = exp(-d3 * d3 * 0.25) * 3.0 * 0.42;
    float mid4 = exp(-d4 * d4 * 0.25) * 3.0 * 0.31;
    float totMid = (mid0 + mid1 + mid2 + mid3 + mid4) * intensity;

    // 4. Outer corona: subtle cool blue atmospheric ionization (sigma ~ 3.0)
    float out0 = exp(-d0 * d0 * 0.055) * 0.85 * 1.00;
    float out1 = exp(-d1 * d1 * 0.055) * 0.85 * 0.75;
    float out2 = exp(-d2 * d2 * 0.055) * 0.85 * 0.56;
    float out3 = exp(-d3 * d3 * 0.055) * 0.85 * 0.42;
    float out4 = exp(-d4 * d4 * 0.055) * 0.85 * 0.31;
    float totOut = (out0 + out1 + out2 + out3 + out4) * intensity;

    const vec3 CORE_COLOR  = vec3(1.00, 1.00, 1.00);
    const vec3 INNER_COLOR = vec3(0.88, 0.94, 1.00);
    const vec3 MID_COLOR   = vec3(0.65, 0.78, 1.00);
    const vec3 OUTER_COLOR = vec3(0.35, 0.58, 1.00);

    return (totCore * CORE_COLOR + totInner * INNER_COLOR + totMid * MID_COLOR + totOut * OUTER_COLOR);
}

// ------------------------------------------------------------------------------
// Procedural Stepped Leader Bolt Geometry (Cloud-to-Ground & Anvil Crawler)
// ------------------------------------------------------------------------------
vec3 evaluateProceduralLightningBolt(vec3 rayDir, LightningStrike s) {
    #ifndef STORM_LIGHTNING
    return vec3(0.0);
    #endif

    #ifndef LIGHTNING_BOLTS
    return vec3(0.0);
    #endif

    if (!s.isTriggered || s.intensity < 0.005) return vec3(0.0);

    // Orthonormal basis centered on strike direction
    vec3 strikeRight = normalize(cross(WORLD_UP, s.strikeDir));
    vec3 strikeUp    = cross(s.strikeDir, strikeRight);

    float cosAngle = dot(rayDir, s.strikeDir);
    if (cosAngle < 0.20) return vec3(0.0); // Outside viewing cone

    vec2 p = vec2(dot(rayDir, strikeRight), dot(rayDir, strikeUp)) / cosAngle;

    // --- TYPE 0: CLOUD-TO-GROUND (CG) STEPPED LEADER BOLT ---
    if (s.strikeType == LIGHTNING_TYPE_CG) {
        // Fast bounding box check with smooth outer border fade
        float fadeX = 1.0 - smoothstep(0.48, 0.72, abs(p.x));
        float fadeY = (1.0 - smoothstep(0.44, 0.56, p.y)) * smoothstep(-0.48, -0.36, p.y);
        float fieldFade = fadeX * fadeY;
        if (fieldFade <= 0.001) return vec3(0.0);

        float rng = s.seed;
        float startX = (lcgRandom(rng) - 0.5) * 0.08;
        float startY = 0.46;
        float targetX = startX + (lcgRandom(rng) - 0.5) * 0.16;
        float targetY = -0.42;

        float curX = startX;
        float curY = startY;
        float curAngle = -PI * 0.5 + (lcgRandom(rng) - 0.5) * 0.15;
        float wander = (lcgRandom(rng) - 0.5) * 0.20;

        float minD_G0 = 1e5;
        float minD_G1 = 1e5;
        float minD_G2 = 1e5;
        float minD_G3 = 1e5;
        float minD_G4 = 1e5;

        // Branch origination nodes for Gen 1 (up to 5 branches along trunk)
        #if LIGHTNING_BRANCH_GEN >= 1
        vec2 g1_pos[5];
        float g1_ang[5];
        float g1_thick[5];
        float g1_side[5];
        int g1_steps[5];
        int g1_count = 0;
        #endif

        // 1. TRUNK (Gen 0): 36 stepped leader iterations
        for (int i = 0; i < 36; ++i) {
            float dx = targetX - curX;
            float dy = targetY - curY;
            float dist = length(vec2(dx, dy));
            float targetAngle = atan(dy, dx);

            // Anisotropy pull towards ground target
            float diff = normAngle(targetAngle - curAngle);
            curAngle += diff * ((abs(diff) > 0.8) ? 0.28 : 0.22);

            // Stepped leader wander low-pass 0.88 + high-freq jitter
            float high = (lcgRandom(rng) - 0.5) * LIGHTNING_ROUGHNESS;
            wander = wander * 0.88 + high * 0.12 + (lcgRandom(rng) - 0.5) * 0.04;

            // 12% probability of sharp dielectric breakdown kink (x2.0)
            bool isKink = lcgRandom(rng) < 0.12;
            curAngle += wander + (isKink ? (high * 2.0) : (high * 0.50));

            // Downward electric field bias: enforce downward progression (-Y)
            if (sin(curAngle) > -0.15) {
                curAngle = -PI * 0.5 + (lcgRandom(rng) - 0.5) * 0.60;
            }

            // Adaptive step length ensuring ground reach in 36 steps
            float baseLen = max(0.024, min(0.048, dist / float(36 - i)));
            float stepLen = baseLen * mix(0.75, 1.25, lcgRandom(rng));

            float nx = curX + cos(curAngle) * stepLen;
            float ny = curY + sin(curAngle) * stepLen;

            float thick = 1.0 * mix(0.92, 1.08, lcgRandom(rng));
            float chW = max(thick * 0.0038, 0.0020);
            float d = distToSegment2D(p, vec2(curX, curY), vec2(nx, ny)) / chW;
            minD_G0 = min(minD_G0, d);

            #if LIGHTNING_BRANCH_GEN >= 1
            // Distributed branch slots along the trunk (i = 4, 10, 16, 22, 28)
            if (g1_count < 5 && (i == 4 || i == 10 || i == 16 || i == 22 || i == 28)) {
                float side = (mod(float(g1_count), 2.0) < 0.5) ? 1.0 : -1.0;
                float offset = radians(30.0 + lcgRandom(rng) * 15.0) * side;
                float childAngle = curAngle + offset + (lcgRandom(rng) - 0.5) * 0.20;
                if (sin(childAngle) < 0.25) {
                    g1_pos[g1_count] = vec2(nx, ny);
                    g1_ang[g1_count] = childAngle;
                    g1_thick[g1_count] = thick * mix(0.52, 0.68, lcgRandom(rng));
                    g1_side[g1_count] = side;
                    g1_steps[g1_count] = int(clamp(36.0 * mix(0.28, 0.45, lcgRandom(rng)), 6.0, 12.0));
                    g1_count++;
                }
            }
            #endif

            curX = nx;
            curY = ny;
            if (curY <= targetY - 0.01) break;
        }

        vec2 groundImpact = vec2(curX, curY);

        // 2. PRIMARY BRANCHES (Gen 1)
        #if LIGHTNING_BRANCH_GEN >= 2
        vec2 g2_pos[5];
        float g2_ang[5];
        float g2_thick[5];
        float g2_side[5];
        int g2_steps[5];
        int g2_count = 0;
        #endif

        #if LIGHTNING_BRANCH_GEN >= 1
        for (int k = 0; k < 5; ++k) {
            if (k >= g1_count) break;
            vec2 cPos = g1_pos[k];
            float cAng = g1_ang[k];
            float bThick = g1_thick[k];
            float bSide = g1_side[k];
            int maxSteps = g1_steps[k];
            float bWander = (lcgRandom(rng) - 0.5) * 0.20;
            float bRough = LIGHTNING_ROUGHNESS * 0.90;

            for (int s = 0; s < 12; ++s) {
                if (s >= maxSteps) break;

                // Anisotropy pull towards ground target
                float dx = targetX - cPos.x;
                float dy = targetY - cPos.y;
                cAng += normAngle(atan(dy, dx) - cAng) * 0.12;

                float high = (lcgRandom(rng) - 0.5) * bRough;
                bWander = bWander * 0.88 + high * 0.12 + (lcgRandom(rng) - 0.5) * 0.04;
                bool isKink = lcgRandom(rng) < 0.12;
                cAng += bWander + (isKink ? (high * 2.0) : (high * 0.50));
                if (sin(cAng) > 0.25) {
                    cAng = -PI * 0.5 + (lcgRandom(rng) - 0.5) * 0.80;
                }
                float stepLen = mix(0.014, 0.024, lcgRandom(rng)) * 0.85;
                vec2 nextPos = cPos + vec2(cos(cAng), sin(cAng)) * stepLen;
                float thick = bThick * mix(0.90, 1.10, lcgRandom(rng));
                float chW = max(thick * 0.0038, 0.0020);
                float d = distToSegment2D(p, cPos, nextPos) / chW;
                minD_G1 = min(minD_G1, d);

                #if LIGHTNING_BRANCH_GEN >= 2
                // Spawn Gen 2 twigs at steps 2 and 4
                if (g2_count < 5 && (s == 2 || s == 4)) {
                    float twSide = (s == 2) ? -bSide : bSide;
                    float twOffset = radians(30.0 + lcgRandom(rng) * 15.0) * twSide;
                    float twAng = cAng + twOffset + (lcgRandom(rng) - 0.5) * 0.20;
                    if (sin(twAng) < 0.25) {
                        g2_pos[g2_count] = nextPos;
                        g2_ang[g2_count] = twAng;
                        g2_thick[g2_count] = thick * mix(0.50, 0.68, lcgRandom(rng));
                        g2_side[g2_count] = twSide;
                        g2_steps[g2_count] = int(clamp(float(maxSteps) * mix(0.40, 0.65, lcgRandom(rng)), 3.0, 7.0));
                        g2_count++;
                    }
                }
                #endif

                cPos = nextPos;
                // Physical branch starvation after minimum 3 steps
                if (s > 3 && lcgRandom(rng) < (0.04 + 1.0 * 0.045)) break;
            }
        }
        #endif

        // 3. SECONDARY BRANCHES (Gen 2)
        #if LIGHTNING_BRANCH_GEN >= 3
        vec2 g3_pos[4];
        float g3_ang[4];
        float g3_thick[4];
        float g3_side[4];
        int g3_steps[4];
        int g3_count = 0;
        #endif

        #if LIGHTNING_BRANCH_GEN >= 2
        for (int k = 0; k < 5; ++k) {
            if (k >= g2_count) break;
            vec2 cPos = g2_pos[k];
            float cAng = g2_ang[k];
            float tThick = g2_thick[k];
            float tSide = g2_side[k];
            int maxSteps = g2_steps[k];
            float tWander = 0.0;
            float tRough = LIGHTNING_ROUGHNESS * 0.81;

            for (int s = 0; s < 7; ++s) {
                if (s >= maxSteps) break;
                float high = (lcgRandom(rng) - 0.5) * tRough;
                tWander = tWander * 0.88 + high * 0.12 + (lcgRandom(rng) - 0.5) * 0.04;
                bool isKink = lcgRandom(rng) < 0.12;
                cAng += tWander + (isKink ? (high * 2.0) : (high * 0.50));
                if (sin(cAng) > 0.25) {
                    cAng = -PI * 0.5 + (lcgRandom(rng) - 0.5) * 0.80;
                }
                float stepLen = mix(0.010, 0.018, lcgRandom(rng));
                vec2 nextPos = cPos + vec2(cos(cAng), sin(cAng)) * stepLen;
                float thick = tThick * mix(0.90, 1.10, lcgRandom(rng));
                float chW = max(thick * 0.0038, 0.0020);
                float d = distToSegment2D(p, cPos, nextPos) / chW;
                minD_G2 = min(minD_G2, d);

                #if LIGHTNING_BRANCH_GEN >= 3
                // Spawn Gen 3 sub-twigs at step 2
                if (g3_count < 4 && s == 2) {
                    float subSide = -tSide;
                    float subOffset = radians(30.0 + lcgRandom(rng) * 15.0) * subSide;
                    float subAng = cAng + subOffset;
                    if (sin(subAng) < 0.28) {
                        g3_pos[g3_count] = nextPos;
                        g3_ang[g3_count] = subAng;
                        g3_thick[g3_count] = thick * mix(0.50, 0.70, lcgRandom(rng));
                        g3_side[g3_count] = subSide;
                        g3_steps[g3_count] = int(clamp(float(maxSteps) * mix(0.45, 0.75, lcgRandom(rng)), 2.0, 5.0));
                        g3_count++;
                    }
                }
                #endif

                cPos = nextPos;
                if (s > 2 && lcgRandom(rng) < (0.04 + 2.0 * 0.05)) break;
            }
        }
        #endif

        // 4. TERTIARY BRANCHES (Gen 3)
        #if LIGHTNING_BRANCH_GEN >= 4
        vec2 g4_pos[4];
        float g4_ang[4];
        float g4_thick[4];
        int g4_count = 0;
        #endif

        #if LIGHTNING_BRANCH_GEN >= 3
        for (int k = 0; k < 4; ++k) {
            if (k >= g3_count) break;
            vec2 cPos = g3_pos[k];
            float cAng = g3_ang[k];
            float sThick = g3_thick[k];
            float sSide = g3_side[k];
            int maxSteps = g3_steps[k];
            float sWander = 0.0;
            float sRough = LIGHTNING_ROUGHNESS * 0.72;

            for (int s = 0; s < 5; ++s) {
                if (s >= maxSteps) break;
                float high = (lcgRandom(rng) - 0.5) * sRough;
                sWander = sWander * 0.88 + high * 0.12;
                cAng += sWander + high * 0.75;
                float stepLen = mix(0.008, 0.014, lcgRandom(rng));
                vec2 nextPos = cPos + vec2(cos(cAng), sin(cAng)) * stepLen;
                float thick = sThick * mix(0.90, 1.10, lcgRandom(rng));
                float chW = max(thick * 0.0038, 0.0020);
                float d = distToSegment2D(p, cPos, nextPos) / chW;
                minD_G3 = min(minD_G3, d);

                #if LIGHTNING_BRANCH_GEN >= 4
                // Spawn Gen 4 filaments at step 1
                if (g4_count < 4 && s == 1) {
                    float filSide = -sSide;
                    float filOffset = radians(30.0 + lcgRandom(rng) * 15.0) * filSide;
                    g4_pos[g4_count] = nextPos;
                    g4_ang[g4_count] = cAng + filOffset;
                    g4_thick[g4_count] = thick * 0.60;
                    g4_count++;
                }
                #endif

                cPos = nextPos;
                if (s > 1 && lcgRandom(rng) < (0.04 + 3.0 * 0.055)) break;
            }
        }
        #endif

        // 5. QUATERNARY MICRO-FILAMENTS (Gen 4)
        #if LIGHTNING_BRANCH_GEN >= 4
        for (int k = 0; k < 4; ++k) {
            if (k >= g4_count) break;
            vec2 cPos = g4_pos[k];
            float cAng = g4_ang[k];
            float fThick = g4_thick[k];
            float fRough = LIGHTNING_ROUGHNESS * 0.65;

            for (int s = 0; s < 3; ++s) {
                float high = (lcgRandom(rng) - 0.5) * fRough;
                cAng += high * 0.70;
                float stepLen = mix(0.006, 0.010, lcgRandom(rng));
                vec2 nextPos = cPos + vec2(cos(cAng), sin(cAng)) * stepLen;
                float thick = fThick * mix(0.90, 1.10, lcgRandom(rng));
                float chW = max(thick * 0.0038, 0.0020);
                float d = distToSegment2D(p, cPos, nextPos) / chW;
                minD_G4 = min(minD_G4, d);
                cPos = nextPos;
            }
        }
        #endif

        // Evaluate 4-Pass Plasma Rendering across all generations
        vec3 boltCol = evaluate4PassPlasma(minD_G0, minD_G1, minD_G2, minD_G3, minD_G4, s.returnStroke, s.intensity);

        // Origin Radial Cloud Illumination (where bolt emerges from storm clouds)
        float dOrigin = length((p - vec2(startX, startY)) * vec2(1.0, 1.4));
        float originGlow = (exp(-dOrigin * dOrigin / 0.006) * 3.5 + exp(-dOrigin / 0.05) * 1.2) * s.intensity;
        vec3 originCol = vec3(0.65, 0.78, 1.0) * originGlow;

        // Ground strike impact reflection: intense localized impact burst at strike coordinates
        vec2 impactP = (p - groundImpact) * vec2(2.0, 4.0);
        float dImpact = length(impactP);
        float impactCore = exp(-dImpact * dImpact / 0.00008) * 40.0 * s.returnStroke;
        float impactGlow = exp(-dImpact / 0.018) * 4.2 * s.intensity;
        vec3 impactCol = (vec3(1.0) * impactCore + vec3(0.65, 0.80, 1.0) * impactGlow);

        return (boltCol + originCol + impactCol) * fieldFade * LIGHTNING_INTENSITY;
    }

    // --- TYPE 1: CLOUD-TO-CLOUD / ANVIL CRAWLER (CC) ---
    if (s.strikeType == LIGHTNING_TYPE_CC) {
        float fadeCC_X = 1.0 - smoothstep(0.62, 0.88, abs(p.x));
        float fadeCC_Y = 1.0 - smoothstep(0.32, 0.52, abs(p.y));
        float fieldFadeCC = fadeCC_X * fadeCC_Y;
        if (fieldFadeCC <= 0.001) return vec3(0.0);

        float rng = s.seed + 11.7;
        float curX = -0.58;
        float curY = (lcgRandom(rng) - 0.5) * 0.06;
        float curAngle = (lcgRandom(rng) - 0.5) * 0.12;
        float wander = (lcgRandom(rng) - 0.5) * 0.20;

        float minD_CC0 = 1e5;
        float minD_CC1 = 1e5;
        float minD_CC2 = 1e5;
        float minD_CC3 = 1e5;
        float minD_CC4 = 1e5;

        // Forks branching upward & downward into cloud anvil
        #if LIGHTNING_BRANCH_GEN >= 1
        vec2 cc1_pos[5];
        float cc1_ang[5];
        float cc1_thick[5];
        float cc1_side[5];
        int cc1_steps[5];
        int cc1_count = 0;
        #endif

        // 1. Horizontal Crawler Trunk (32 steps across the sky)
        for (int i = 0; i < 32; ++i) {
            float targetAngle = -curY * 0.8; // gently pull towards horizontal centerline
            curAngle += normAngle(targetAngle - curAngle) * 0.16;

            float high = (lcgRandom(rng) - 0.5) * LIGHTNING_ROUGHNESS;
            wander = wander * 0.88 + high * 0.12 + (lcgRandom(rng) - 0.5) * 0.04;
            bool isKink = lcgRandom(rng) < 0.12;
            curAngle += wander + (isKink ? (high * 2.0) : (high * 0.50));
            curAngle = clamp(curAngle, -0.65, 0.65);

            float baseLen = max(0.024, min(0.045, (0.58 - curX) / float(32 - i)));
            float stepLen = baseLen * mix(0.75, 1.25, lcgRandom(rng));
            float nx = curX + cos(curAngle) * stepLen;
            float ny = curY + sin(curAngle) * stepLen;

            float thick = 1.0 * mix(0.90, 1.10, lcgRandom(rng));
            float chW = max(thick * 0.0038, 0.0020);
            float d = distToSegment2D(p, vec2(curX, curY), vec2(nx, ny)) / chW;
            minD_CC0 = min(minD_CC0, d);

            #if LIGHTNING_BRANCH_GEN >= 1
            // Distributed fork slots (i = 3, 9, 15, 21, 27)
            if (cc1_count < 5 && (i == 3 || i == 9 || i == 15 || i == 21 || i == 27)) {
                float side = (mod(float(cc1_count), 2.0) < 0.5) ? 1.0 : -1.0;
                float offset = radians(32.0 + lcgRandom(rng) * 16.0) * side;
                cc1_pos[cc1_count] = vec2(nx, ny);
                cc1_ang[cc1_count] = curAngle + offset + (lcgRandom(rng) - 0.5) * 0.20;
                cc1_thick[cc1_count] = thick * mix(0.50, 0.68, lcgRandom(rng));
                cc1_side[cc1_count] = side;
                cc1_steps[cc1_count] = int(clamp(32.0 * mix(0.28, 0.45, lcgRandom(rng)), 5.0, 10.0));
                cc1_count++;
            }
            #endif

            curX = nx;
            curY = ny;
            if (curX >= 0.58) break;
        }

        // 2. Anvil Spiderweb Forks (Gen 1)
        #if LIGHTNING_BRANCH_GEN >= 2
        vec2 cc2_pos[5];
        float cc2_ang[5];
        float cc2_thick[5];
        float cc2_side[5];
        int cc2_steps[5];
        int cc2_count = 0;
        #endif

        #if LIGHTNING_BRANCH_GEN >= 1
        for (int k = 0; k < 5; ++k) {
            if (k >= cc1_count) break;
            vec2 cPos = cc1_pos[k];
            float cAng = cc1_ang[k];
            float bThick = cc1_thick[k];
            float bSide = cc1_side[k];
            int maxSteps = cc1_steps[k];
            float bWander = (lcgRandom(rng) - 0.5) * 0.20;
            float bRough = LIGHTNING_ROUGHNESS * 0.90;

            for (int s = 0; s < 10; ++s) {
                if (s >= maxSteps) break;
                float high = (lcgRandom(rng) - 0.5) * bRough;
                bWander = bWander * 0.88 + high * 0.12 + (lcgRandom(rng) - 0.5) * 0.04;
                bool isKink = lcgRandom(rng) < 0.12;
                cAng += bWander + (isKink ? (high * 2.0) : (high * 0.50));
                float stepLen = mix(0.014, 0.024, lcgRandom(rng)) * 0.85;
                vec2 nextPos = cPos + vec2(cos(cAng), sin(cAng)) * stepLen;
                float thick = bThick * mix(0.90, 1.10, lcgRandom(rng));
                float chW = max(thick * 0.0038, 0.0020);
                float d = distToSegment2D(p, cPos, nextPos) / chW;
                minD_CC1 = min(minD_CC1, d);

                #if LIGHTNING_BRANCH_GEN >= 2
                // Spawn Gen 2 crawler twigs
                if (cc2_count < 5 && (s == 2 || s == 4)) {
                    float twSide = (s == 2) ? -bSide : bSide;
                    float twOffset = radians(30.0 + lcgRandom(rng) * 16.0) * twSide;
                    cc2_pos[cc2_count] = nextPos;
                    cc2_ang[cc2_count] = cAng + twOffset + (lcgRandom(rng) - 0.5) * 0.20;
                    cc2_thick[cc2_count] = thick * mix(0.48, 0.68, lcgRandom(rng));
                    cc2_side[cc2_count] = twSide;
                    cc2_steps[cc2_count] = int(clamp(float(maxSteps) * mix(0.40, 0.65, lcgRandom(rng)), 3.0, 6.0));
                    cc2_count++;
                }
                #endif

                cPos = nextPos;
                if (s > 3 && lcgRandom(rng) < (0.04 + 1.0 * 0.045)) break;
            }
        }
        #endif

        // 3. Secondary Crawler Twigs (Gen 2)
        #if LIGHTNING_BRANCH_GEN >= 3
        vec2 cc3_pos[4];
        float cc3_ang[4];
        float cc3_thick[4];
        float cc3_side[4];
        int cc3_steps[4];
        int cc3_count = 0;
        #endif

        #if LIGHTNING_BRANCH_GEN >= 2
        for (int k = 0; k < 5; ++k) {
            if (k >= cc2_count) break;
            vec2 cPos = cc2_pos[k];
            float cAng = cc2_ang[k];
            float tThick = cc2_thick[k];
            float tSide = cc2_side[k];
            int maxSteps = cc2_steps[k];
            float tWander = 0.0;
            float tRough = LIGHTNING_ROUGHNESS * 0.81;

            for (int s = 0; s < 6; ++s) {
                if (s >= maxSteps) break;
                float high = (lcgRandom(rng) - 0.5) * tRough;
                tWander = tWander * 0.88 + high * 0.12 + (lcgRandom(rng) - 0.5) * 0.04;
                bool isKink = lcgRandom(rng) < 0.12;
                cAng += tWander + (isKink ? (high * 2.0) : (high * 0.50));
                float stepLen = mix(0.010, 0.018, lcgRandom(rng));
                vec2 nextPos = cPos + vec2(cos(cAng), sin(cAng)) * stepLen;
                float thick = tThick * mix(0.90, 1.10, lcgRandom(rng));
                float chW = max(thick * 0.0038, 0.0020);
                float d = distToSegment2D(p, cPos, nextPos) / chW;
                minD_CC2 = min(minD_CC2, d);

                #if LIGHTNING_BRANCH_GEN >= 3
                // Spawn Gen 3 crawler twigs
                if (cc3_count < 4 && s == 2) {
                    float subSide = -tSide;
                    float subOffset = radians(30.0 + lcgRandom(rng) * 15.0) * subSide;
                    cc3_pos[cc3_count] = nextPos;
                    cc3_ang[cc3_count] = cAng + subOffset;
                    cc3_thick[cc3_count] = thick * mix(0.50, 0.70, lcgRandom(rng));
                    cc3_side[cc3_count] = subSide;
                    cc3_steps[cc3_count] = int(clamp(float(maxSteps) * mix(0.45, 0.75, lcgRandom(rng)), 2.0, 5.0));
                    cc3_count++;
                }
                #endif

                cPos = nextPos;
                if (s > 2 && lcgRandom(rng) < (0.04 + 2.0 * 0.05)) break;
            }
        }
        #endif

        // 4. Tertiary Crawler Filaments (Gen 3)
        #if LIGHTNING_BRANCH_GEN >= 4
        vec2 cc4_pos[4];
        float cc4_ang[4];
        float cc4_thick[4];
        int cc4_count = 0;
        #endif

        #if LIGHTNING_BRANCH_GEN >= 3
        for (int k = 0; k < 4; ++k) {
            if (k >= cc3_count) break;
            vec2 cPos = cc3_pos[k];
            float cAng = cc3_ang[k];
            float sThick = cc3_thick[k];
            float sSide = cc3_side[k];
            int maxSteps = cc3_steps[k];
            float sWander = 0.0;
            float sRough = LIGHTNING_ROUGHNESS * 0.72;

            for (int s = 0; s < 5; ++s) {
                if (s >= maxSteps) break;
                float high = (lcgRandom(rng) - 0.5) * sRough;
                sWander = sWander * 0.88 + high * 0.12;
                cAng += sWander + high * 0.75;
                float stepLen = mix(0.008, 0.014, lcgRandom(rng));
                vec2 nextPos = cPos + vec2(cos(cAng), sin(cAng)) * stepLen;
                float thick = sThick * mix(0.90, 1.10, lcgRandom(rng));
                float chW = max(thick * 0.0038, 0.0020);
                float d = distToSegment2D(p, cPos, nextPos) / chW;
                minD_CC3 = min(minD_CC3, d);

                #if LIGHTNING_BRANCH_GEN >= 4
                // Spawn Gen 4 filaments
                if (cc4_count < 4 && s == 1) {
                    float filSide = -sSide;
                    float filOffset = radians(30.0 + lcgRandom(rng) * 15.0) * filSide;
                    cc4_pos[cc4_count] = nextPos;
                    cc4_ang[cc4_count] = cAng + filOffset;
                    cc4_thick[cc4_count] = thick * 0.60;
                    cc4_count++;
                }
                #endif

                cPos = nextPos;
                if (s > 1 && lcgRandom(rng) < (0.04 + 3.0 * 0.055)) break;
            }
        }
        #endif

        // 5. Quaternary Filaments (Gen 4)
        #if LIGHTNING_BRANCH_GEN >= 4
        for (int k = 0; k < 4; ++k) {
            if (k >= cc4_count) break;
            vec2 cPos = cc4_pos[k];
            float cAng = cc4_ang[k];
            float fThick = cc4_thick[k];
            float fRough = LIGHTNING_ROUGHNESS * 0.65;

            for (int s = 0; s < 3; ++s) {
                float high = (lcgRandom(rng) - 0.5) * fRough;
                cAng += high * 0.70;
                float stepLen = mix(0.006, 0.010, lcgRandom(rng));
                vec2 nextPos = cPos + vec2(cos(cAng), sin(cAng)) * stepLen;
                float thick = fThick * mix(0.90, 1.10, lcgRandom(rng));
                float chW = max(thick * 0.0038, 0.0020);
                float d = distToSegment2D(p, cPos, nextPos) / chW;
                minD_CC4 = min(minD_CC4, d);
                cPos = nextPos;
            }
        }
        #endif

        vec3 crawlerCol = evaluate4PassPlasma(minD_CC0, minD_CC1, minD_CC2, minD_CC3, minD_CC4, s.returnStroke, s.intensity);
        return crawlerCol * fieldFadeCC * LIGHTNING_INTENSITY;
    }

    // --- TYPE 2: INTRA-CLOUD (IC) / SHEET LIGHTNING ---
    // Deep volumetric scatter inside cloud volume; in sky background, soft diffused internal glow
    if (s.strikeType == LIGHTNING_TYPE_IC) {
        vec2 icCenter = vec2((hash11(s.seed * 5.3) - 0.5) * 0.20, 0.30);
        float dIC = length(p - icCenter);

        float icCore = exp(-dIC * 4.5) * 2.5 * s.returnStroke;
        float icGlow = exp(-dIC * 2.0) * 1.2 * s.intensity;
        float fadeIC = 1.0 - smoothstep(0.20, 0.75, dIC);

        return (s.coreColor * icCore * 0.4 + s.sheathColor * (icCore + icGlow)) * fadeIC * LIGHTNING_INTENSITY;
    }

    return vec3(0.0);
}

// ------------------------------------------------------------------------------
// Volumetric Intra-Cloud Scattering & Multiple-Scattering Lighting
// Evaluated for 3D point 'pos' with cloud density 'density' inside raymarch loop
// ------------------------------------------------------------------------------
vec3 evaluateIntraCloudLighting(vec3 pos, float density, LightningStrike s, vec3 rayDir) {
    #ifndef STORM_LIGHTNING
    return vec3(0.0);
    #endif

    #ifndef LIGHTNING_INTRA_CLOUD
    return vec3(0.0);
    #endif

    if (!s.isTriggered || s.intensity < 0.008) return vec3(0.0);

    // Vector and distance from 3D cloud sample point to lightning discharge source
    vec3 toStrike = s.origin - pos;
    float dist = length(toStrike);

    // Fast localized optical falloff through dense cloud
    float normDist = dist / 420.0;
    float distAtten = exp(-normDist * normDist * 2.8) / (1.0 + normDist * 2.5);
    if (distAtten < 0.0005) return vec3(0.0);

    // Volumetric optical extinction through cloud droplets
    // Dense cloud regions attenuate light heavily, creating moody dramatic shadows
    float extinction = exp(-density * 8.0);

    // Forward Mie scattering peak towards the viewer
    vec3 lightDir = normalize(toStrike + vec3(1e-4));
    float cosTheta = dot(lightDir, -rayDir);
    float mieScatter = hgPhase(cosTheta, 0.65);

    // Powder sugar effect / rim lighting: thin cloud fringes catch glowing edge highlights
    float rimEffect = (1.0 - exp(-density * 5.0)) * exp(-density * 2.0) * 2.5;
    float cloudRadianceFactor = mix(extinction * 0.35, rimEffect, 0.65);

    // Controlled emission that illuminates internal billows without blowing out
    vec3 emission = (s.coreColor * 0.04 + s.sheathColor * 2.2) * s.intensity * LIGHTNING_INTENSITY;
    return emission * distAtten * cloudRadianceFactor * (mieScatter * 0.65 + 0.35);
}

// ------------------------------------------------------------------------------
// Directional Atmospheric Air Ionization Glow (No full-screen white washout!)
// ------------------------------------------------------------------------------
vec3 evaluateAtmosphericLightningGlow(vec3 rayDir, LightningStrike s) {
    #ifndef STORM_LIGHTNING
    return vec3(0.0);
    #endif

    if (!s.isTriggered || s.intensity < 0.008) return vec3(0.0);

    float cosTheta = dot(rayDir, s.strikeDir);
    if (cosTheta < 0.20) return vec3(0.0);

    // Focused forward Mie scatter strictly concentrated around strike
    float focusedMie = pow(max(cosTheta, 0.0), 32.0) * 0.35;
    float diffuseGlow = pow(max(cosTheta, 0.0), 8.0) * 0.08;

    return s.sheathColor * (focusedMie + diffuseGlow) * s.intensity * LIGHTNING_INTENSITY;
}

#endif // LIGHTNING_GLSL
