#ifndef SETTINGS_GLSL
#define SETTINGS_GLSL

/*
 * ==============================================================================
 *  CELESTIAL & WEATHER SHADER CONFIGURATION (EXTREME HIGH-END EDITION)
 *  OptiFine / Iris Shaders for Minecraft Java Edition 1.20+
 * ==============================================================================
 */

// --- Biome Adaptation ---
#define BIOME_ADAPTATION            // Climate-aware sky scattering, fog, clouds, auroras & weather

// --- Sky & Atmosphere ---
#define RAYLEIGH_SCATTERING         // Realistic Rayleigh atmospheric scattering
#define MIE_SCATTERING              // Forward Mie aerosol/haze scattering
#define OZONE_ABSORPTION            // Chappuis ozone layer absorption (deep blue/purple twilight)
#define SKY_GROUND_FOG              // Horizon and altitude atmospheric blending
#define ATMOSPHERE_DENSITY  1.0     // [0.5 0.75 1.0 1.25 1.5 2.0] Atmosphere optical thickness

// --- Sun ---
#define ENABLE_SUN                  // Custom procedural sun disc and atmospheric flare
#define SUN_SIZE            1.0     // [0.5 0.75 1.0 1.25 1.5 2.0] Angular diameter of the sun
#define SUN_LIMB_DARKENING          // 3-term polynomial solar limb darkening
#define SUN_CORONA_INTENSITY 1.2    // [0.0 0.5 1.0 1.2 1.5 2.0] Intensity of solar corona glow
#define SUN_GLARE                   // Wide-angle atmospheric solar glare
#define SOLAR_DIFFRACTION_SPIKES    // Anamorphic 4-point solar flare diffraction spikes
#define GODRAYS                     // Volumetric crepuscular light shafts through clouds and horizon
#define GODRAYS_INTENSITY   1.2     // [0.5 0.75 1.0 1.2 1.5 2.0] Brightness of god rays

// --- Moon ---
#define ENABLE_MOON                 // Custom high-detail procedural moon
#define MOON_SIZE           1.0     // [0.5 0.75 1.0 1.25 1.5 2.0] Angular diameter of the moon
#define MOON_PHASES                 // Realistic 8-phase lunar cycle based on world moonPhase
#define MOON_SURFACE_DETAIL         // Procedural lunar maria (basalt seas) and crater relief
#define MOON_EARTHSHINE             // Subtle illumination of the unlit lunar crescent
#define MOON_HALO                   // Ethereal lunar atmospheric halo / ice crystal ring
#define MOON_HALO_INTENSITY 1.0     // [0.0 0.5 1.0 1.5 2.0] Halo brightness

// --- Night Sky & Celestials (NASA SVS 4851 Deep Star Maps Edition) ---
#define ENABLE_STARS                // High-density procedural star field
#define STARS_DENSITY       1.2     // [0.5 0.75 1.0 1.2 1.5 2.0] Total number of visible stars
#define STARS_TWINKLE               // Atmospheric scintillation / temporal twinkling
#define STARS_COLOR_VARIETY         // Spectral star classifications via Ballesteros blackbody spectrum
#define NASA_SVS_MILKY_WAY          // NASA SVS 4851 photographic Milky Way from 1.7B stars (Gaia DR2/Tycho-2)
#define MILKY_WAY                   // Enable Milky Way galactic band rendering
#define MILKY_WAY_BRIGHTNESS 0.75   // [0.2 0.4 0.6 0.75 1.0 1.2 1.5 2.0] Visibility of galactic band
//#define CONSTELLATION_FIGURES     // IAU official constellation stick figures (NASA SVS 4851)
#define CONSTELLATION_INTENSITY 1.0 // [0.5 0.75 1.0 1.25 1.5] Constellation line brightness
//#define CELESTIAL_GRID            // Equatorial celestial coordinate grid (RA/Dec J2000)
#define CELESTIAL_GRID_INTENSITY 0.6 // [0.3 0.5 0.6 0.8 1.0] Celestial coordinate grid brightness
#define CELESTIAL_LATITUDE  42.0    // [0.0 20.0 30.0 42.0 50.0 60.0 90.0] Observer celestial latitude in degrees
#define METEOR_SHOWERS              // Shooting stars streaking through cosmos at night
#define AURORA_BOREALIS             // Dynamic undulating Northern Lights (prominent in cold biomes)
#define AURORA_INTENSITY    1.3     // [0.0 0.5 1.0 1.3 1.5 2.0] Aurora brightness

// --- Clouds (High-End Volumetric Raymarched) ---
#define ENABLE_CLOUDS               // Enable custom cloud system
#define VOLUMETRIC_3D_CLOUDS        // True 3D raymarched volumetric cloud slab for high-end PCs
#define VOLUMETRIC_CLOUD_STEPS 20   // [12 16 20 24 32] Raymarch sample count
#define CLOUD_LAYERS        2       // [1 2] 1: Single deck, 2: Dual cumulus & cirrus decks
#define CLOUD_SPEED         1.0     // [0.2 0.5 1.0 1.5 2.0] Wind drift speed
#define CLOUD_DENSITY       1.0     // [0.5 0.75 1.0 1.25 1.5] Base cloud thickness
#define CLOUD_SILVER_LINING         // Dual-lobe Henyey-Greenstein forward scattering rim
#define CLOUD_SHADOWING             // Directional self-shadowing and powder sugar effect

// --- Weather & Precipitation ---
#define DYNAMIC_WEATHER             // Atmospheric transitions during rain and thunderstorms
#define RAIN_FOG_DENSITY    1.0     // [0.5 0.75 1.0 1.5 2.0] Fog thickness during rain
#define STORM_LIGHTNING             // Branching procedural lightning flashes with terrain glow
#define DESERT_SANDSTORM            // Replaces rain with dust/sandstorm in desert/mesa biomes
#define RAIN_STREAKS                // Enhanced translucent raindrops with motion blur and lighting
#define WETNESS_EFFECT              // Puddle darkening and ground slickness during rainfall

// --- Post-Processing & Color ---
#define TONEMAP_ACES                // Academy Color Encoding System (ACES) filmic tonemapping
#define EXPOSURE            1.0     // [0.7 0.85 1.0 1.15 1.3] Scene exposure
#define SATURATION          1.08    // [0.8 0.9 1.0 1.08 1.15 1.25] Color saturation
#define VIGNETTE                    // Cinematic edge darkening
#define VIGNETTE_STRENGTH   0.22    // [0.1 0.2 0.22 0.35 0.5] Vignette intensity

#endif // SETTINGS_GLSL
