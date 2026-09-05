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

// --- Sky & Atmosphere (Physically Based Optics) ---
#define PHYSICAL_ATMOSPHERE         // Physically based atmospheric scattering & solar illumination
#define RAYLEIGH_SCATTERING         // Realistic Rayleigh atmospheric scattering (molecular lambda^-4)
#define RAYLEIGH_SCALE      1.0     // [0.5 0.75 1.0 1.25 1.5 2.0] Molecular scattering optical thickness
#define MIE_SCATTERING              // Forward Mie aerosol/haze scattering
#define MIE_TURBIDITY       1.0     // [0.5 0.75 1.0 1.25 1.5 2.0 3.0] Atmospheric aerosol turbidity & haze
#define OZONE_ABSORPTION            // Chappuis ozone layer absorption (deep blue/purple twilight)
#define OZONE_SCALE         1.0     // [0.0 0.5 0.75 1.0 1.25 1.5 2.0] Stratospheric ozone concentration
#define BELT_OF_VENUS               // Anti-solar twilight arch & Earth shadow projection
#define SKY_MULTI_SCATTERING        // Multi-scattering ambient sky fill
#define MULTI_SCATTER_SCALE 1.0     // [0.0 0.5 0.75 1.0 1.25 1.5 2.0] Secondary scattering intensity
#define SKY_GROUND_FOG              // Horizon and altitude atmospheric blending
#define ATMOSPHERE_DENSITY  1.0     // [0.5 0.75 1.0 1.25 1.5 2.0] Atmosphere optical thickness
#define SUN_ILLUMINANCE     1.0     // [0.5 0.75 1.0 1.25 1.5 2.0] Physical solar irradiance multiplier
#define SKY_RADIANCE_SCALE  1.0     // [0.5 0.75 1.0 1.25 1.5 2.0] Sky dome radiance exposure

// --- Sun ---
#define ENABLE_SUN                  // Custom procedural sun disc and atmospheric flare
#define SUN_SIZE            1.0     // [0.5 0.75 1.0 1.25 1.5 2.0] Angular diameter of the sun
#define SUN_LIMB_DARKENING          // 3-term polynomial solar limb darkening
#define SUN_ATMOSPHERIC_FLATTENING  // Atmospheric refraction flattening near horizon
#define SUN_CHROMATIC_CORONA        // Multi-spectral chromatic plasma corona ring
#define SUN_CORONA_INTENSITY 1.0    // [0.0 0.5 1.0 1.2 1.4 1.8 2.5] Intensity of solar corona glow
#define SUN_GLARE                   // Wide-angle atmospheric solar glare
#define SOLAR_DIFFRACTION_SPIKES    // Anamorphic 6-point solar flare diffraction spikes
#define GODRAYS                     // Volumetric crepuscular light shafts through clouds and horizon
#define GODRAYS_INTENSITY   1.3     // [0.5 0.75 1.0 1.2 1.3 1.6 2.0] Brightness of god rays
#define GODRAYS_SAMPLES     24      // [16 20 24 32 40] Raymarch steps for light shafts

// --- Moon ---
#define ENABLE_MOON                 // Custom high-detail procedural moon
#define MOON_SIZE           1.0     // [0.5 0.75 1.0 1.25 1.5 2.0] Angular diameter of the moon
#define MOON_BRIGHTNESS     0.80    // [0.2 0.4 0.6 0.8 1.0 1.2 1.5] Moon surface radiance / brightness
#define MOON_PHASES                 // Realistic 8-phase lunar cycle based on world moonPhase
#define MOON_SURFACE_DETAIL         // Procedural lunar maria (basalt seas) and crater relief
#define MOON_CRATER_RELIEF          // 3D normal-mapped crater rim relief along terminator
#define MOON_EARTHSHINE             // Subtle illumination of the unlit lunar crescent
#define MOON_HALO                   // Ethereal lunar atmospheric halo / ice crystal ring
#define MOON_HALO_INTENSITY 0.4     // [0.0 0.2 0.4 0.6 0.8 1.0 1.5] Halo brightness

