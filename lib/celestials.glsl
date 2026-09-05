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

    // 1. Đĩa Mặt trời sắc nét với quy luật tối vùng rìa Eddington 3 thành phần
    if (flatDist < discRadius) {
        float r = flatDist / discRadius;
        #ifdef SUN_LIMB_DARKENING
        float mu = sqrt(max(1.0 - r * r, 0.0));
        float limbDarkening = 0.35 + 0.65 * pow(mu, 0.60);
        vec3 limbTint = mix(vec3(1.0, 0.65, 0.35), vec3(1.0), pow(mu, 0.35));
        #else
        float limbDarkening = 1.0;
        vec3 limbTint = vec3(1.0);
        #endif
        float edgeAA = 1.0 - smoothstep(0.94, 1.0, r);
        sunEmission += currentSunColor * limbDarkening * limbTint * edgeAA;
        alpha = max(alpha, edgeAA);
    }

    // 2. Quầng plasma corona bám sát rìa quang cầu (tight physical plasma envelope)
    // Suy giảm mượt mà theo hàm mũ bắt đầu ngay từ mép đĩa ra ngoài, triệt tiêu trước biên quad
    if (SUN_CORONA_INTENSITY > 0.001) {
        float rRel = max(flatDist - discRadius, 0.0) / discRadius;
        float coronaGlow = exp(-rRel * 6.8) * 0.36 * SUN_CORONA_INTENSITY;

        #ifdef SUN_CHROMATIC_CORONA
        // Tán sắc plasma quang sai nhẹ nhàng chuyển từ cam vàng sang ánh mặt trời
        vec3 coronaColor = mix(vec3(1.0, 0.52, 0.15), currentSunColor, exp(-rRel * 3.5));
        #else
        vec3 coronaColor = currentSunColor;
        #endif
        sunEmission += coronaColor * coronaGlow;
        alpha = max(alpha, clamp(coronaGlow * 1.5, 0.0, 1.0));
    }

    // 3. Hào quang tán xạ dịu êm (không dùng hàm bậc 2 gây viền tròn cắt cụt quad)
    #ifdef SUN_GLARE
    float glare = exp(-flatDist * 3.6) * 0.10 * biomeAtm.hazeDensity;
    sunEmission += currentSunColor * glare;
    alpha = max(alpha, clamp(glare * 1.5, 0.0, 1.0));
    #endif

    // 4. Tia lóe nhiễu xạ 6 cánh (diffraction spikes anamorphic)
    #ifdef SOLAR_DIFFRACTION_SPIKES
    float spAngle1 = 0.0;
    float spAngle2 = 1.047197; // 60 deg
    float spAngle3 = 2.094395; // 120 deg
    
    vec2 p1 = vec2(localCoord.x * cos(spAngle1) - localCoord.y * sin(spAngle1), localCoord.x * sin(spAngle1) + localCoord.y * cos(spAngle1));
    vec2 p2 = vec2(localCoord.x * cos(spAngle2) - localCoord.y * sin(spAngle2), localCoord.x * sin(spAngle2) + localCoord.y * cos(spAngle2));
    vec2 p3 = vec2(localCoord.x * cos(spAngle3) - localCoord.y * sin(spAngle3), localCoord.x * sin(spAngle3) + localCoord.y * cos(spAngle3));

    float s1 = exp(-abs(p1.y) * 16.0) / (abs(p1.x) * 2.5 + 1.0);
    float s2 = exp(-abs(p2.y) * 16.0) / (abs(p2.x) * 2.5 + 1.0);
    float s3 = exp(-abs(p3.y) * 16.0) / (abs(p3.x) * 2.5 + 1.0);

    float spike = (s1 + s2 + s3) * exp(-flatDist * 3.2) * 0.20;
    vec3 spikeColor = mix(vec3(1.0, 0.85, 0.65), currentSunColor, 0.5);
    sunEmission += spikeColor * spike;
    alpha = max(alpha, clamp(spike * 1.5, 0.0, 1.0));
    #endif

    // Suy giảm mượt ở biên ngoài quad, hoàn toàn không để lại vết cắt hay ranh giới tròn
    float quadFade = 1.0 - smoothstep(0.65, 1.0, distToCenter);
    sunEmission *= quadFade;
    alpha *= quadFade;

    float weatherFade = 1.0 - rainStrength * 0.90;
    return vec4(sunEmission * weatherFade, alpha * weatherFade);
}

