#ifndef CELESTIALS_GLSL
#define CELESTIALS_GLSL

#include "settings.glsl"
#include "common.glsl"
#include "noise.glsl"
#include "biome.glsl"

/*
 * ==============================================================================
 *  CELESTIAL OBJECTS (HIGH-END BIOME-AWARE EDITION)
 *  Sun with diffraction spikes, 8-phase Moon with maria, Meteor showers,
 *  Multi-layer Aurora Borealis, and Milky Way Galaxy
 * ==============================================================================
 */

// Procedural realistic Sun disc, limb darkening, chromatic plasma corona, glare, and anamorphic diffraction spikes
vec4 renderSunBillboard(vec2 localCoord, float distToCenter, float sunHeight, float rainStrength, BiomeAtmosphere biomeAtm) {
    if (rainStrength > 0.95 || sunHeight < -0.18) return vec4(0.0);

    // Physically based solar radiance attenuated by atmospheric transmittance
    vec3 physicalSun = getSunColor(sunHeight, 0.0) * (3.8 / max(ATM_SOLAR_IRRADIANCE.r * 0.14, 0.01));
    vec3 currentSunColor = max(physicalSun, vec3(0.02, 0.005, 0.001));

    if (biomeAtm.isArid) {
        currentSunColor = mix(currentSunColor, currentSunColor * vec3(1.15, 0.85, 0.60), biomeAtm.sandstormFactor);
    }

    // Khúc xạ khí quyển nén dẹt trục thẳng đứng khi mặt trời sát chân trời
    vec2 sunCoord = localCoord;
    #ifdef SUN_ATMOSPHERIC_FLATTENING
    float flattenFactor = 1.0 + clamp((0.15 - sunHeight) * 2.2, 0.0, 0.45);
    sunCoord.y *= flattenFactor;
    #endif
    float flatDist = length(sunCoord);

    float discRadius = 0.48 * SUN_SIZE;
    vec3 sunEmission = vec3(0.0);
    float alpha = 0.0;

    // 1. Đĩa Mặt trời sắc nét với nén dải động HDR quang cầu (chống cháy trắng hoàn toàn viền Eddington)
    if (flatDist < discRadius) {
        float r = flatDist / discRadius;
        #ifdef SUN_LIMB_DARKENING
        float mu = sqrt(max(1.0 - r * r, 0.0));
        float limbDarkening = 0.40 + 0.60 * pow(mu, 0.55);
        vec3 limbTint = mix(vec3(1.08, 0.58, 0.22), vec3(1.0), pow(mu, 0.30));
        #else
        float limbDarkening = 1.0;
        vec3 limbTint = vec3(1.0);
        #endif
        float edgeAA = 1.0 - smoothstep(0.93, 1.0, r);
        // Photospheric core: center reaches pure white, limb softly rolls off to golden-amber
        vec3 discColor = currentSunColor * limbDarkening * limbTint;
        float coreIncandescence = pow(max(1.0 - r, 0.0), 1.6) * 2.8;
        sunEmission += (discColor + vec3(coreIncandescence)) * edgeAA;
        alpha = max(alpha, edgeAA);
    }

    // 2. Quầng nhật hoa đa tầng (K-Corona plasma bám sát + F-Corona bụi khuếch tán rộng)
    if (SUN_CORONA_INTENSITY > 0.001) {
        float rRel = max(flatDist - discRadius, 0.0) / discRadius;
        float kCorona = exp(-rRel * 7.5) * 0.72; // Inner dense plasma envelope
        float fCorona = exp(-rRel * 2.4) * 0.28; // Outer soft dust halo
        float coronaGlow = (kCorona + fCorona) * 0.85 * SUN_CORONA_INTENSITY;

        #ifdef SUN_CHROMATIC_CORONA
        vec3 coronaColor = mix(vec3(1.0, 0.52, 0.16), currentSunColor, exp(-rRel * 3.0));
        #else
        vec3 coronaColor = currentSunColor;
        #endif
        sunEmission += coronaColor * coronaGlow;
        alpha = max(alpha, clamp(coronaGlow * 1.5, 0.0, 1.0));
    }

    // 3. Hào quang tán xạ dịu êm
    #ifdef SUN_GLARE
    float glare = exp(-flatDist * 3.2) * 0.16 * biomeAtm.hazeDensity;
    sunEmission += currentSunColor * glare;
    alpha = max(alpha, clamp(glare * 1.5, 0.0, 1.0));
    #endif

    // 4. Tia lóe nhiễu xạ 6 cánh tán sắc quang phổ cầu vồng (Chromatic Spectral Dispersion)
    #ifdef SOLAR_DIFFRACTION_SPIKES
    float spAngle1 = 0.0;
    float spAngle2 = 1.047197; // 60 deg
    float spAngle3 = 2.094395; // 120 deg
    
    vec2 p1 = vec2(localCoord.x * cos(spAngle1) - localCoord.y * sin(spAngle1), localCoord.x * sin(spAngle1) + localCoord.y * cos(spAngle1));
    vec2 p2 = vec2(localCoord.x * cos(spAngle2) - localCoord.y * sin(spAngle2), localCoord.x * sin(spAngle2) + localCoord.y * cos(spAngle2));
    vec2 p3 = vec2(localCoord.x * cos(spAngle3) - localCoord.y * sin(spAngle3), localCoord.x * sin(spAngle3) + localCoord.y * cos(spAngle3));

    // Wavelength-dependent diffraction widths: Red spreads wider, Blue is narrower
    vec3 s1 = vec3(
        exp(-abs(p1.y) * 11.5) / (abs(p1.x) * 2.0 + 1.0),
        exp(-abs(p1.y) * 15.0) / (abs(p1.x) * 2.4 + 1.0),
        exp(-abs(p1.y) * 19.5) / (abs(p1.x) * 2.8 + 1.0)
    );
    vec3 s2 = vec3(
        exp(-abs(p2.y) * 11.5) / (abs(p2.x) * 2.0 + 1.0),
        exp(-abs(p2.y) * 15.0) / (abs(p2.x) * 2.4 + 1.0),
        exp(-abs(p2.y) * 19.5) / (abs(p2.x) * 2.8 + 1.0)
    );
    vec3 s3 = vec3(
        exp(-abs(p3.y) * 11.5) / (abs(p3.x) * 2.0 + 1.0),
        exp(-abs(p3.y) * 15.0) / (abs(p3.x) * 2.4 + 1.0),
        exp(-abs(p3.y) * 19.5) / (abs(p3.x) * 2.8 + 1.0)
    );

    vec3 spike = (s1 + s2 + s3) * exp(-flatDist * 2.4) * 0.65;
    vec3 spikeColor = mix(vec3(1.1, 0.92, 0.75), currentSunColor, 0.5);
    sunEmission += spikeColor * spike;
    alpha = max(alpha, clamp(max(max(spike.r, spike.g), spike.b) * 1.5, 0.0, 1.0));
    #endif

    // Suy giảm mượt ở biên ngoài quad, hoàn toàn không để lại vết cắt hay ranh giới tròn
    float quadFade = 1.0 - smoothstep(0.65, 1.0, distToCenter);
    sunEmission *= quadFade;
    alpha *= quadFade;

    float weatherFade = 1.0 - rainStrength * 0.90;
    return vec4(sunEmission * weatherFade, alpha * weatherFade);
}