// --- Night Sky & Celestials (NASA SVS 4851 Deep Star Maps Edition) ---
#define ENABLE_STARS                // High-density procedural star field
#define STARS_DENSITY       1.35    // [0.5 0.75 1.0 1.2 1.35 1.6 2.0] Total number of visible stars
#define STARS_TWINKLE               // Atmospheric scintillation / temporal twinkling
#define STARS_COLOR_VARIETY         // Spectral star classifications via Ballesteros blackbody spectrum
#define NASA_SVS_MILKY_WAY          // NASA SVS 4851 photographic Milky Way from 1.7B stars (Gaia DR2/Tycho-2)
#define MILKY_WAY                   // Enable Milky Way galactic band rendering
#define MILKY_WAY_BRIGHTNESS 0.85   // [0.2 0.4 0.6 0.75 0.85 1.0 1.2 1.5 2.0] Visibility of galactic band
#define MILKY_WAY_H_ALPHA           // Hydrogen-alpha red/magenta emission nebula enhancement
//#define CONSTELLATION_FIGURES     // IAU official constellation stick figures (NASA SVS 4851)
#define CONSTELLATION_INTENSITY 1.0 // [0.5 0.75 1.0 1.25 1.5] Constellation line brightness
//#define CELESTIAL_GRID            // Equatorial celestial coordinate grid (RA/Dec J2000)
#define CELESTIAL_GRID_INTENSITY 0.6 // [0.3 0.5 0.6 0.8 1.0] Celestial coordinate grid brightness
#define CELESTIAL_LATITUDE  42.0    // [0.0 20.0 30.0 42.0 50.0 60.0 90.0] Observer celestial latitude in degrees
#define METEOR_SHOWERS              // Shooting stars streaking through cosmos at night
#define AURORA_BOREALIS             // Dynamic undulating Northern Lights (prominent in cold biomes)
#define AURORA_INTENSITY    1.35    // [0.0 0.5 1.0 1.35 1.6 2.0] Aurora brightness
#define AURORA_RAY_STREAMERS        // High-definition vertical auroral ray streamers

// --- Clouds (WMO 10 Genera High-End Volumetric Raymarched) ---
#define ENABLE_CLOUDS               // Enable custom cloud system
#define VOLUMETRIC_3D_CLOUDS        // True 3D raymarched volumetric cloud slab for high-end PCs
#ifndef VOLUMETRIC_CLOUD_STEPS
#define VOLUMETRIC_CLOUD_STEPS 20   // [12 16 20 24 28 32] Raymarch sample count
#endif
#ifndef CLOUD_LAYERS
#define CLOUD_LAYERS        2       // [1 2 3] 1: Single deck, 2: Dual decks, 3: Multi-tier WMO
#endif
#ifndef CLOUD_SPEED
#define CLOUD_SPEED         1.0     // [0.2 0.5 1.0 1.5 2.0] Wind drift speed
#endif
#ifndef CLOUD_DENSITY
#define CLOUD_DENSITY       1.0     // [0.5 0.75 1.0 1.25 1.5] Base cloud optical thickness
#endif
#ifndef CLOUD_COVERAGE
#define CLOUD_COVERAGE      1.0     // [0.4 0.6 0.8 1.0 1.2 1.4] Sky cloud coverage factor
#endif
#ifndef CLOUD_WMO_GENUS
#define CLOUD_WMO_GENUS     0       // [0 1 2 3 4 5 6 7 8 9 10] 0: Auto (Weather/Biome), 1: Cirrus, 2: Cirrocumulus, 3: Cirrostratus, 4: Altocumulus, 5: Altostratus, 6: Stratocumulus, 7: Stratus, 8: Nimbostratus, 9: Cumulus, 10: Cumulonimbus
#endif
#define CLOUD_SILVER_LINING         // Dual-lobe Henyey-Greenstein forward scattering rim
#define CLOUD_SHADOWING             // Directional self-shadowing and powder sugar effect
#define CLOUD_ICE_HALO              // Optical 22° Solar/Lunar ice crystal refraction halo for Cirrostratus