// Procedural high-detail Moon with maria, craters, 8-phases, 3D crater relief and halo for billboard rendering
vec4 renderMoonBillboard(vec2 localCoord, float distToCenter, vec3 sunDir, vec3 moonDir, vec3 upVector, int moonPhase, float sunHeight, float rainStrength, BiomeAtmosphere biomeAtm) {
    if (rainStrength > 0.92 || sunHeight > 0.18) return vec4(0.0);

    float nightFactor = clamp(-sunHeight * 8.0, 0.0, 1.0);
    float discRadius = 0.48 * MOON_SIZE;
    // Tông màu bạc ánh trăng tự nhiên dịu mát, không bị gắt xanh
    vec3 moonBaseColor = vec3(0.92, 0.94, 0.97);
    vec3 moonEmission = vec3(0.0);
    float alpha = 0.0;

    if (distToCenter < discRadius) {
        float r = distToCenter / discRadius;
        float edgeAA = 1.0 - smoothstep(0.93, 1.0, r);

        float normalZ = sqrt(max(1.0 - r * r, 0.0));
        vec3 sphereNormal = vec3(localCoord / discRadius, normalZ);

        // Chi tiết bề mặt biển bazan (maria) và các tia bắn miệng hố
        #ifdef MOON_SURFACE_DETAIL
        vec2 surfaceUV = (localCoord / discRadius) * 1.5 + vec2(1.2, 0.8);
        float maria = fbm2D_Detailed(surfaceUV * 2.4);
        float craterRays = voronoi2D(surfaceUV * 4.2);
        float microCraters = voronoi2D(surfaceUV * 9.5);
        // Cân đối tương phản bề mặt để hiển thị rõ chi tiết mà không bị cháy sáng
        float albedo = mix(0.55, 1.05, smoothstep(0.35, 0.68, maria));
        albedo += (1.0 - smoothstep(0.0, 0.15, craterRays)) * 0.22;
        albedo += (1.0 - smoothstep(0.0, 0.10, microCraters)) * 0.12;
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
        // Đạo hàm vi phân gradient FBM liên tục C2 để tránh gãy khúc / răng cưa so với voronoi
        vec2 eps = vec2(0.04, 0.0);
        float hL = fbm2D(surfaceUV * 5.0 - eps.xy);
        float hR = fbm2D(surfaceUV * 5.0 + eps.xy);
        float hD = fbm2D(surfaceUV * 5.0 - eps.yx);
        float hU = fbm2D(surfaceUV * 5.0 + eps.yx);
        vec2 smoothGrad = vec2(hR - hL, hU - hD) * 1.8;

        // Chỉ tạo gồ ghề vi mô nhẹ dọc đường phân giới terminator
        float termProximity = 1.0 - smoothstep(0.0, 0.35, abs(dot(sphereNormal, phaseLightDir)));
        vec3 perturbedNormal = normalize(sphereNormal + vec3(smoothGrad * 0.18 * termProximity, 0.0));
        #else
        vec3 perturbedNormal = sphereNormal;
        #endif

        // Dải chuyển tiếp sáng tối mượt mà (smooth physical terminator falloff) loại bỏ răng cưa
        float NdotL = dot(perturbedNormal, phaseLightDir);
        float illumination = smoothstep(-0.14, 0.14, NdotL);

        #ifdef MOON_EARTHSHINE
        // Ánh đất dịu nhẹ phản chiếu phần tối của mặt trăng
        illumination += 0.025 * (1.0 - illumination);
        #endif
        #else
        float illumination = 1.0;
        #endif

        // Cân chỉnh cường độ phát xạ theo MOON_BRIGHTNESS giữ trọn vẹn chi tiết bề mặt
        moonEmission += moonBaseColor * albedo * illumination * (0.85 * MOON_BRIGHTNESS) * edgeAA;
        alpha = max(alpha, edgeAA);
    }

    // Quầng sáng khí quyển & vòng tinh thể băng 22 độ (Lunar Halo)
    #ifdef MOON_HALO
    // Hào quang khuếch tán mềm mại, dịu êm
    float haloGlow = exp(-distToCenter * 2.8) * 0.035 * MOON_HALO_INTENSITY;
    haloGlow *= mix(1.0, 1.4, biomeAtm.auroraStrength / 1.8);

    // Vành hào quang 22 độ siêu mờ ảo, phân bố Gauss rộng không còn đường viền sắc
    float ringR = abs(distToCenter - 0.72);
    float ringIntensity = (biomeAtm.isCold ? 0.035 : 0.008) * MOON_HALO_INTENSITY;
    float haloRing = exp(-ringR * ringR * 26.0) * ringIntensity;

    vec3 haloColor = vec3(0.65, 0.75, 0.92);
    moonEmission += haloColor * (haloGlow + haloRing);
    alpha = max(alpha, clamp((haloGlow + haloRing) * 1.0, 0.0, 1.0));
    #endif

    // Suy giảm mượt ở biên ngoài billboard quad
    float quadFade = 1.0 - smoothstep(0.70, 1.0, distToCenter);
    moonEmission *= quadFade;
    alpha *= quadFade;

    float weatherFade = (1.0 - rainStrength * 0.90) * nightFactor;
    return vec4(moonEmission * weatherFade, alpha * weatherFade);
}