// Procedural high-detail Moon with spherical mapping, maria, craters, exact 8-phases terminator, Lommel-Seeliger scattering, Earthshine and halo
vec4 renderMoonBillboard(vec2 localCoord, float distToCenter, vec3 sunDir, vec3 moonDir, vec3 upVector, int moonPhase, float sunHeight, float rainStrength, BiomeAtmosphere biomeAtm) {
    if (rainStrength > 0.92 || sunHeight > 0.18) return vec4(0.0);

    float nightFactor = clamp(-sunHeight * 8.0, 0.0, 1.0);
    float discRadius = 0.48 * MOON_SIZE;
    // Tông màu bạc ánh trăng tự nhiên dịu mát
    vec3 moonBaseColor = vec3(0.92, 0.94, 0.97);
    vec3 moonEmission = vec3(0.0);
    float alpha = 0.0;

    if (distToCenter < discRadius) {
        float r = distToCenter / discRadius;
        float edgeAA = 1.0 - smoothstep(0.93, 1.0, r);

        float normalZ = sqrt(max(1.0 - r * r, 0.0));
        vec3 sphereNormal = vec3(localCoord / discRadius, normalZ);

        // Spherical UV projection (preserves real spherical geometry & foreshortens naturally toward limb)
        float moonLon = atan(sphereNormal.x, sphereNormal.z);
        float moonLat = asin(clamp(sphereNormal.y, -1.0, 1.0));
        vec2 surfaceUV = vec2(moonLon * (1.0 / PI) + 0.5, moonLat * (2.0 / PI) + 0.5);

        // Chi tiết bề mặt biển bazan (maria) và các tia bắn miệng hố
        #ifdef MOON_SURFACE_DETAIL
        // Realistic Lunar geography:
        // Oceanus Procellarum & Mare Imbrium (northwest basalt plains)
        float mareBase = fbm2D_Detailed(surfaceUV * 2.8);
        float mareMask = smoothstep(0.40, 0.65, mareBase);
        
        // Tycho crater & ray system (southern highlands impact radiating rays)
        vec2 tychoPos = vec2(0.48, 0.28);
        float distTycho = length(surfaceUV - tychoPos);
        float tychoAngle = atan(surfaceUV.y - tychoPos.y, surfaceUV.x - tychoPos.x);
        float tychoRays = pow(abs(sin(tychoAngle * 8.0)), 6.0) * exp(-distTycho * 3.5);

        // Impact cratering with natural scale distribution
        float craters = 1.0 - voronoi2D(surfaceUV * 5.5);
        float microCraters = 1.0 - voronoi2D(surfaceUV * 12.0);

        float albedo = mix(0.52, 1.08, mareMask);
        albedo += tychoRays * 0.28;
        albedo += craters * 0.14 + microCraters * 0.08;
        #else
        float albedo = 1.0;
        #endif

        // Chu kỳ 8 pha mặt trăng với hướng ánh sáng vật lý chính xác theo mặt trời
        #ifdef MOON_PHASES
        vec3 safeUp = abs(dot(moonDir, upVector)) > 0.99 ? vec3(0.0, 0.0, 1.0) : upVector;
        vec3 moonRight = normalize(cross(moonDir, safeUp));
        vec3 moonUp    = cross(moonRight, moonDir);
        float sunProjX = dot(sunDir, moonRight);
        float sunProjY = dot(sunDir, moonUp);
        vec2 sunTangentDir = normalize(vec2(sunProjX, sunProjY) + vec2(1e-5));

        float phaseAngle = float(moonPhase) * (TWO_PI / 8.0);
        float lightZ = cos(phaseAngle);
        float lightTransverse = -sin(phaseAngle);
        vec3 phaseLightDir = normalize(vec3(sunTangentDir * lightTransverse, lightZ));

        #ifdef MOON_CRATER_RELIEF
        vec2 eps = vec2(0.03, 0.0);
        float hL = fbm2D(surfaceUV * 6.0 - eps.xy);
        float hR = fbm2D(surfaceUV * 6.0 + eps.xy);
        float hD = fbm2D(surfaceUV * 6.0 - eps.yx);
        float hU = fbm2D(surfaceUV * 6.0 + eps.yx);
        vec2 smoothGrad = vec2(hR - hL, hU - hD) * 1.5;

        float termProximity = 1.0 - smoothstep(0.0, 0.25, abs(dot(sphereNormal, phaseLightDir)));
        vec3 perturbedNormal = normalize(sphereNormal + vec3(smoothGrad * 0.15 * termProximity, 0.0));
        #else
        vec3 perturbedNormal = sphereNormal;
        #endif

        float NdotL = dot(perturbedNormal, phaseLightDir);
        // Lommel-Seeliger lunar regolith reflection
        float mu0 = max(NdotL, 0.0);
        float mu = max(perturbedNormal.z, 0.0);
        float regolithScatter = mu0 / (mu0 + mu + 1e-3) * 1.75;
        
        // Exact sharp-yet-soft physical terminator (không bị méo trứng ở pha lưỡi liềm)
        float terminator = smoothstep(-0.03, 0.04, NdotL);
        float illumination = mix(0.0, regolithScatter, terminator);

        #ifdef MOON_EARTHSHINE
        // Subtle planetary Earthshine (ánh đất xanh lam phản xạ từ đại dương Trái Đất)
        float earthPhase = 1.0 - cos(phaseAngle) * 0.5;
        vec3 earthshineColor = vec3(0.025, 0.038, 0.060) * earthPhase * (1.0 - terminator);
        #else
        vec3 earthshineColor = vec3(0.0);
        #endif
        #else
        float illumination = 1.0;
        vec3 earthshineColor = vec3(0.0);
        #endif

        moonEmission += (moonBaseColor * albedo * illumination * (0.85 * MOON_BRIGHTNESS) + earthshineColor) * edgeAA;
        alpha = max(alpha, edgeAA);
    }

    // Quầng sáng khí quyển & vòng tinh thể băng 22 độ (Lunar Halo)
    #ifdef MOON_HALO
    float haloGlow = exp(-distToCenter * 2.5) * 0.040 * MOON_HALO_INTENSITY;
    haloGlow *= mix(1.0, 1.4, biomeAtm.auroraStrength / 1.8);

    float ringR = abs(distToCenter - 0.68);
    float ringIntensity = (biomeAtm.isCold ? 0.040 : 0.012) * MOON_HALO_INTENSITY;
    float haloRing = exp(-ringR * ringR * 32.0) * ringIntensity;

    vec3 haloColor = vec3(0.68, 0.78, 0.95);
    moonEmission += haloColor * (haloGlow + haloRing);
    alpha = max(alpha, clamp((haloGlow + haloRing) * 1.2, 0.0, 1.0));
    #endif

    // Suy giảm mượt ở biên ngoài billboard quad (mở rộng vùng suy giảm để quầng băng không bị cắt góc)
    float quadFade = 1.0 - smoothstep(0.82, 1.0, distToCenter);
    moonEmission *= quadFade;
    alpha *= quadFade;

    float weatherFade = (1.0 - rainStrength * 0.90) * nightFactor;
    return vec4(moonEmission * weatherFade, alpha * weatherFade);
}