// --- Weather & Precipitation ---
#define DYNAMIC_WEATHER             // Atmospheric transitions during rain and thunderstorms
#define RAIN_FOG_DENSITY    1.0     // [0.5 0.75 1.0 1.5 2.0] Fog thickness during rain
#define STORM_LIGHTNING             // Cinematic procedural lightning discharges (CG, CC & IC)
#define LIGHTNING_BOLTS             // Render visible geometric fractal lightning bolts in the sky
#define LIGHTNING_BRANCH_GEN 4      // [1 2 3 4] Stepped leader fractal branching depth (1=Trunk, 2=Primary branches, 3=Secondary twigs, 4=Full 4-tier dendritic hierarchy)
#define LIGHTNING_ROUGHNESS 1.6     // [0.8 1.0 1.2 1.4 1.6 1.8 2.0] Channel tortuosity / roughness factor (dielectric breakdown stepped leader)
#define LIGHTNING_INTRA_CLOUD       // 3D volumetric internal scattering & illumination in storm clouds
#define LIGHTNING_INTENSITY 1.0     // [0.5 0.75 1.0 1.25 1.5 2.0] Brightness scale of lightning discharges
#define DESERT_SANDSTORM            // Replaces rain with dust/sandstorm in desert/mesa biomes
#define RAIN_STREAKS                // Enhanced translucent raindrops with motion blur and lighting
#define PROCEDURAL_RAIN             // Aerodynamic sub-pixel needle raindrop streaks
#define RAIN_MIE_GLISTEN            // Strong forward Mie scattering glisten when backlit
#define PROCEDURAL_SNOW             // 6-fold dendritic Keplerian hexagonal snowflakes (D6h symmetry)
#define SNOW_FLUTTER                // Aerodynamic fluttering tumble & micro-turbulence
#define SNOW_DIAMOND_DUST           // Micro-facet specular sparkling on falling ice crystals
#define SNOW_CRYSTAL_SIZE   1.0     // [0.5 0.75 1.0 1.25 1.5] Scale of procedural snowflakes
#define WETNESS_EFFECT              // Puddle darkening and ground slickness during rainfall

// --- Fire & Plasma Thermodynamics ---
#define CINEMATIC_FIRE              // Thermodynamic blackbody fire and convective plasma
#define FIRE_BLACKBODY_CORE         // Ultra-bright >2000K incandescent white-yellow reaction core
#define FIRE_TURBULENCE             // Buoyant thermal convective plumes and swirling flame licks
#define SOUL_FIRE_SPECTRAL          // High-energy Swan-band ionized cyan plasma for soul fire
#define FIRE_EMBERS                 // Detached glowing embers and floating sparks drifting upward
#define CINEMATIC_SCREEN_FIRE       // Peripheral heat and flame vignette when player is burning
#define SCREEN_FIRE_OPACITY 0.75    // [0.3 0.5 0.7 0.75 0.85 1.0] Intensity of camera fire overlay

// --- Post-Processing & Color ---
#define TONEMAP_ACES                // Academy Color Encoding System (ACES) filmic tonemapping
#define EXPOSURE            1.0     // [0.7 0.85 1.0 1.15 1.3] Scene exposure
#define SATURATION          1.08    // [0.8 0.9 1.0 1.08 1.15 1.25] Color saturation
#define VIGNETTE                    // Cinematic edge darkening
#define VIGNETTE_STRENGTH   0.22    // [0.1 0.2 0.22 0.35 0.5] Vignette intensity

#endif // SETTINGS_GLSL