// Shooting star / meteor streaks
vec3 renderMeteors(vec3 rayDir, float timeSec) {
    #ifndef METEOR_SHOWERS
    return vec3(0.0);
    #endif

    // Meteor frequency cycle (every ~4 seconds)
    float cycle = floor(timeSec * 0.25);
    float localT = fract(timeSec * 0.25);

    float meteorSeed = hash11(cycle * 78.43);
    // 40% chance of meteor in a cycle
    if (meteorSeed > 0.60) {
        // Random start position and direction across upper sky
        vec3 startPos = normalize(vec3(hash11(cycle * 12.1) * 2.0 - 1.0, 0.5 + hash11(cycle * 34.2) * 0.4, hash11(cycle * 56.3) * 2.0 - 1.0));
        vec3 streakDir = normalize(vec3(0.8, -0.6, 0.5));

        // Fast streak animation (lasts ~0.3 seconds)
        float tSpeed = localT * 4.0;
        if (tSpeed > 0.0 && tSpeed < 1.2) {
            vec3 curHead = normalize(startPos + streakDir * tSpeed * 0.35);
            float distToHead = length(rayDir - curHead);
            
            // Bright ionization trail
            if (distToHead < 0.08) {
                float headGlow = exp(-distToHead * 450.0);
                float trail = exp(-distToHead * 80.0) * (1.0 - tSpeed / 1.2);
                vec3 meteorColor = vec3(0.9, 0.96, 1.0) * 4.0;
                return meteorColor * (headGlow + trail * 0.5);
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

// Procedural dense star background in celestial coordinate space
// Modulated by local galaxy luminance (Photon technique: stars cluster along the galactic plane)
// Uses jittered Voronoi cellular distribution with dec-aware longitude scaling to prevent grid alignment & concentric ring artifacts
vec3 renderProceduralStars(vec3 celDir, float starU, float timeSec, float galaxyLuminance) {
    vec3 starsColor = vec3(0.0);

    // Declination and Right Ascension projection
    float dec = asin(clamp(celDir.y, -1.0, 1.0)); // [-pi/2, pi/2]
    float cosDec = max(cos(dec), 0.08);

    // Layer 1: Base high-density background stars
    {
        float scale = 360.0 * STARS_DENSITY;
        vec2 starUV = vec2(starU * scale * cosDec, (dec * INV_PI + 0.5) * scale);
        vec2 cell = floor(starUV);
        vec2 frac = fract(starUV) - 0.5;

        // Jitter offset within cell to completely eliminate grid alignment & circular patterns
        vec2 jitter = hash22(cell) - 0.5;
        vec2 delta = frac - jitter * 0.76;

        float starRandom = hash21(cell + vec2(1.7, 9.2));
        float densityThreshold = clamp(0.81 - galaxyLuminance * 0.40, 0.55, 0.82);

        if (starRandom > densityThreshold) {
            float starDist = length(delta);
            float starSize = 0.08 + (starRandom - densityThreshold) * 1.4;

            float twinkleSpeed = 2.0 + hash21(cell + 5.0) * 6.5;
            vec3 twinkle = calculateStarTwinkle(timeSec, twinkleSpeed, starRandom * 62.8, 0.35);

            float bv = hash21(cell + 12.0) * 2.1 - 0.3;
            vec3 starTint = getStarColorFromBV(bv);

            float brightness = exp(-starDist * starDist / (starSize * starSize * 0.08));
            starsColor += starTint * brightness * twinkle * 1.8;
        }
    }

    // Layer 2: Secondary decorrelated layer (rotated grid) to break any subtle single-lattice resonance
    {
        mat2 rotLayer = mat2(0.7071, -0.7071, 0.7071, 0.7071);
        float scale2 = 250.0 * STARS_DENSITY;
        vec2 starUV2 = rotLayer * vec2(starU * scale2 * cosDec, (dec * INV_PI + 0.5) * scale2);
        vec2 cell2 = floor(starUV2);
        vec2 frac2 = fract(starUV2) - 0.5;

        vec2 jitter2 = hash22(cell2 + vec2(43.1, 17.5)) - 0.5;
        vec2 delta2 = frac2 - jitter2 * 0.76;

        float starRandom2 = hash21(cell2 + vec2(8.3, 31.7));
        float densityThreshold2 = clamp(0.86 - galaxyLuminance * 0.35, 0.65, 0.88);

        if (starRandom2 > densityThreshold2) {
            float starDist2 = length(delta2);
            float starSize2 = 0.07 + (starRandom2 - densityThreshold2) * 1.3;

            float twinkleSpeed2 = 1.8 + hash21(cell2 + 9.0) * 5.5;
            vec3 twinkle2 = calculateStarTwinkle(timeSec, twinkleSpeed2, starRandom2 * 51.4, 0.30);

            float bv2 = hash21(cell2 + 7.0) * 2.0 - 0.25;
            vec3 starTint2 = getStarColorFromBV(bv2);

            float brightness2 = exp(-starDist2 * starDist2 / (starSize2 * starSize2 * 0.08));
            starsColor += starTint2 * brightness2 * twinkle2 * 1.5;
        }
    }

    return starsColor;
}

// Primary Night Sky Compositor: NASA SVS 4851 Milky Way, Stars, Meteors & Auroras
vec3 renderStarsAndMilkyWay(vec3 rayDir, float sunHeight, float rain, float timeSec, int worldTimeTicks, BiomeAtmosphere biomeAtm) {
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

    vec3 sphereDir = normalize(rayDir);
    vec3 celDir = worldToCelestial(sphereDir, worldTimeTicks);
    vec2 nasaUV = celestialToNASA_UV(celDir);

    vec3 starsColor = vec3(0.0);
    float galaxyLuminance = 0.0;

    // 1. Milky Way Galaxy Band (Photon-style Linear decoding & luminance-preserving saturation)
    #ifdef MILKY_WAY
    #ifdef NASA_SVS_MILKY_WAY
    vec4 mwSample = texture2D(milkyway, nasaUV);
    
    // Inverse sRGB EOTF: prevents black space from turning into a bright hazy fog
    vec3 mwLinear = srgbToLinear(mwSample.rgb);
    
    // Celestial tint (Photon palette: subtle cosmic blue-violet galactic tint)
    const vec3 galaxyTint = vec3(0.78, 0.72, 1.0);
    vec3 mwColor = mwLinear * galaxyTint * MILKY_WAY_BRIGHTNESS;
    
    // Luminance-preserving saturation boost for vibrant dust lanes and nebulae
    galaxyLuminance = dot(mwColor, vec3(0.2126, 0.7152, 0.0722));
    mwColor = mix(vec3(galaxyLuminance), mwColor, 1.85);

    #ifdef MILKY_WAY_H_ALPHA
    // Hydrogen-alpha (656.3 nm) deep red/magenta emission nebula enhancement
    // Prominently enhances emission regions like Carina, Orion, Barnard's Loop, and Cygnus
    float hAlphaMask = clamp(mwSample.r * 1.8 - (mwSample.g + mwSample.b) * 0.9, 0.0, 1.0);
    vec3 hAlphaColor = vec3(1.0, 0.18, 0.38) * hAlphaMask * 0.45 * MILKY_WAY_BRIGHTNESS;
    mwColor += hAlphaColor;
    #endif

    mwColor = max(mwColor, vec3(0.0));
    
    starsColor += mwColor;
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

        vec3 galacticCoreColor = vec3(0.22, 0.30, 0.60);
        vec3 galacticDustColor = vec3(0.48, 0.26, 0.42);
        vec3 mwColor = mix(galacticCoreColor, galacticDustColor, dustLaneNoise);

        galaxyLuminance = bandProfile * emission * 0.42 * MILKY_WAY_BRIGHTNESS;
        starsColor += mwColor * galaxyLuminance;
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

    // 4. Procedural Dense Star Field with Ballesteros Blackbody Colors & Galactic Concentration
    starsColor += renderProceduralStars(celDir, nasaUV.x, timeSec, galaxyLuminance);

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

    // 7. Multi-Layer Aurora Borealis (prominent in cold/mountain biomes)
    #ifdef AURORA_BOREALIS
    float auroraStrength = biomeAtm.auroraStrength * AURORA_INTENSITY;
    if (auroraStrength > 0.01 && sphereDir.y > 0.03 && sphereDir.y < 0.65) {
        // Continuous smooth northward factor - no abrupt cutoffs
        float northFactor = 1.0 - smoothstep(-0.45, 0.15, sphereDir.z);
        if (northFactor > 0.001) {
            float heightFactor = smoothstep(0.03, 0.16, sphereDir.y) * (1.0 - smoothstep(0.32, 0.60, sphereDir.y));

            // Curving auroral oval projected onto celestial dome
            float azim = atan(sphereDir.x, max(-sphereDir.z, 0.02));
            float distFromPole = length(vec2(sphereDir.x, sphereDir.z + 0.35));
            vec2 auroraUV = vec2(azim * 2.5, (distFromPole - 0.75) / (sphereDir.y + 0.12));
            
            float wave1 = sin(auroraUV.x * 2.8 + timeSec * 0.35);
            float wave2 = cos(auroraUV.x * 5.6 - timeSec * 0.22) * 0.5;
            float wave3 = sin(auroraUV.x * 9.2 + timeSec * 0.45) * 0.25;
            float auroraFbm = fbm2D(auroraUV * 2.2 + vec2(timeSec * 0.06, 0.0));

            float curtain = abs(auroraUV.y * 0.38 + wave1 * 0.15 + wave2 * 0.08 + wave3 * 0.04 + auroraFbm * 0.18);
            curtain = exp(-curtain * 16.0);

            #ifdef AURORA_RAY_STREAMERS
            // High-frequency vertical magnetic field streamers
            float rayPattern = sin(auroraUV.x * 32.0 + timeSec * 0.8) * 0.5 + 0.5;
            rayPattern *= sin(auroraUV.x * 75.0 - timeSec * 1.4) * 0.5 + 0.5;
            curtain *= mix(0.72, 1.45, rayPattern);
            #endif

            vec3 greenEmerald  = vec3(0.12, 0.92, 0.45);
            vec3 violetMagenta = vec3(0.70, 0.18, 0.90);
            vec3 crimsonTop    = vec3(0.88, 0.15, 0.25);

            float vGrad1 = smoothstep(0.06, 0.26, sphereDir.y);
            float vGrad2 = smoothstep(0.24, 0.48, sphereDir.y);
            vec3 auroraColor = mix(greenEmerald, violetMagenta, vGrad1);
            auroraColor = mix(auroraColor, crimsonTop, vGrad2);

            starsColor += auroraColor * curtain * heightFactor * northFactor * 0.90 * auroraStrength;
        }
    }
    #endif

    return starsColor * visibility;
}

#endif // CELESTIALS_GLSL
