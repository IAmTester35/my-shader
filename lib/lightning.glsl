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
 *  - 4-Layer Plasma Structure: Core, Inner Shell, Mid Corona, Outer Corona
 *  - Physical Multi-Peak Return Stroke Temporal Waveform (760ms timeline)
 *  - Incandescent White Plasma Core (>30,000K) & Atmospheric Scattering
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

// Linear Congruential Generator (LCG) in normalized [0..1] float space
// Exact modulo recurrence: X_{n+1} = (a * X_n + c) mod 1.0
float lcgRandom(inout float state) {
    state = fract(state * 1664.525 + 0.101390422);
    return state;
}

float normAngle(float a) {
    return a - TWO_PI * floor((a + PI) / TWO_PI);
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
// Evaluates multi-peak return strokes and subsequent dart-leader pulses
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
    // Incandescent plasma core (>30,000K) in HDR scale
    s.coreColor = vec3(1.0, 1.0, 1.0) * 85.0;
    // Ionization corona color (subtle cool ice-blue)
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
// 4-Pass Physical Plasma Emission Model
// Pass 1: Plasma Core (x8.0, razor-sharp incandescent white >30,000K)
// Pass 2: Inner Shell (x1.4, high energy bluish-white ionization sheath)
// Pass 3: Mid Corona (x0.25, pale lavender-ice electric glow)
// Pass 4: Outer Corona (x0.055, subtle cool blue atmospheric ionization)
// ------------------------------------------------------------------------------
void accumulatePlasma(float d, float weight, inout float totCore, inout float totInner, inout float totMid, inout float totOut) {
    float d2 = d * d;
    totCore  += exp(-d2 * 8.0)   * (75.0 * weight);
    totInner += exp(-d2 * 1.4)   * (14.0 * weight);
    totMid   += exp(-d2 * 0.25)  * (3.0  * weight);
    totOut   += exp(-d2 * 0.055) * (0.85 * weight);
}

vec3 evaluate4PassPlasma(float d0, float d1, float d2, float d3, float d4, float returnStroke, float intensity) {
    float totCore = 0.0;
    float totInner = 0.0;
    float totMid = 0.0;
    float totOut = 0.0;

    accumulatePlasma(d0, 1.00, totCore, totInner, totMid, totOut);
    accumulatePlasma(d1, 0.75, totCore, totInner, totMid, totOut);
    accumulatePlasma(d2, 0.56, totCore, totInner, totMid, totOut);
    accumulatePlasma(d3, 0.42, totCore, totInner, totMid, totOut);
    accumulatePlasma(d4, 0.31, totCore, totInner, totMid, totOut);

    const vec3 CORE_COLOR  = vec3(1.00, 1.00, 1.00);
    const vec3 INNER_COLOR = vec3(0.88, 0.94, 1.00);
    const vec3 MID_COLOR   = vec3(0.65, 0.78, 1.00);
    const vec3 OUTER_COLOR = vec3(0.35, 0.58, 1.00);

    return (totCore * returnStroke) * CORE_COLOR
         + (totInner * INNER_COLOR + totMid * MID_COLOR + totOut * OUTER_COLOR) * intensity;
}

// ------------------------------------------------------------------------------
// Procedural Stepped Leader Bolt Geometry (Cloud-to-Ground & Anvil Crawler)
// ------------------------------------------------------------------------------

// Dielectric breakdown branch starvation model:
// Probability of leader extinction scales with branch generation (order) as charge dissipates.
const float STARVE_BASE_RATE     = 0.040;
const float STARVE_GEN_INCREMENT = 0.045;
#define DIELECTRIC_STARVE_PROB(gen) (STARVE_BASE_RATE + float(gen) * (STARVE_GEN_INCREMENT + float(gen) * 0.003))

vec3 evaluateProceduralLightningBolt(vec3 rayDir, LightningStrike s) {
    #ifndef STORM_LIGHTNING
    return vec3(0.0);
    #endif

    #ifndef LIGHTNING_BOLTS
    return vec3(0.0);
    #endif

    if (!s.isTriggered || s.intensity < 0.005) return vec3(0.0);

    // Orthonormal basis centered on strike direction
    vec3 strikeUpRef = abs(dot(WORLD_UP, s.strikeDir)) > 0.99 ? vec3(0.0, 0.0, 1.0) : WORLD_UP;
    vec3 strikeRight = normalize(cross(strikeUpRef, s.strikeDir));
    vec3 strikeUp    = cross(s.strikeDir, strikeRight);

    float cosAngle = dot(rayDir, s.strikeDir);
    if (cosAngle < 0.20) return vec3(0.0); // Outside viewing cone

    vec2 p = vec2(dot(rayDir, strikeRight), dot(rayDir, strikeUp)) / cosAngle;

    // --- TYPE 2: INTRA-CLOUD (IC) / SHEET LIGHTNING ---
    // Deep volumetric scatter inside cloud volume; soft diffused internal glow
    if (s.strikeType == LIGHTNING_TYPE_IC) {
        vec2 icCenter = vec2((hash11(s.seed * 5.3) - 0.5) * 0.20, 0.30);
        float dIC = length(p - icCenter);

        float icCore = exp(-dIC * 4.5) * 2.5 * s.returnStroke;
        float icGlow = exp(-dIC * 2.0) * 1.2 * s.intensity;
        float fadeIC = 1.0 - smoothstep(0.20, 0.75, dIC);

        return (s.coreColor * icCore * 0.4 + s.sheathColor * (icCore + icGlow)) * fadeIC * LIGHTNING_INTENSITY;
    }

    // --- UNIFIED STEPPED LEADER: TYPE 0 (CG) & TYPE 1 (CC) ---
    bool isCG = (s.strikeType == LIGHTNING_TYPE_CG);

    // Bounding field check with smooth outer border fade
    float fadeX = 1.0 - smoothstep(isCG ? 0.48 : 0.62, isCG ? 0.72 : 0.88, abs(p.x));
    float fadeY = isCG
        ? ((1.0 - smoothstep(0.44, 0.56, p.y)) * smoothstep(-0.65, -0.52, p.y))
        : (1.0 - smoothstep(0.32, 0.52, abs(p.y)));
    float fieldFade = fadeX * fadeY;
    if (fieldFade <= 0.001) return vec3(0.0);

    float rng = isCG ? s.seed : (s.seed + 11.7);
    float startX = isCG ? (lcgRandom(rng) - 0.5) * 0.08 : -0.58;
    float startY = isCG ? 0.48 : (lcgRandom(rng) - 0.5) * 0.06;
    vec2 curPos = vec2(startX, startY);
    vec2 targetPos = isCG ? vec2(startX + (lcgRandom(rng) - 0.5) * 0.16, -0.50) : vec2(0.58, 0.0);
    float curAngle = isCG ? (-PI * 0.5 + (lcgRandom(rng) - 0.5) * 0.15) : ((lcgRandom(rng) - 0.5) * 0.12);
    float wander = (lcgRandom(rng) - 0.5) * 0.20;
    int trunkSteps = isCG ? 36 : 32;

    float minD_0 = 1e5;
    float minD_1 = 1e5;
    float minD_2 = 1e5;
    float minD_3 = 1e5;
    float minD_4 = 1e5;

    // Branch origination nodes for Gen 1 (up to 5 branches along trunk)
    #if LIGHTNING_BRANCH_GEN >= 1
    vec2 g1_pos[5];
    float g1_ang[5];
    float g1_thick[5];
    float g1_side[5];
    int g1_steps[5];
    int g1_count = 0;
    #endif

    // 1. TRUNK (Gen 0)
    for (int i = 0; i < 36; ++i) {
        if (i >= trunkSteps) break;

        if (isCG) {
            vec2 toTarget = targetPos - curPos;
            float targetAngle = atan(toTarget.y, toTarget.x);
            float diff = normAngle(targetAngle - curAngle);
            curAngle += diff * ((abs(diff) > 0.8) ? 0.28 : 0.22);
        } else {
            float targetAngle = -curPos.y * 0.8;
            curAngle += normAngle(targetAngle - curAngle) * 0.16;
        }

        float high = (lcgRandom(rng) - 0.5) * LIGHTNING_ROUGHNESS;
        wander = wander * 0.88 + high * 0.12 + (lcgRandom(rng) - 0.5) * 0.04;
        bool isKink = lcgRandom(rng) < 0.12;
        curAngle += wander + (isKink ? (high * 2.0) : (high * 0.50));

        if (isCG) {
            if (sin(curAngle) > -0.15) {
                curAngle = -PI * 0.5 + (lcgRandom(rng) - 0.5) * 0.60;
            }
        } else {
            curAngle = clamp(curAngle, -0.65, 0.65);
        }

        float remDist = isCG ? length(targetPos - curPos) : (0.58 - curPos.x);
        float baseLen = max(0.024, min(isCG ? 0.048 : 0.045, remDist / float(trunkSteps - i)));
        float stepLen = baseLen * mix(0.75, 1.25, lcgRandom(rng));

        vec2 nextPos = curPos + vec2(cos(curAngle), sin(curAngle)) * stepLen;
        float thick = 1.0 * mix(isCG ? 0.92 : 0.90, isCG ? 1.08 : 1.10, lcgRandom(rng));
        float chW = max(thick * 0.0038, 0.0020);
        float d = distToSegment2D(p, curPos, nextPos) / chW;
        minD_0 = min(minD_0, d);

        #if LIGHTNING_BRANCH_GEN >= 1
        bool isSlot = isCG ? (i == 4 || i == 10 || i == 16 || i == 22 || i == 28)
                           : (i == 3 || i == 9  || i == 15 || i == 21 || i == 27);
        if (g1_count < 5 && isSlot) {
            float side = (mod(float(g1_count), 2.0) < 0.5) ? 1.0 : -1.0;
            float offset = radians((isCG ? 30.0 : 32.0) + lcgRandom(rng) * (isCG ? 15.0 : 16.0)) * side;
            float childAngle = curAngle + offset + (lcgRandom(rng) - 0.5) * 0.20;
            if (!isCG || sin(childAngle) < 0.25) {
                g1_pos[g1_count]   = nextPos;
                g1_ang[g1_count]   = childAngle;
                g1_thick[g1_count] = thick * mix(isCG ? 0.52 : 0.50, 0.68, lcgRandom(rng));
                g1_side[g1_count]  = side;
                g1_steps[g1_count] = int(clamp(float(trunkSteps) * mix(0.28, 0.45, lcgRandom(rng)), isCG ? 6.0 : 5.0, isCG ? 12.0 : 10.0));
                g1_count++;
            }
        }
        #endif

        curPos = nextPos;
        if (isCG ? (curPos.y <= targetPos.y - 0.01) : (curPos.x >= 0.58)) break;
    }

    vec2 groundImpact = curPos;

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

            if (isCG) {
                vec2 toTarget = targetPos - cPos;
                cAng += normAngle(atan(toTarget.y, toTarget.x) - cAng) * 0.12;
            }

            float high = (lcgRandom(rng) - 0.5) * bRough;
            bWander = bWander * 0.88 + high * 0.12 + (lcgRandom(rng) - 0.5) * 0.04;
            bool isKink = lcgRandom(rng) < 0.12;
            cAng += bWander + (isKink ? (high * 2.0) : (high * 0.50));

            if (isCG && sin(cAng) > 0.25) {
                cAng = -PI * 0.5 + (lcgRandom(rng) - 0.5) * 0.80;
            }

            float stepLen = mix(0.014, 0.024, lcgRandom(rng)) * 0.85;
            vec2 nextPos = cPos + vec2(cos(cAng), sin(cAng)) * stepLen;
            float thick = bThick * mix(0.90, 1.10, lcgRandom(rng));
            float chW = max(thick * 0.0038, 0.0020);
            float d = distToSegment2D(p, cPos, nextPos) / chW;
            minD_1 = min(minD_1, d);

            #if LIGHTNING_BRANCH_GEN >= 2
            if (g2_count < 5 && (s == 2 || s == 4)) {
                float twSide = (s == 2) ? -bSide : bSide;
                float twOffset = radians(30.0 + lcgRandom(rng) * (isCG ? 15.0 : 16.0)) * twSide;
                float twAng = cAng + twOffset + (lcgRandom(rng) - 0.5) * 0.20;
                if (!isCG || sin(twAng) < 0.25) {
                    g2_pos[g2_count]   = nextPos;
                    g2_ang[g2_count]   = twAng;
                    g2_thick[g2_count] = thick * mix(isCG ? 0.50 : 0.48, 0.68, lcgRandom(rng));
                    g2_side[g2_count]  = twSide;
                    g2_steps[g2_count] = int(clamp(float(maxSteps) * mix(0.40, 0.65, lcgRandom(rng)), 3.0, isCG ? 7.0 : 6.0));
                    g2_count++;
                }
            }
            #endif

            cPos = nextPos;
            if (s > 3 && lcgRandom(rng) < DIELECTRIC_STARVE_PROB(1)) break;
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

            if (isCG && sin(cAng) > 0.25) {
                cAng = -PI * 0.5 + (lcgRandom(rng) - 0.5) * 0.80;
            }

            float stepLen = mix(0.010, 0.018, lcgRandom(rng));
            vec2 nextPos = cPos + vec2(cos(cAng), sin(cAng)) * stepLen;
            float thick = tThick * mix(0.90, 1.10, lcgRandom(rng));
            float chW = max(thick * 0.0038, 0.0020);
            float d = distToSegment2D(p, cPos, nextPos) / chW;
            minD_2 = min(minD_2, d);

            #if LIGHTNING_BRANCH_GEN >= 3
            if (g3_count < 4 && s == 2) {
                float subSide = -tSide;
                float subOffset = radians(30.0 + lcgRandom(rng) * 15.0) * subSide;
                float subAng = cAng + subOffset;
                if (!isCG || sin(subAng) < 0.28) {
                    g3_pos[g3_count]   = nextPos;
                    g3_ang[g3_count]   = subAng;
                    g3_thick[g3_count] = thick * mix(0.50, 0.70, lcgRandom(rng));
                    g3_side[g3_count]  = subSide;
                    g3_steps[g3_count] = int(clamp(float(maxSteps) * mix(0.45, 0.75, lcgRandom(rng)), 2.0, 5.0));
                    g3_count++;
                }
            }
            #endif

            cPos = nextPos;
            if (s > 2 && lcgRandom(rng) < DIELECTRIC_STARVE_PROB(2)) break;
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
            minD_3 = min(minD_3, d);

            #if LIGHTNING_BRANCH_GEN >= 4
            if (g4_count < 4 && s == 1) {
                float filSide = -sSide;
                float filOffset = radians(30.0 + lcgRandom(rng) * 15.0) * filSide;
                g4_pos[g4_count]   = nextPos;
                g4_ang[g4_count]   = cAng + filOffset;
                g4_thick[g4_count] = thick * 0.60;
                g4_count++;
            }
            #endif

            cPos = nextPos;
            if (s > 1 && lcgRandom(rng) < DIELECTRIC_STARVE_PROB(3)) break;
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
            minD_4 = min(minD_4, d);
            cPos = nextPos;
        }
    }
    #endif

    // Evaluate 4-Pass Plasma Rendering across all generations
    vec3 boltCol = evaluate4PassPlasma(minD_0, minD_1, minD_2, minD_3, minD_4, s.returnStroke, s.intensity);

    vec3 originCol = vec3(0.0);
    vec3 impactCol = vec3(0.0);

    if (isCG) {
        // Origin Radial Cloud Illumination (where bolt emerges from storm clouds)
        float dOrigin = length((p - vec2(startX, 0.48)) * vec2(1.0, 1.4));
        float originGlow = (exp(-dOrigin * dOrigin / 0.006) * 3.5 + exp(-dOrigin / 0.05) * 1.2) * s.intensity;
        originCol = vec3(0.65, 0.78, 1.0) * originGlow;

        // Ground strike impact reflection: intense localized impact burst at strike coordinates
        vec2 impactP = (p - groundImpact) * vec2(2.0, 4.0);
        float dImpact = length(impactP);
        float impactCore = exp(-dImpact * dImpact / 0.00008) * 40.0 * s.returnStroke;
        float impactGlow = exp(-dImpact / 0.018) * 4.2 * s.intensity;
        impactCol = (vec3(1.0) * impactCore + vec3(0.65, 0.80, 1.0) * impactGlow);
    }

    return (boltCol + originCol + impactCol) * fieldFade * LIGHTNING_INTENSITY;
}

// ------------------------------------------------------------------------------
// Volumetric Intra-Cloud Scattering & Multiple-Scattering Lighting
// Evaluated for 3D point 'pos' with cloud density 'density' inside raymarch loop
// ------------------------------------------------------------------------------
vec3 evaluateIntraCloudLighting(vec3 pos, float density, LightningStrike s, vec3 rayDir) {
    #ifndef STORM_LIGHTNING
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

    // Internal billow scattering emission:
    // Core white radiance is de-amplified from bolt HDR scale (85.0 -> 3.4) while corona sheath provides color tinting
    const float CLOUD_CORE_SCALE   = 0.04;
    const float CLOUD_SHEATH_SCALE = 2.20;
    vec3 emission = (s.coreColor * CLOUD_CORE_SCALE + s.sheathColor * CLOUD_SHEATH_SCALE) * s.intensity * LIGHTNING_INTENSITY;
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
