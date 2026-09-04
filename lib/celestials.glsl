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

// Procedural realistic Sun disc, limb darkening, corona, glare, and diffraction spikes for billboard rendering
vec4 renderSunBillboard(vec2 localCoord, float distToCenter, float sunHeight, float rainStrength, BiomeAtmosphere biomeAtm) {
    if (rainStrength > 0.95 || sunHeight < -0.18) return vec4(0.0);

    vec3 noonColor    = vec3(1.00, 0.98, 0.94) * 5.2;
    vec3 sunsetColor  = vec3(1.00, 0.45, 0.08) * 4.2;
    vec3 horizonColor = vec3(0.96, 0.16, 0.02) * 3.4;

    if (biomeAtm.isArid) {
        sunsetColor = mix(sunsetColor, vec3(1.00, 0.32, 0.04) * 4.4, biomeAtm.sandstormFactor);
    }

    float sunsetT  = clamp(1.0 - sunHeight * 4.0, 0.0, 1.0);
    float horizonT = clamp(-sunHeight * 8.0 + 0.4, 0.0, 1.0);
    vec3 currentSunColor = mix(noonColor, sunsetColor, sunsetT);
    currentSunColor = mix(currentSunColor, horizonColor, horizonT);

    float discRadius = 0.50 * SUN_SIZE;
    vec3 sunEmission = vec3(0.0);
    float alpha = 0.0;

    // 1. Sharp solar disc with 3-term Eddington limb darkening
    if (distToCenter < discRadius) {
        float r = distToCenter / discRadius;
        #ifdef SUN_LIMB_DARKENING
        float mu = sqrt(max(1.0 - r * r, 0.0));
        float limbDarkening = 0.35 + 0.65 * pow(mu, 0.65);
        #else
        float limbDarkening = 1.0;
        #endif
        float edgeAA = smoothstep(1.0, 0.94, r);
        sunEmission += currentSunColor * limbDarkening * edgeAA;
        alpha = max(alpha, edgeAA);
    }

    // 2. Solar Corona (intense inner glow)
    if (SUN_CORONA_INTENSITY > 0.001) {
        float coronaGlow = exp(-distToCenter * 4.2) * SUN_CORONA_INTENSITY * 0.85;
        sunEmission += currentSunColor * coronaGlow;
        alpha = max(alpha, clamp(coronaGlow, 0.0, 1.0));
    }

    // 3. Wide solar glare halo
    #ifdef SUN_GLARE
    float glare = 0.22 / (1.0 + distToCenter * distToCenter * 6.0) * biomeAtm.hazeDensity;
    sunEmission += currentSunColor * glare;
    alpha = max(alpha, clamp(glare, 0.0, 1.0));
    #endif

    // 4. Solar diffraction starburst spikes
    #ifdef SOLAR_DIFFRACTION_SPIKES
    vec2 rotCoord = vec2(localCoord.x + localCoord.y, localCoord.x - localCoord.y) * 0.7071;
    float sp1 = exp(-abs(rotCoord.x) * 12.0) / (abs(rotCoord.y) * 2.0 + 1.0);
    float sp2 = exp(-abs(rotCoord.y) * 12.0) / (abs(rotCoord.x) * 2.0 + 1.0);
    float spike = (sp1 + sp2) * exp(-distToCenter * 2.5) * 0.45;
    sunEmission += currentSunColor * spike;
    alpha = max(alpha, clamp(spike, 0.0, 1.0));
    #endif

    // Smooth circular quad boundary falloff: guarantees 0 at quad edges, eliminating square cut-off boxes
    float quadFade = smoothstep(1.0, 0.70, distToCenter);
    sunEmission *= quadFade;
    alpha *= quadFade;

    float weatherFade = 1.0 - rainStrength * 0.90;
    return vec4(sunEmission * weatherFade, alpha * weatherFade);
}