// Shooting star / meteor streaks with 3D capsule line segment distance and ionization trail
vec3 renderMeteors(vec3 rayDir, float timeSec) {
    #ifndef METEOR_SHOWERS
    return vec3(0.0);
    #endif

    float cycle = floor(timeSec * 0.35);
    float localT = fract(timeSec * 0.35);

    float meteorSeed = hash11(cycle * 78.43);
    if (meteorSeed > 0.45) {
        // Trajectory start and end points in upper celestial hemisphere
        vec3 startPos = normalize(vec3(
            hash11(cycle * 12.1 + 1.0) * 1.8 - 0.9,
            0.45 + hash11(cycle * 34.2 + 2.0) * 0.45,
            hash11(cycle * 56.3 + 3.0) * 1.8 - 0.9
        ));
        vec3 meteorVel = normalize(vec3(
            hash11(cycle * 71.5 + 4.0) * 1.4 - 0.7,
            -0.35 - hash11(cycle * 83.2 + 5.0) * 0.3,
            hash11(cycle * 92.8 + 6.0) * 1.4 - 0.7
        ));
        
        // Fast streak duration ~ 0.45s
        float progress = localT * 2.8;
        if (progress > 0.0 && progress < 1.0) {
            float streakLen = 0.25;
            vec3 headPos = normalize(startPos + meteorVel * progress * 0.70);
            vec3 tailPos = normalize(startPos + meteorVel * max(progress * 0.70 - streakLen, 0.0));
            
            // Distance from ray to 3D line segment (headPos to tailPos)
            vec3 ab = headPos - tailPos;
            vec3 ap = rayDir - tailPos;
            float h = clamp(dot(ap, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
            float distToStreak = length(ap - ab * h);
            
            if (distToStreak < 0.025) {
                float intensity = exp(-distToStreak * 650.0);
                float tailFade = pow(h, 2.5); // brightest at head, fades toward tail
                
                // Mineral emission color: magnesium (teal/green) or sodium (golden white)
                vec3 meteorColor = mix(vec3(0.65, 0.95, 1.0), vec3(1.0, 0.92, 0.75), hash11(cycle * 3.1));
                return meteorColor * intensity * tailFade * 8.5;
            }
        }
    }
    return vec3(0.0);
}

// ==============================================================================
//  NASA SVS 4851 DEEP STAR MAPS 2020 INTEGRATION
// ==============================================================================

uniform sampler2D milkyway;
uniform sampler2D constellations;
uniform sampler2D celestialgrid;

// Ballesteros (2012) formula mapping B-V color index to effective temperature (K)
// NASA SVS 4851: T_eff = 4600 * ( 1 / (0.92*(B-V) + 1.7) + 1 / (0.92*(B-V) + 0.62) )
float ballesterosTeff(float bv) {
    float c = 0.92 * bv;
    return 4600.0 * (1.0 / (c + 1.70) + 1.0 / (c + 0.62));
}

// Map effective temperature (Kelvin) to RGB blackbody spectrum (Mitchell Charity / Planckian locus)
vec3 blackbodyToRGB(float tempK) {
    float t = clamp(tempK, 1500.0, 35000.0) / 100.0;
    vec3 rgb;
    if (t <= 66.0) {
        rgb.r = 1.0;
    } else {
        rgb.r = clamp(pow((t - 60.0) / 100.0, -0.1332) * 1.29, 0.0, 1.0);
    }
    if (t <= 66.0) {
        rgb.g = clamp(log(max(t, 1.0)) * 0.39008 - 0.6318, 0.0, 1.0);
    } else {
        rgb.g = clamp(pow(t - 60.0, -0.0755) * 1.129, 0.0, 1.0);
    }
    if (t >= 66.0) {
        rgb.b = 1.0;
    } else if (t <= 19.0) {
        rgb.b = 0.0;
    } else {
        rgb.b = clamp(log(max(t - 10.0, 1.0)) * 0.5432 - 1.196, 0.0, 1.0);
    }
    return rgb;
}

vec3 getStarColorFromBV(float bv) {
    #ifdef STARS_COLOR_VARIETY
    float teff = ballesterosTeff(bv);
    return blackbodyToRGB(teff);
    #else
    return vec3(0.96, 0.98, 1.0);
    #endif
}

// Transforms Minecraft world view ray to J2000 Celestial Coordinates with diurnal rotation
vec3 worldToCelestial(vec3 worldDir, int worldTimeTicks) {
    float latRad = radians(CELESTIAL_LATITUDE);
    float sinLat = sin(latRad);
    float cosLat = cos(latRad);

    // Observer orientation: North is -Z, East is +X, Up is +Y
    float vEast = worldDir.x;
    float vMeridian = worldDir.y * cosLat + worldDir.z * sinLat;
    float vPole = worldDir.y * sinLat - worldDir.z * cosLat;

    // Diurnal rotation angle around celestial pole (East to West)
    float diurnalAngle = (float(worldTimeTicks) / 24000.0) * TWO_PI;
    float cosD = cos(diurnalAngle);
    float sinD = sin(diurnalAngle);

    float xCel = vEast * cosD - vMeridian * sinD;
    float zCel = vEast * sinD + vMeridian * cosD;
    float yCel = vPole;

    return normalize(vec3(xCel, yCel, zCel));
}

// Fast & precise inverse sRGB EOTF (HLSL / Jim Cowlishaw approximation)
// Maps non-linear sRGB texture data to physical linear HDR radiometric space
vec3 srgbToLinear(vec3 srgb) {
    return srgb * (srgb * (srgb * 0.305306011 + 0.682171111) + 0.012522878);
}

// Convert Celestial unit vector to NASA SVS equirectangular UV coordinates
// Matches standard celestial panorama mapping used in Photon Shader
vec2 celestialToNASA_UV(vec3 celDir) {
    float lon = atan(celDir.x, celDir.z);
    float lat = acos(clamp(-celDir.y, -1.0, 1.0));
    return vec2(lon * (0.5 * INV_PI) + 0.5, lat * INV_PI);
}

vec3 raDecToCel(float raHours, float decDeg) {
    float raRad = raHours * (TWO_PI / 24.0);
    float decRad = radians(decDeg);
    float cosDec = cos(decRad);
    return vec3(cosDec * sin(raRad), sin(decRad), cosDec * cos(raRad));
}

// Consolidated chromatic twinkling calculation for stars (SSOC)
vec3 calculateStarTwinkle(float timeSec, float speed, float phase, float amp) {
    #ifdef STARS_TWINKLE
    float p = timeSec * speed + phase;
    return vec3(
        sin(p + 0.0) * amp + (1.0 - amp),
        sin(p + 0.4) * amp + (1.0 - amp),
        sin(p + 0.8) * amp + (1.0 - amp)
    );
    #else
    return vec3(1.0);
    #endif
}

vec3 renderBrightStar(vec3 celDir, vec3 starPos, float bv, float brightness, float size, float timeSec, float seed) {
    float cosA = dot(celDir, starPos);
    if (cosA < 0.9992) return vec3(0.0);

    float angle = acos(clamp(cosA, -1.0, 1.0));
    float radius = size * 0.0019;
    if (angle > radius * 6.0) return vec3(0.0);

    float twinkleSpeed = 3.2 + hash11(seed * 19.3) * 5.5;
    vec3 twinkle = calculateStarTwinkle(timeSec, twinkleSpeed, seed * 6.28, 0.32);

    vec3 starColor = getStarColorFromBV(bv);
    float core = exp(-angle / (radius * 0.42)) * 4.2;
    float halo = exp(-angle / (radius * 1.8)) * 0.75;

    return starColor * (core + halo) * brightness * twinkle;
}

// Procedural dense star background using 6-face Cubemap Lattice
// Eliminates polar singularities, latitude pinching, and 3D voxel clipping
vec3 renderProceduralStars(vec3 celDir, float timeSec, float galaxyLuminance) {
    vec3 starsColor = vec3(0.0);

    // Layer 1: High-density faint background stars
    {
        vec3 a = abs(celDir);
        vec2 uv;
        float faceId = 0.0;
        if (a.x >= a.y && a.x >= a.z) {
            uv = celDir.yz / a.x;
            faceId = (celDir.x > 0.0) ? 1.0 : 2.0;
        } else if (a.y >= a.x && a.y >= a.z) {
            uv = celDir.xz / a.y;
            faceId = (celDir.y > 0.0) ? 3.0 : 4.0;
        } else {
            uv = celDir.xy / a.z;
            faceId = (celDir.z > 0.0) ? 5.0 : 6.0;
        }

        float scale = 160.0 * STARS_DENSITY;
        vec2 gridPos = uv * scale;
        vec2 cell = floor(gridPos);
        vec2 frac = fract(gridPos) - 0.5;

        vec2 cellKey = cell + vec2(faceId * 71.3, faceId * 37.9);
        vec2 jitter = hash22(cellKey) - 0.5;
        vec2 delta = frac - jitter * 0.72;

        float starRandom = hash21(cellKey + vec2(1.7, 9.2));
        float densityThreshold = clamp(0.78 - galaxyLuminance * 0.35, 0.52, 0.82);

        if (starRandom > densityThreshold) {
            float starDist = length(delta);
            float starSize = 0.07 + (starRandom - densityThreshold) * 1.2;

            float twinkleSpeed = 2.0 + hash21(cellKey + 5.0) * 6.5;
            vec3 twinkle = calculateStarTwinkle(timeSec, twinkleSpeed, starRandom * 62.8, 0.35);

            float bv = hash21(cellKey + 12.0) * 2.1 - 0.3;
            vec3 starTint = getStarColorFromBV(bv);

            float core = exp(-starDist * starDist / (starSize * starSize * 0.06));
            float halo = exp(-starDist / (starSize * 0.65)) * 0.15;
            starsColor += starTint * (core + halo) * twinkle * 1.6;
        }
    }

    // Layer 2: Medium-density brighter foreground stars (rotated coordinate frame)
    {
        mat3 rot = mat3(
            0.80,  0.36, -0.48,
           -0.36,  0.93,  0.10,
            0.48,  0.10,  0.87
        );
        vec3 rotDir = rot * celDir;
        vec3 a = abs(rotDir);
        vec2 uv2;
        float faceId2 = 0.0;
        if (a.x >= a.y && a.x >= a.z) {
            uv2 = rotDir.yz / a.x;
            faceId2 = (rotDir.x > 0.0) ? 1.0 : 2.0;
        } else if (a.y >= a.x && a.y >= a.z) {
            uv2 = rotDir.xz / a.y;
            faceId2 = (rotDir.y > 0.0) ? 3.0 : 4.0;
        } else {
            uv2 = rotDir.xy / a.z;
            faceId2 = (rotDir.z > 0.0) ? 5.0 : 6.0;
        }

        float scale2 = 105.0 * STARS_DENSITY;
        vec2 gridPos2 = uv2 * scale2;
        vec2 cell2 = floor(gridPos2);
        vec2 frac2 = fract(gridPos2) - 0.5;

        vec2 cellKey2 = cell2 + vec2(faceId2 * 53.7 + 100.0, faceId2 * 29.1 + 50.0);
        vec2 jitter2 = hash22(cellKey2) - 0.5;
        vec2 delta2 = frac2 - jitter2 * 0.72;

        float starRandom2 = hash21(cellKey2 + vec2(3.1, 7.8));
        float densityThreshold2 = clamp(0.85 - galaxyLuminance * 0.25, 0.65, 0.88);

        if (starRandom2 > densityThreshold2) {
            float starDist2 = length(delta2);
            float starSize2 = 0.09 + (starRandom2 - densityThreshold2) * 1.5;

            float twinkleSpeed2 = 1.8 + hash21(cellKey2 + 9.0) * 5.5;
            vec3 twinkle2 = calculateStarTwinkle(timeSec, twinkleSpeed2, starRandom2 * 51.4, 0.30);

            float bv2 = hash21(cellKey2 + 7.0) * 2.0 - 0.25;
            vec3 starTint2 = getStarColorFromBV(bv2);

            float core2 = exp(-starDist2 * starDist2 / (starSize2 * starSize2 * 0.07));
            float halo2 = exp(-starDist2 / (starSize2 * 0.70)) * 0.20;
            starsColor += starTint2 * (core2 + halo2) * twinkle2 * 2.2;
        }
    }

    return starsColor;
}

// Primary Night Sky Compositor: NASA SVS 4851 Milky Way, Stars, Meteors & Auroras (8-param with Lunar Washout)
vec3 renderStarsAndMilkyWay(vec3 rayDir, vec3 moonDir, int moonPhase, float sunHeight, float rain, float timeSec, int worldTimeTicks, BiomeAtmosphere biomeAtm) {
    #ifndef ENABLE_STARS
    return vec3(0.0);
    #endif

    if (rain > 0.4 || sunHeight > -0.04 || rayDir.y < 0.0) return vec3(0.0);

    // Smooth night transition curve without harsh steps
    float nightStrength = clamp(-sunHeight * 10.0 - 0.1, 0.0, 1.0);
    
    // Physical atmospheric extinction along view ray (thick air at horizon dims celestials)
    float opticalAirMass = 1.0 / max(rayDir.y + 0.08, 0.08);
    float atmExtinction  = exp(-0.06 * opticalAirMass);
    float horizonMask    = smoothstep(0.015, 0.22, rayDir.y) * atmExtinction;
    float visibility     = nightStrength * horizonMask * (1.0 - rain * 2.0);
    if (visibility <= 0.0) return vec3(0.0);

    // Lunar sky wash-out (Bortle scale simulation)
    // When the moon is high and bright, nocturnal Rayleigh/Mie airglow washes out faint cosmos
    float moonElev = dot(moonDir, WORLD_UP);
    float lunarIllum = (moonPhase == 0) ? 1.0 : ((moonPhase == 1 || moonPhase == 7) ? 0.72 : ((moonPhase == 2 || moonPhase == 6) ? 0.45 : ((moonPhase == 3 || moonPhase == 5) ? 0.18 : 0.0)));
    float moonWashout = clamp(moonElev * 1.5, 0.0, 1.0) * lunarIllum * 0.60;
    float cosmosVisibility = visibility * (1.0 - moonWashout);

    vec3 sphereDir = normalize(rayDir);
    vec3 celDir = worldToCelestial(sphereDir, worldTimeTicks);
    vec2 nasaUV = celestialToNASA_UV(celDir);

    vec3 starsColor = vec3(0.0);
    float galaxyLuminance = 0.0;

    // 1. Milky Way Galaxy Band (Natural NASA SVS 4851 photometric color palette)
    #ifdef MILKY_WAY
    #ifdef NASA_SVS_MILKY_WAY
    vec4 mwSample = texture2D(milkyway, nasaUV);
    
    // Inverse sRGB EOTF: prevents black space from turning into a bright hazy fog
    vec3 mwLinear = srgbToLinear(mwSample.rgb);
    
    // Warm golden galactic core (population II stars) with cool dark dust lanes
    const vec3 galaxyTint = vec3(1.08, 0.98, 0.88);
    vec3 mwColor = mwLinear * galaxyTint * MILKY_WAY_BRIGHTNESS;
    
    // Gentle saturation preservation without neon purple tint
    galaxyLuminance = dot(mwColor, vec3(0.2126, 0.7152, 0.0722));
    mwColor = mix(vec3(galaxyLuminance), mwColor, 1.35);

    #ifdef MILKY_WAY_H_ALPHA
    // Hydrogen-alpha (656.3 nm) deep crimson/magenta emission nebula enhancement
    float hAlphaMask = clamp(mwSample.r * 1.6 - (mwSample.g * 0.8 + mwSample.b * 0.8), 0.0, 1.0);
    vec3 hAlphaColor = vec3(0.95, 0.12, 0.28) * hAlphaMask * 0.28 * MILKY_WAY_BRIGHTNESS;
    mwColor += hAlphaColor;
    #endif

    mwColor = max(mwColor, vec3(0.0));
    starsColor += mwColor * (cosmosVisibility / max(visibility, 1e-4));
    #else
    // Procedural fallback Milky Way
    mat3 galRot = mat3(
        0.57,  0.72,  0.39,
       -0.64,  0.67, -0.37,
       -0.51, -0.17,  0.84
    );
    vec3 galDir = galRot * sphereDir;
    float galLatitude = abs(galDir.y);

    if (galLatitude < 0.35) {
        float bandProfile = exp(-galLatitude * galLatitude * 28.0);
        vec2 galUV = vec2(atan(galDir.z, galDir.x) * 1.5, galDir.y * 3.5);
        float nebulaeNoise = fbm2D(galUV * 3.0);
        float dustLaneNoise = fbm2D(galUV * 6.0 + vec2(1.5, -0.8));

        float dustAbsorption = smoothstep(0.35, 0.65, dustLaneNoise);
        float emission = nebulaeNoise * (1.0 - dustAbsorption * 0.75);

        vec3 galacticCoreColor = vec3(0.32, 0.30, 0.45);
        vec3 galacticDustColor = vec3(0.38, 0.24, 0.32);
        vec3 mwColor = mix(galacticCoreColor, galacticDustColor, dustLaneNoise);

        galaxyLuminance = bandProfile * emission * 0.42 * MILKY_WAY_BRIGHTNESS;
        starsColor += mwColor * galaxyLuminance * (cosmosVisibility / max(visibility, 1e-4));
    }
    #endif
    #endif

    // 2. NASA SVS 4851 Official IAU Constellation Figures (Stick lines)
    #ifdef CONSTELLATION_FIGURES
    vec4 constSample = texture2D(constellations, nasaUV);
    float constLine = constSample.r;
    if (constLine > 0.04) {
        vec3 constColor = vec3(0.42, 0.70, 1.0) * constLine * CONSTELLATION_INTENSITY * 1.6;
        starsColor += constColor;
    }
    #endif

    // 3. NASA SVS 4851 Celestial Coordinate Grid (RA/Dec J2000 Equator & Meridians)
    #ifdef CELESTIAL_GRID
    vec4 gridSample = texture2D(celestialgrid, nasaUV);
    float gridLine = gridSample.r;
    if (gridLine > 0.04) {
        vec3 gridColor = vec3(0.25, 0.46, 0.85) * gridLine * CELESTIAL_GRID_INTENSITY * 1.3;
        starsColor += gridColor;
    }
    #endif

    // 4. Procedural Dense Star Field with Isotropic Cubemap Lattice (0 polar distortion, 0 voxel clipping)
    starsColor += renderProceduralStars(celDir, timeSec, galaxyLuminance) * (cosmosVisibility / max(visibility, 1e-4));

    // 5. Prominent Real Stars (Hipparcos Catalog with Ballesteros B-V Photometry)
    // Sirius (Canis Major): RA 6.75h, Dec -16.7°, B-V 0.00
    starsColor += renderBrightStar(celDir, raDecToCel(6.75, -16.7), 0.00, 2.8, 1.4, timeSec, 1.0);
    // Canopus (Carina): RA 6.40h, Dec -52.7°, B-V 0.15
    starsColor += renderBrightStar(celDir, raDecToCel(6.40, -52.7), 0.15, 2.2, 1.3, timeSec, 2.0);
    // Rigil Kentaurus (Alpha Centauri): RA 14.66h, Dec -60.8°, B-V 0.71
    starsColor += renderBrightStar(celDir, raDecToCel(14.66, -60.8), 0.71, 1.9, 1.2, timeSec, 3.0);
    // Arcturus (Bootes): RA 14.26h, Dec +19.2°, B-V 1.23
    starsColor += renderBrightStar(celDir, raDecToCel(14.26, 19.2), 1.23, 2.0, 1.3, timeSec, 4.0);
    // Vega (Lyra): RA 18.62h, Dec +38.8°, B-V 0.00
    starsColor += renderBrightStar(celDir, raDecToCel(18.62, 38.8), 0.00, 2.0, 1.2, timeSec, 5.0);
    // Capella (Auriga): RA 5.28h, Dec +46.0°, B-V 0.80
    starsColor += renderBrightStar(celDir, raDecToCel(5.28, 46.0), 0.80, 1.9, 1.2, timeSec, 6.0);
    // Rigel (Orion): RA 5.24h, Dec -8.2°, B-V -0.03
    starsColor += renderBrightStar(celDir, raDecToCel(5.24, -8.2), -0.03, 1.9, 1.2, timeSec, 7.0);
    // Procyon (Canis Minor): RA 7.65h, Dec +5.2°, B-V 0.42
    starsColor += renderBrightStar(celDir, raDecToCel(7.65, 5.2), 0.42, 1.7, 1.1, timeSec, 8.0);
    // Betelgeuse (Orion): RA 5.92h, Dec +7.4°, B-V 1.85 (Red supergiant)
    starsColor += renderBrightStar(celDir, raDecToCel(5.92, 7.4), 1.85, 2.1, 1.4, timeSec, 9.0);
    // Altair (Aquila): RA 19.84h, Dec +8.9°, B-V 0.22
    starsColor += renderBrightStar(celDir, raDecToCel(19.84, 8.9), 0.22, 1.6, 1.1, timeSec, 10.0);
    // Aldebaran (Taurus): RA 4.60h, Dec +16.5°, B-V 1.54 (Orange giant)
    starsColor += renderBrightStar(celDir, raDecToCel(4.60, 16.5), 1.54, 1.7, 1.2, timeSec, 11.0);
    // Antares (Scorpius): RA 16.49h, Dec -26.4°, B-V 1.83 (Red supergiant)
    starsColor += renderBrightStar(celDir, raDecToCel(16.49, -26.4), 1.83, 1.8, 1.3, timeSec, 12.0);
    // Spica (Virgo): RA 13.42h, Dec -11.2°, B-V -0.23 (Blue giant)
    starsColor += renderBrightStar(celDir, raDecToCel(13.42, -11.2), -0.23, 1.6, 1.1, timeSec, 13.0);
    // Polaris (Ursa Minor - North Celestial Pole): RA 2.53h, Dec +89.3°, B-V 0.60
    starsColor += renderBrightStar(celDir, raDecToCel(2.53, 89.3), 0.60, 1.6, 1.1, timeSec, 14.0);

    // 6. Meteor Showers
    starsColor += renderMeteors(sphereDir, timeSec);

    // 7. Multi-Curtain Aurora Borealis with Curl Domain Warping (prominent in cold/mountain biomes)
    #ifdef AURORA_BOREALIS
    float auroraStrength = biomeAtm.auroraStrength * AURORA_INTENSITY;
    if (auroraStrength > 0.01 && sphereDir.y > 0.03 && sphereDir.y < 0.72) {
        float northFactor = 1.0 - smoothstep(-0.55, 0.20, sphereDir.z);
        if (northFactor > 0.001) {
            float heightFactor = smoothstep(0.03, 0.16, sphereDir.y) * (1.0 - smoothstep(0.38, 0.68, sphereDir.y));

            float azim = atan(sphereDir.x, max(-sphereDir.z, 0.02));
            float distFromPole = length(vec2(sphereDir.x, sphereDir.z + 0.35));

            // Domain warping for organic folded plasma ribbon curtains (curling folds)
            vec2 curtainCoord = vec2(azim * 2.8, (distFromPole - 0.75) / (sphereDir.y + 0.12));
            vec2 curlWarp = vec2(
                fbm2D(curtainCoord * 1.6 + vec2(timeSec * 0.04, 0.0)),
                fbm2D(curtainCoord * 1.6 + vec2(1.7, timeSec * 0.03))
            ) * 0.28;
            curtainCoord += curlWarp;

            // Curtain 1: Primary active auroral arc
            float waveA1 = sin(curtainCoord.x * 3.2 + timeSec * 0.32);
            float waveA2 = cos(curtainCoord.x * 6.5 - timeSec * 0.20) * 0.5;
            float cDist1 = abs(curtainCoord.y * 0.42 + waveA1 * 0.18 + waveA2 * 0.08);
            float curtain1 = exp(-cDist1 * 14.0);

            // Curtain 2: Secondary deeper background arc (parallax fold)
            float waveB1 = sin(curtainCoord.x * 2.4 - timeSec * 0.25 + 1.8);
            float waveB2 = cos(curtainCoord.x * 5.2 + timeSec * 0.18) * 0.4;
            float cDist2 = abs((curtainCoord.y - 0.18) * 0.48 + waveB1 * 0.15 + waveB2 * 0.07);
            float curtain2 = exp(-cDist2 * 16.0) * 0.65;

            float totalCurtain = curtain1 + curtain2;

            #ifdef AURORA_RAY_STREAMERS
            // Flowing vertical magnetic field streamers along geomagnetic field lines
            float rayPattern1 = sin(curtainCoord.x * 28.0 + sphereDir.y * 12.0 + timeSec * 0.75) * 0.5 + 0.5;
            float rayPattern2 = sin(curtainCoord.x * 62.0 - sphereDir.y * 22.0 - timeSec * 1.2) * 0.5 + 0.5;
            float rayPattern = rayPattern1 * 0.6 + rayPattern2 * 0.4;
            totalCurtain *= mix(0.70, 1.45, rayPattern);
            #endif

            // Physically authentic atmospheric emission spectrum:
            // 557.7 nm atomic oxygen green dominates lower 100-150km
            // 630.0 nm atomic oxygen crimson at high altitude >200km
            // N2+ first negative violet at lower border during active storms
            vec3 emeraldGreen  = vec3(0.08, 0.95, 0.42);
            vec3 celestialCyan = vec3(0.12, 0.85, 0.78);
            vec3 violetBorder  = vec3(0.55, 0.15, 0.85);
            vec3 crimsonCrown  = vec3(0.92, 0.10, 0.22);

            vec3 auroraColor = mix(emeraldGreen, celestialCyan, smoothstep(0.10, 0.28, sphereDir.y));
            auroraColor = mix(auroraColor, crimsonCrown, smoothstep(0.30, 0.58, sphereDir.y));
            // Subtle violet border at the very lower edge
            float lowerEdge = smoothstep(0.04, 0.10, sphereDir.y) * (1.0 - smoothstep(0.10, 0.16, sphereDir.y));
            auroraColor = mix(auroraColor, violetBorder, lowerEdge * 0.45);

            starsColor += auroraColor * totalCurtain * heightFactor * northFactor * 1.15 * auroraStrength;
        }
    }
    #endif

    return starsColor * visibility;
}

// 6-parameter backwards compatibility wrapper
vec3 renderStarsAndMilkyWay(vec3 rayDir, float sunHeight, float rain, float timeSec, int worldTimeTicks, BiomeAtmosphere biomeAtm) {
    return renderStarsAndMilkyWay(rayDir, vec3(0.0, -1.0, 0.0), 4, sunHeight, rain, timeSec, worldTimeTicks, biomeAtm);
}

#endif // CELESTIALS_GLSL