// Procedural high-detail Moon with maria, craters, 8-phases, and halo for billboard rendering
vec4 renderMoonBillboard(vec2 localCoord, float distToCenter, vec3 sunDir, vec3 moonDir, vec3 upVector, int moonPhase, float sunHeight, float rainStrength, BiomeAtmosphere biomeAtm) {
    if (rainStrength > 0.92 || sunHeight > 0.18) return vec4(0.0);

    float nightFactor = clamp(-sunHeight * 8.0, 0.0, 1.0);
    float discRadius = 0.50 * MOON_SIZE;
    vec3 moonBaseColor = vec3(0.90, 0.94, 1.0);
    vec3 moonEmission = vec3(0.0);
    float alpha = 0.0;

    if (distToCenter < discRadius) {
        float r = distToCenter / discRadius;
        float edgeAA = smoothstep(1.0, 0.93, r);

        float normalZ = sqrt(max(1.0 - r * r, 0.0));
        vec3 sphereNormal = vec3(localCoord / discRadius, normalZ);

        // Detailed lunar maria & crater ejecta rays
        #ifdef MOON_SURFACE_DETAIL
        vec2 surfaceUV = (localCoord / discRadius) * 1.5 + vec2(1.2, 0.8);
        float maria = fbm2D_Detailed(surfaceUV * 2.4);
        float craterRays = voronoi2D(surfaceUV * 4.2);
        float albedo = mix(0.52, 1.08, smoothstep(0.36, 0.70, maria));
        albedo += (1.0 - smoothstep(0.0, 0.12, craterRays)) * 0.28;
        #else
        float albedo = 1.0;
        #endif

        // 8-Phase lunar cycle with physically oriented terminator pointing toward the Sun
        #ifdef MOON_PHASES
        vec3 moonRight = normalize(cross(moonDir, upVector));
        vec3 moonUp    = cross(moonRight, moonDir);
        float sunProjX = dot(sunDir, moonRight);
        float sunProjY = dot(sunDir, moonUp);
        vec2 sunTangentDir = normalize(vec2(sunProjX, sunProjY) + vec2(1e-5));

        float phaseAngle = float(moonPhase) * (TWO_PI / 8.0);
        float lightZ = cos(phaseAngle);
        float lightTransverse = -sin(phaseAngle);
        vec3 phaseLightDir = normalize(vec3(sunTangentDir * lightTransverse, lightZ));

        float NdotL = dot(sphereNormal, phaseLightDir);
        float illumination = smoothstep(-0.06, 0.06, NdotL);

        #ifdef MOON_EARTHSHINE
        illumination += 0.05 * (1.0 - illumination);
        #endif
        #else
        float illumination = 1.0;
        #endif

        moonEmission += moonBaseColor * albedo * illumination * 2.6 * edgeAA;
        alpha = max(alpha, edgeAA);
    }

    // Lunar atmospheric halo / ice crystal ring
    #ifdef MOON_HALO
    float haloGlow = exp(-distToCenter * 3.2) * 0.28 * MOON_HALO_INTENSITY;
    haloGlow *= mix(1.0, 1.8, biomeAtm.auroraStrength / 1.8);

    // 22-degree hexagonal ice crystal halo ring within billboard quad
    float ringR = abs(distToCenter - 0.72);
    float ringIntensity = (biomeAtm.isCold ? 0.35 : 0.12) * MOON_HALO_INTENSITY;
    float haloRing = exp(-ringR * ringR * 120.0) * ringIntensity;

    vec3 haloColor = vec3(0.55, 0.72, 1.0);
    moonEmission += haloColor * (haloGlow + haloRing);
    alpha = max(alpha, clamp((haloGlow + haloRing) * 1.5, 0.0, 1.0));
    #endif

    // Smooth circular quad boundary falloff
    float quadFade = smoothstep(1.0, 0.70, distToCenter);
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

// Convert Celestial unit vector to NASA SVS 4851 plate carrée equirectangular UV
// Centered at 0h RA, RA increases to the left
vec2 celestialToNASA_UV(vec3 celDir) {
    float dec = asin(clamp(celDir.y, -1.0, 1.0));
    float v = dec * INV_PI + 0.5;

    float ra = atan(celDir.z, celDir.x);
    float u = fract(0.5 - ra * (0.5 * INV_PI));

    return vec2(u, v);
}

vec3 raDecToCel(float raHours, float decDeg) {
    float raRad = raHours * (TWO_PI / 24.0);
    float decRad = radians(decDeg);
    float cosDec = cos(decRad);
    return vec3(cosDec * cos(raRad), sin(decRad), cosDec * sin(raRad));
}

vec3 renderBrightStar(vec3 celDir, vec3 starPos, float bv, float brightness, float size, float timeSec, float seed) {
    float cosA = dot(celDir, starPos);
    if (cosA < 0.9992) return vec3(0.0);

    float angle = acos(clamp(cosA, -1.0, 1.0));
    float radius = size * 0.0019;
    if (angle > radius * 6.0) return vec3(0.0);

    #ifdef STARS_TWINKLE
    float twinkleSpeed = 3.2 + hash11(seed * 19.3) * 5.5;
    float twR = sin(timeSec * twinkleSpeed + seed * 6.28 + 0.0) * 0.32 + 0.68;
    float twG = sin(timeSec * twinkleSpeed + seed * 6.28 + 0.4) * 0.32 + 0.68;
    float twB = sin(timeSec * twinkleSpeed + seed * 6.28 + 0.8) * 0.32 + 0.68;
    vec3 twinkle = vec3(twR, twG, twB);
    #else
    vec3 twinkle = vec3(1.0);
    #endif

    vec3 starColor = getStarColorFromBV(bv);
    float core = exp(-angle / (radius * 0.42)) * 4.2;
    float halo = exp(-angle / (radius * 1.8)) * 0.75;

    return starColor * (core + halo) * brightness * twinkle;
}

// Procedural dense star background in celestial coordinate space
vec3 renderProceduralStars(vec3 celDir, float timeSec) {
    vec3 starsColor = vec3(0.0);
    vec2 starUV = vec2(atan(celDir.z, celDir.x) * INV_PI * 0.5 + 0.5, celDir.y * 0.5 + 0.5);
    vec2 starCell = floor(starUV * 360.0 * STARS_DENSITY);
    vec2 starFrac = fract(starUV * 360.0 * STARS_DENSITY) - 0.5;

    float starRandom = hash21(starCell);

    if (starRandom > 0.81) {
        float starDist = length(starFrac);
        float starSize = 0.07 + (starRandom - 0.81) * 1.5;

        #ifdef STARS_TWINKLE
        float twinkleSpeed = 2.0 + hash21(starCell + 5.0) * 6.5;
        float twR = sin(timeSec * twinkleSpeed + starRandom * 62.8 + 0.0) * 0.35 + 0.65;
        float twG = sin(timeSec * twinkleSpeed + starRandom * 62.8 + 0.4) * 0.35 + 0.65;
        float twB = sin(timeSec * twinkleSpeed + starRandom * 62.8 + 0.8) * 0.35 + 0.65;
        vec3 twinkle = vec3(twR, twG, twB);
        #else
        vec3 twinkle = vec3(1.0);
        #endif

        float bv = hash21(starCell + 12.0) * 2.1 - 0.3;
        vec3 starTint = getStarColorFromBV(bv);

        float brightness = exp(-starDist * starDist / (starSize * starSize * 0.08));
        starsColor += starTint * brightness * twinkle * 1.8;
    }
    return starsColor;
}

// Primary Night Sky Compositor: NASA SVS 4851 Milky Way, Stars, Meteors & Auroras
vec3 renderStarsAndMilkyWay(vec3 rayDir, float sunHeight, float rain, float timeSec, int worldTimeTicks, BiomeAtmosphere biomeAtm) {
    #ifndef ENABLE_STARS
    return vec3(0.0);
    #endif

    if (rain > 0.4 || sunHeight > -0.04 || rayDir.y < 0.0) return vec3(0.0);

    float nightStrength = clamp(-sunHeight * 12.0 - 0.2, 0.0, 1.0);
    float horizonMask   = smoothstep(0.02, 0.25, rayDir.y);
    float visibility    = nightStrength * horizonMask * (1.0 - rain * 2.0);
    if (visibility <= 0.0) return vec3(0.0);

    vec3 sphereDir = normalize(rayDir);
    vec3 celDir = worldToCelestial(sphereDir, worldTimeTicks);
    vec2 nasaUV = celestialToNASA_UV(celDir);

    vec3 starsColor = vec3(0.0);

    // 1. Milky Way Galaxy Band (NASA SVS 4851 Gaia/Tycho composite texture with procedural fallback)
    #ifdef MILKY_WAY
    #ifdef NASA_SVS_MILKY_WAY
    vec4 mwSample = texture2D(milkyway, nasaUV);
    // Dynamic contrast & cosmic dust richness enhancement
    vec3 mwColor = pow(mwSample.rgb, vec3(1.10)) * 2.1;
    starsColor += mwColor * MILKY_WAY_BRIGHTNESS;
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

        starsColor += mwColor * bandProfile * emission * 0.42 * MILKY_WAY_BRIGHTNESS;
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

    // 4. Procedural Dense Star Field with Ballesteros Blackbody Colors
    starsColor += renderProceduralStars(celDir, timeSec);

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
        float northFactor = smoothstep(0.15, -0.45, sphereDir.z);
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

            vec3 greenEmerald  = vec3(0.12, 0.88, 0.45);
            vec3 violetMagenta = vec3(0.68, 0.18, 0.88);
            vec3 crimsonTop    = vec3(0.85, 0.15, 0.25);

            float vGrad1 = smoothstep(0.06, 0.26, sphereDir.y);
            float vGrad2 = smoothstep(0.24, 0.48, sphereDir.y);
            vec3 auroraColor = mix(greenEmerald, violetMagenta, vGrad1);
            auroraColor = mix(auroraColor, crimsonTop, vGrad2);

            starsColor += auroraColor * curtain * heightFactor * northFactor * 0.85 * auroraStrength;
        }
    }
    #endif

    return starsColor * visibility;
}

#endif // CELESTIALS_GLSL
