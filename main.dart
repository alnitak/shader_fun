import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shader_fun/shader_fun.dart';

void main() {
  runApp(const OceanSimulationApp());
}

/// Standalone Flutter application showcasing a photorealistic real-time ocean
/// simulation with multi-pass rendering and enhanced realism.
class OceanSimulationApp extends StatelessWidget {
  /// Creates the [OceanSimulationApp].
  const OceanSimulationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photorealistic Ocean Simulation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090D14),
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color(0xFF38BDF8),
          inactiveTrackColor: Colors.white12,
          thumbColor: const Color(0xFF38BDF8),
          overlayColor: const Color(0xFF38BDF8).withValues(alpha: 0.2),
          trackHeight: 3.0,
        ),
      ),
      home: const OceanScreen(),
    );
  }
}

/// Main ocean viewport screen with control sidebar.
class OceanScreen extends StatefulWidget {
  /// Creates the [OceanScreen].
  const OceanScreen({super.key});

  @override
  State<OceanScreen> createState() => _OceanScreenState();
}

class _OceanScreenState extends State<OceanScreen> {
  late final ShaderController _controller;
  bool _isPanelOpen = true;

  // Ocean Simulation Parameters
  double _waveHeight = 1.2;
  double _waveSpeed = 1.1;
  double _choppiness = 2.0;
  double _frequency = 0.18;
  double _waterClarity = 0.65;

  // Sky & Lighting Parameters
  double _sunElevation = 0.35;
  double _sunAzimuth = 0.45;
  double _fogDensity = 0.25;

  // Wind & Foam Parameters
  double _windSpeed = 1.4;
  double _turbulence = 0.85;
  double _foamIntensity = 1.2;

  // Buffer A: Procedural noise texture generation for turbulence
  static const String _noiseBufferGlsl = '''
// High-quality procedural noise for wave turbulence and foam
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float hash13(vec3 p) {
    return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

float smoothNoise2D(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2(0.0, 0.0)), hash21(i + vec2(1.0, 0.0)), u.x),
        mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
        u.y
    );
}

float smoothNoise3D(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);

    float a = hash13(i + vec3(0.0, 0.0, 0.0));
    float b = hash13(i + vec3(1.0, 0.0, 0.0));
    float c = hash13(i + vec3(0.0, 1.0, 0.0));
    float d = hash13(i + vec3(1.0, 1.0, 0.0));
    float e = hash13(i + vec3(0.0, 0.0, 1.0));
    float f2 = hash13(i + vec3(1.0, 0.0, 1.0));
    float g = hash13(i + vec3(0.0, 1.0, 1.0));
    float h = hash13(i + vec3(1.0, 1.0, 1.0));

    return mix(
        mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
        mix(mix(e, f2, u.x), mix(g, h, u.x), u.y),
        u.z
    );
}

float fbm2D(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 6; i++) {
        v += a * smoothNoise2D(p);
        p = p * 2.03 + vec2(0.5);
        a *= 0.5;
    }
    return v;
}

float fbm3D(vec3 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * smoothNoise3D(p);
        p = p * 2.02 + vec3(0.3);
        a *= 0.5;
    }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 p = uv * 8.0;

    // Multi-octave noise for different purposes
    // R: Fine detail turbulence (animated)
    // G: Medium foam pattern
    // B: Large-scale wave modulation
    // A: 3D volumetric noise for caustics

    vec3 p3 = vec3(p, iTime * 0.1);

    float r = fbm2D(p + iTime * 0.3);
    float g = fbm2D(p * 1.5 - iTime * 0.2);
    float b = fbm2D(p * 0.5 + iTime * 0.15);
    float a = fbm3D(p3);

    fragColor = vec4(r, g, b, a);
}
''';

  // Buffer B: Wave height field and foam accumulation
  static const String _waveBufferGlsl = '''
uniform float uWaveHeight;
uniform float uWaveSpeed;
uniform float uChoppiness;
uniform float uFrequency;
uniform float uWindSpeed;
uniform float uTurbulence;
uniform sampler2D iChannel0; // Noise texture

const float PI = 3.14159265359;

mat2 rot2D(float a) {
    float c = cos(a);
    float s = sin(a);
    return mat2(c, -s, s, c);
}

// Enhanced Gerstner wave with directional wind influence
float gerstnerWave(vec2 p, vec2 dir, float freq, float speed, float steepness, float time) {
    float k = freq * 2.0 * PI;
    float phase = dot(p, dir) * k + time * speed;
    float sharpness = pow(0.5 + 0.5 * sin(phase), steepness);
    return sharpness * 2.0 - 1.0;
}

// Multi-directional wave field with realistic spectrum
float oceanHeightField(vec2 p, float time) {
    float freq = uFrequency;
    float amp = uWaveHeight;
    float speed = uWaveSpeed * uWindSpeed * 1.5;
    float steep = uChoppiness * 0.8;

    vec2 windDir = normalize(vec2(0.8, 0.6));

    float height = 0.0;

    // Primary wave train (dominant wind direction)
    height += gerstnerWave(p, windDir, freq, speed, steep, time) * amp * 0.5;

    // Secondary wave trains (cross-seas)
    vec2 p2 = rot2D(0.6) * p;
    height += gerstnerWave(p2, windDir, freq * 1.4, speed * 1.1, steep * 0.9, time) * amp * 0.3;

    vec2 p3 = rot2D(-0.8) * p;
    height += gerstnerWave(p3, windDir, freq * 1.9, speed * 1.25, steep * 0.8, time) * amp * 0.2;

    // Fine capillary waves
    vec2 p4 = rot2D(1.2) * p;
    height += gerstnerWave(p4, windDir, freq * 3.5, speed * 1.5, 1.0, time) * amp * 0.15;

    // High-frequency ripples
    height += gerstnerWave(p, windDir, freq * 6.0, speed * 2.0, 0.8, time) * amp * 0.08;

    return height;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 worldPos = (uv - 0.5) * 50.0;

    // Sample height at current position
    float h = oceanHeightField(worldPos, iTime);

    // Sample neighboring heights for gradient
    float eps = 0.1;
    float hx = oceanHeightField(worldPos + vec2(eps, 0.0), iTime);
    float hz = oceanHeightField(worldPos + vec2(0.0, eps), iTime);

    vec2 gradient = vec2(h - hx, h - hz) / eps;
    float slope = length(gradient);

    // Turbulent foam generation using noise texture
    vec4 noise = texture(iChannel0, uv * 2.0 + iTime * 0.1);
    float turbulentFoam = smoothstep(0.3, 0.8, noise.g) * uTurbulence;

    // Crest detection for whitecaps
    float crestFoam = smoothstep(uWaveHeight * 0.4, uWaveHeight * 0.9, h) * slope * 3.0;

    // Combined foam intensity
    float foam = clamp(crestFoam + turbulentFoam, 0.0, 1.0);

    // Store: R=height, G=foam, B=slope, A=turbulence
    fragColor = vec4(h * 0.5 + 0.5, foam, slope, noise.r);
}
''';

  // Main Image: Final photorealistic ocean render
  static const String _oceanMainGlsl = '''
uniform float uWaveHeight;
uniform float uWaveSpeed;
uniform float uChoppiness;
uniform float uFrequency;
uniform float uWaterClarity;
uniform float uSunElevation;
uniform float uSunAzimuth;
uniform float uTurbulence;
uniform float uFoamIntensity;
uniform float uWindSpeed;
uniform float uFogDensity;
uniform sampler2D iChannel0; // Noise texture
uniform sampler2D iChannel1; // Wave/foam buffer

const int MAX_MARCH_STEPS = 60;
const int MAX_CLOUD_STEPS = 24;
const float PI = 3.14159265359;
const float EPSILON = 0.01;

mat2 rot2D(float a) {
    float c = cos(a);
    float s = sin(a);
    return mat2(c, -s, s, c);
}

// Sample noise texture
float noise(vec2 p) {
    return texture(iChannel0, p * 0.125).r;
}

float fbmClouds(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.03 + vec2(0.7, 0.3);
        a *= 0.5;
    }
    return v;
}

// Directional Gerstner wave
float gerstnerWave(vec2 p, vec2 dir, float freq, float speed, float steepness) {
    float phase = dot(p, dir) * freq * 2.0 * PI + iTime * speed;
    return pow(0.5 + 0.5 * sin(phase), steepness) * 2.0 - 1.0;
}

// Ocean height sampling (must match Buffer B)
float oceanHeight(vec2 p) {
    float freq = uFrequency;
    float amp = uWaveHeight;
    float speed = uWaveSpeed * uWindSpeed * 1.5;
    float steep = uChoppiness * 0.8;

    vec2 windDir = normalize(vec2(0.8, 0.6));
    float h = 0.0;

    h += gerstnerWave(p, windDir, freq, speed, steep) * amp * 0.5;
    h += gerstnerWave(rot2D(0.6) * p, windDir, freq * 1.4, speed * 1.1, steep * 0.9) * amp * 0.3;
    h += gerstnerWave(rot2D(-0.8) * p, windDir, freq * 1.9, speed * 1.25, steep * 0.8) * amp * 0.2;
    h += gerstnerWave(rot2D(1.2) * p, windDir, freq * 3.5, speed * 1.5, 1.0) * amp * 0.15;
    h += gerstnerWave(p, windDir, freq * 6.0, speed * 2.0, 0.8) * amp * 0.08;

    // Add micro-turbulence
    vec4 noiseVal = texture(iChannel0, p * 0.2 + iTime * 0.1);
    h += (noiseVal.r - 0.5) * 0.1 * uTurbulence;

    return h;
}

vec3 getNormal(vec3 p, float eps) {
    vec2 e = vec2(eps, 0.0);
    float h = oceanHeight(p.xz);
    return normalize(vec3(
        h - oceanHeight(p.xz + e.xy),
        eps,
        h - oceanHeight(p.xz + e.yx)
    ));
}

// Photorealistic sky with volumetric clouds
vec3 renderSky(vec3 rd, vec3 sunDir) {
    float horizon = max(rd.y, 0.0);
    float sunElev = max(sunDir.y, 0.0);

    // Atmospheric gradient
    vec3 zenithColor = mix(vec3(0.05, 0.15, 0.35), vec3(0.18, 0.42, 0.75), sunElev);
    vec3 horizonColor = mix(vec3(0.92, 0.82, 0.78), vec3(0.70, 0.80, 0.92), sunElev);
    vec3 sky = mix(horizonColor, zenithColor, pow(horizon, 0.4));

    // Sun
    float sunDot = max(dot(rd, sunDir), 0.0);
    float sunDisc = smoothstep(0.9992, 0.9998, sunDot) * 5.0;
    float sunGlow = pow(sunDot, 8.0) * 0.8;
    vec3 sunColor = mix(vec3(1.0, 0.85, 0.6), vec3(1.0, 1.0, 0.95), sunElev);
    sky += (sunDisc + sunGlow) * sunColor;

    // Volumetric clouds
    if (rd.y > 0.0) {
        vec2 cloudUV = (rd.xz / (rd.y + 0.12)) * 0.08;
        cloudUV += vec2(iTime * 0.005, iTime * 0.003);

        float cloudDensity = fbmClouds(cloudUV);
        float cloudMask = smoothstep(0.42, 0.75, cloudDensity);
        cloudMask *= smoothstep(0.0, 0.15, rd.y);

        // Cloud shading
        vec3 cloudLight = vec3(1.0);
        cloudLight = mix(vec3(0.75, 0.78, 0.85), vec3(1.0, 1.0, 1.0), smoothstep(0.5, 0.8, cloudDensity));
        cloudLight += sunColor * pow(sunDot, 3.0) * 0.3;

        sky = mix(sky, cloudLight, cloudMask * 0.92);
    }

    return sky;
}

// Enhanced raymarch with adaptive stepping
bool marchOcean(vec3 ro, vec3 rd, out vec3 hitPos, out float dist) {
    if (rd.y >= 0.0) return false;

    float maxH = uWaveHeight * 1.5;
    float tMin = max(0.1, (maxH - ro.y) / rd.y);
    float tMax = min(500.0, (-maxH - ro.y) / rd.y);

    if (tMax <= tMin) return false;

    float t = tMin;
    float dt = (tMax - tMin) / float(MAX_MARCH_STEPS);

    for (int i = 0; i < MAX_MARCH_STEPS; i++) {
        vec3 p = ro + rd * t;
        float h = oceanHeight(p.xz);
        float diff = p.y - h;

        if (diff < 0.0) {
            // Bisection refinement
            float t0 = t - dt;
            float t1 = t;
            for (int j = 0; j < 8; j++) {
                float tm = (t0 + t1) * 0.5;
                vec3 pm = ro + rd * tm;
                if (pm.y < oceanHeight(pm.xz)) {
                    t1 = tm;
                } else {
                    t0 = tm;
                }
            }
            dist = (t0 + t1) * 0.5;
            hitPos = ro + rd * dist;
            return true;
        }

        t += dt;
    }

    return false;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;

    // Camera setup
    vec2 mouse = iMouse.xy / iResolution.xy;
    if (iMouse.z <= 0.0 || length(iMouse.xy) < 1.0) {
        mouse = vec2(0.5 + sin(iTime * 0.04) * 0.08, 0.40);
    }

    float yaw = (mouse.x - 0.5) * 4.0;
    float pitch = mix(-0.05, 0.6, mouse.y);

    // Camera positioned low over the waves
    vec3 camPos = vec3(sin(iTime * 0.1) * 2.0, 1.5 + uWaveHeight * 0.4, iTime * 0.5 - 8.0);
    vec3 rayDir = normalize(vec3(uv.x, uv.y - 0.05, 1.4));

    rayDir.yz = rot2D(-pitch) * rayDir.yz;
    rayDir.xz = rot2D(yaw) * rayDir.xz;

    // Sun direction
    vec3 sunDir = normalize(vec3(
        sin(uSunAzimuth) * cos(uSunElevation),
        sin(uSunElevation),
        cos(uSunAzimuth) * cos(uSunElevation)
    ));

    vec3 skyColor = renderSky(rayDir, sunDir);
    vec3 col = skyColor;

    // Raymarch ocean
    vec3 waterPos;
    float waterDist;

    if (marchOcean(camPos, rayDir, waterPos, waterDist)) {
        float eps = max(0.008, waterDist * 0.001);
        vec3 normal = getNormal(waterPos, eps);

        // Fresnel
        float ndotv = max(dot(-rayDir, normal), 0.0);
        float fresnel = 0.02 + 0.98 * pow(1.0 - ndotv, 5.0);

        // Reflection
        vec3 reflDir = reflect(rayDir, normal);
        vec3 reflColor = renderSky(reflDir, sunDir);

        // Specular highlights
        float specDot = max(dot(reflDir, sunDir), 0.0);
        float specular = pow(specDot, 380.0) * 6.0 + pow(specDot, 45.0) * 1.5;
        reflColor += specular * vec3(1.0, 0.96, 0.88);

        // Refraction and underwater
        vec3 refractDir = refract(rayDir, normal, 1.0 / 1.333);
        if (refractDir.y >= 0.0 || length(refractDir) < 0.1) {
            refractDir = normalize(vec3(rayDir.x * 0.6, -1.0, rayDir.z * 0.6));
        }

        // Seabed with rocks
        float seabedDepth = 3.5;
        float tBed = (waterPos.y - (-seabedDepth)) / max(-refractDir.y, 0.05);
        vec3 bedPos = waterPos + refractDir * min(tBed, 25.0);

        // Procedural underwater rocks/coral formations
        float rock1 = smoothstep(3.0, 0.3, length(bedPos.xz - vec2(-2.0, 6.0)));
        float rock2 = smoothstep(4.0, 0.5, length(bedPos.xz - vec2(3.5, 10.0)));
        float rock3 = smoothstep(2.5, 0.2, length(bedPos.xz - vec2(-5.0, 13.0)));
        float rock4 = smoothstep(3.5, 0.4, length(bedPos.xz - vec2(1.0, 8.0)));
        float rockPresence = max(max(rock1, rock2), max(rock3, rock4));

        // Caustics
        vec4 noiseVal = texture(iChannel0, bedPos.xz * 0.15 + iTime * 0.05);
        float caustic1 = pow(noiseVal.r * noiseVal.a, 1.8) * 3.5;
        float caustic2 = pow(noise(bedPos.xz * 0.3 - iTime * 0.03), 2.0) * 2.0;
        float caustics = (caustic1 + caustic2) * 0.5;

        // Seabed color
        vec3 sandColor = vec3(0.06, 0.50, 0.62) * (1.0 + caustics * 0.4);
        vec3 rockColor = vec3(0.04, 0.08, 0.12);
        vec3 seabedColor = mix(sandColor, rockColor, rockPresence * 0.90);

        // Light attenuation through water
        float waterDepth = length(bedPos - waterPos);
        float clarity = mix(0.3, 1.0, uWaterClarity);
        vec3 extinction = exp(-vec3(0.65, 0.20, 0.08) * waterDepth * (2.0 - clarity));

        // Deep water body color
        vec3 deepColor = vec3(0.01, 0.08, 0.22);
        vec3 waterColor = mix(deepColor, seabedColor, extinction);

        // Subsurface scattering
        float sss = pow(max(dot(refractDir, sunDir), 0.0), 2.5);
        sss *= smoothstep(-0.3, 1.0, waterPos.y / max(uWaveHeight, 0.5));
        sss *= max(normal.y, 0.0);
        waterColor += vec3(0.04, 0.45, 0.40) * sss * 0.7;

        // Combine water and reflection
        col = mix(waterColor, reflColor, fresnel);

        // Foam from buffer
        vec2 foamUV = (waterPos.xz + 25.0) / 50.0;
        vec4 waveData = texture(iChannel1, foamUV);
        float foamMask = waveData.g * uFoamIntensity;

        // Additional foam detail
        float foamNoise = texture(iChannel0, waterPos.xz * 0.5 + iTime * 0.08).g;
        foamMask *= smoothstep(0.35, 0.75, foamNoise);

        vec3 foamColor = vec3(0.90, 0.94, 0.98);
        col = mix(col, foamColor, clamp(foamMask, 0.0, 0.88));

        // Atmospheric fog
        float fogAmount = 1.0 - exp(-waterDist * 0.003 * (1.0 + uFogDensity * 3.0));
        col = mix(col, skyColor, fogAmount);
    }

    // Tonemapping and color grading
    col = col / (col + vec3(0.75));
    col = pow(col, vec3(0.4545)); // Gamma correction

    // Subtle vignette
    float vignette = 1.0 - 0.3 * length(fragCoord / iResolution.xy - 0.5);
    col *= vignette;

    fragColor = vec4(col, 1.0);
}
''';

  @override
  void initState() {
    super.initState();

    // Multi-pass setup: Noise -> Wave Field -> Final Render
    final noisePass = ShaderPass(
      name: 'NoiseBuffer',
      type: PassType.bufferA,
      mode: ShaderPassMode.shaderToy,
      code: _noiseBufferGlsl,
    );

    final wavePass = ShaderPass(
      name: 'WaveField',
      type: PassType.bufferB,
      mode: ShaderPassMode.shaderToy,
      code: _waveBufferGlsl,
      channels: [
        ShaderChannel(source: PassType.bufferA), // Noise texture
      ],
    );

    final mainPass = ShaderPass(
      name: 'OceanMain',
      type: PassType.image,
      mode: ShaderPassMode.shaderToy,
      code: _oceanMainGlsl,
      channels: [
        ShaderChannel(source: PassType.bufferA), // Noise texture
        ShaderChannel(source: PassType.bufferB), // Wave/foam data
      ],
    );

    _controller = ShaderController(
      autoPlay: true,
      initialProject: ShaderProject(
        passes: <ShaderPass>[noisePass, wavePass, mainPass],
      ),
    );

    _updateAllUniforms();
  }

  void _updateAllUniforms() {
    // Update all passes with uniforms
    for (var passType in [PassType.bufferB, PassType.image]) {
      _controller.setUniform('uWaveHeight', _waveHeight, passType: passType);
      _controller.setUniform('uWaveSpeed', _waveSpeed, passType: passType);
      _controller.setUniform('uChoppiness', _choppiness, passType: passType);
      _controller.setUniform('uFrequency', _frequency, passType: passType);
      _controller.setUniform(
        'uWaterClarity',
        _waterClarity,
        passType: passType,
      );
      _controller.setUniform(
        'uSunElevation',
        _sunElevation,
        passType: passType,
      );
      _controller.setUniform('uSunAzimuth', _sunAzimuth, passType: passType);
      _controller.setUniform('uTurbulence', _turbulence, passType: passType);
      _controller.setUniform(
        'uFoamIntensity',
        _foamIntensity,
        passType: passType,
      );
      _controller.setUniform('uWindSpeed', _windSpeed, passType: passType);
      _controller.setUniform('uFogDensity', _fogDensity, passType: passType);
    }
  }

  void _applyPreset(String name) {
    setState(() {
      switch (name) {
        case 'Reference Image':
          _waveHeight = 1.2;
          _waveSpeed = 1.1;
          _choppiness = 2.0;
          _frequency = 0.18;
          _waterClarity = 0.65;
          _sunElevation = 0.35;
          _sunAzimuth = 0.45;
          _fogDensity = 0.25;
          _windSpeed = 1.4;
          _turbulence = 0.85;
          _foamIntensity = 1.2;
        case 'Calm Waters':
          _waveHeight = 0.4;
          _waveSpeed = 0.6;
          _choppiness = 1.2;
          _frequency = 0.12;
          _waterClarity = 0.95;
          _sunElevation = 0.60;
          _sunAzimuth = 0.25;
          _fogDensity = 0.08;
          _windSpeed = 0.6;
          _turbulence = 0.2;
          _foamIntensity = 0.3;
        case 'Stormy Seas':
          _waveHeight = 2.0;
          _waveSpeed = 1.8;
          _choppiness = 2.8;
          _frequency = 0.24;
          _waterClarity = 0.3;
          _sunElevation = 0.18;
          _sunAzimuth = 1.0;
          _fogDensity = 0.55;
          _windSpeed = 2.2;
          _turbulence = 1.5;
          _foamIntensity = 2.0;
        case 'Tropical Paradise':
          _waveHeight = 0.8;
          _waveSpeed = 0.8;
          _choppiness = 1.5;
          _frequency = 0.15;
          _waterClarity = 0.98;
          _sunElevation = 0.70;
          _sunAzimuth = 0.30;
          _fogDensity = 0.02;
          _windSpeed = 0.9;
          _turbulence = 0.3;
          _foamIntensity = 0.6;
        case 'Arctic Waters':
          _waveHeight = 1.5;
          _waveSpeed = 1.0;
          _choppiness = 2.2;
          _frequency = 0.20;
          _waterClarity = 0.85;
          _sunElevation = 0.12;
          _sunAzimuth = 0.80;
          _fogDensity = 0.40;
          _windSpeed = 1.6;
          _turbulence = 1.0;
          _foamIntensity = 1.4;
      }
      _updateAllUniforms();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D14),
      body: Stack(
        children: [
          // Fullscreen Shader Viewport
          Positioned.fill(child: ShaderViewport(controller: _controller)),

          // Top-Left Title Overlay
          Positioned(
            top: 24,
            left: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.70),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.water, color: Color(0xFF38BDF8), size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Photorealistic Ocean',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Multi-Pass',
                          style: TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.mouse,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Drag to orbit camera',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Control Panel Toggle Button
          Positioned(
            top: 24,
            right: _isPanelOpen ? 376 : 24,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: () => setState(() => _isPanelOpen = !_isPanelOpen),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 12,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isPanelOpen ? Icons.chevron_right : Icons.tune,
                        color: const Color(0xFF38BDF8),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isPanelOpen ? 'Hide' : 'Controls',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Right-Side Control Panel
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            top: 20,
            bottom: 20,
            right: _isPanelOpen ? 20 : -360,
            width: 340,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.tune,
                            color: Color(0xFF38BDF8),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Ocean Parameters',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(
                              Icons.refresh,
                              size: 18,
                              color: Colors.white70,
                            ),
                            tooltip: 'Reset to reference',
                            onPressed: () => _applyPreset('Reference Image'),
                          ),
                        ],
                      ),
                    ),

                    // Scrollable Controls
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                        children: [
                          // Presets
                          const Text(
                            'SCENE PRESETS',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _buildPresetChip('Reference', 'Reference Image'),
                              _buildPresetChip('Calm', 'Calm Waters'),
                              _buildPresetChip('Stormy', 'Stormy Seas'),
                              _buildPresetChip('Tropical', 'Tropical Paradise'),
                              _buildPresetChip('Arctic', 'Arctic Waters'),
                            ],
                          ),

                          const SizedBox(height: 20),
                          _buildSectionHeader('WAVE DYNAMICS', Icons.waves),
                          _buildSlider(
                            label: 'Wave Height',
                            value: _waveHeight,
                            min: 0.2,
                            max: 2.5,
                            unit: 'm',
                            onChanged: (val) {
                              setState(() => _waveHeight = val);
                              _controller.setUniform(
                                'uWaveHeight',
                                val,
                                passType: PassType.bufferB,
                              );
                              _controller.setUniform(
                                'uWaveHeight',
                                val,
                                passType: PassType.image,
                              );
                            },
                          ),
                          _buildSlider(
                            label: 'Wave Speed',
                            value: _waveSpeed,
                            min: 0.2,
                            max: 2.5,
                            unit: 'x',
                            onChanged: (val) {
                              setState(() => _waveSpeed = val);
                              _controller.setUniform(
                                'uWaveSpeed',
                                val,
                                passType: PassType.bufferB,
                              );
                              _controller.setUniform(
                                'uWaveSpeed',
                                val,
                                passType: PassType.image,
                              );
                            },
                          ),
                          _buildSlider(
                            label: 'Choppiness',
                            value: _choppiness,
                            min: 0.5,
                            max: 3.0,
                            unit: '',
                            onChanged: (val) {
                              setState(() => _choppiness = val);
                              _controller.setUniform(
                                'uChoppiness',
                                val,
                                passType: PassType.bufferB,
                              );
                              _controller.setUniform(
                                'uChoppiness',
                                val,
                                passType: PassType.image,
                              );
                            },
                          ),
                          _buildSlider(
                            label: 'Wave Frequency',
                            value: _frequency,
                            min: 0.05,
                            max: 0.35,
                            unit: 'Hz',
                            onChanged: (val) {
                              setState(() => _frequency = val);
                              _controller.setUniform(
                                'uFrequency',
                                val,
                                passType: PassType.bufferB,
                              );
                              _controller.setUniform(
                                'uFrequency',
                                val,
                                passType: PassType.image,
                              );
                            },
                          ),
                          _buildSlider(
                            label: 'Water Clarity',
                            value: _waterClarity,
                            min: 0.0,
                            max: 1.0,
                            unit: '%',
                            onChanged: (val) {
                              setState(() => _waterClarity = val);
                              _controller.setUniform(
                                'uWaterClarity',
                                val,
                                passType: PassType.image,
                              );
                            },
                          ),

                          const SizedBox(height: 20),
                          _buildSectionHeader('WIND & FOAM', Icons.air),
                          _buildSlider(
                            label: 'Wind Speed',
                            value: _windSpeed,
                            min: 0.3,
                            max: 3.0,
                            unit: 'kts',
                            onChanged: (val) {
                              setState(() => _windSpeed = val);
                              _controller.setUniform(
                                'uWindSpeed',
                                val,
                                passType: PassType.bufferB,
                              );
                              _controller.setUniform(
                                'uWindSpeed',
                                val,
                                passType: PassType.image,
                              );
                            },
                          ),
                          _buildSlider(
                            label: 'Turbulence',
                            value: _turbulence,
                            min: 0.0,
                            max: 2.0,
                            unit: '',
                            onChanged: (val) {
                              setState(() => _turbulence = val);
                              _controller.setUniform(
                                'uTurbulence',
                                val,
                                passType: PassType.bufferB,
                              );
                              _controller.setUniform(
                                'uTurbulence',
                                val,
                                passType: PassType.image,
                              );
                            },
                          ),
                          _buildSlider(
                            label: 'Foam Intensity',
                            value: _foamIntensity,
                            min: 0.0,
                            max: 2.5,
                            unit: '',
                            onChanged: (val) {
                              setState(() => _foamIntensity = val);
                              _controller.setUniform(
                                'uFoamIntensity',
                                val,
                                passType: PassType.image,
                              );
                            },
                          ),

                          const SizedBox(height: 20),
                          _buildSectionHeader('LIGHTING & SKY', Icons.wb_sunny),
                          _buildSlider(
                            label: 'Sun Elevation',
                            value: _sunElevation,
                            min: 0.05,
                            max: 0.8,
                            unit: 'rad',
                            onChanged: (val) {
                              setState(() => _sunElevation = val);
                              _controller.setUniform(
                                'uSunElevation',
                                val,
                                passType: PassType.image,
                              );
                            },
                          ),
                          _buildSlider(
                            label: 'Sun Azimuth',
                            value: _sunAzimuth,
                            min: -math.pi,
                            max: math.pi,
                            unit: 'rad',
                            onChanged: (val) {
                              setState(() => _sunAzimuth = val);
                              _controller.setUniform(
                                'uSunAzimuth',
                                val,
                                passType: PassType.image,
                              );
                            },
                          ),
                          _buildSlider(
                            label: 'Fog Density',
                            value: _fogDensity,
                            min: 0.0,
                            max: 1.0,
                            unit: '%',
                            onChanged: (val) {
                              setState(() => _fogDensity = val);
                              _controller.setUniform(
                                'uFogDensity',
                                val,
                                passType: PassType.image,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, String presetName) {
    return ActionChip(
      label: Text(label),
      labelStyle: const TextStyle(
        fontSize: 11,
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      onPressed: () => _applyPreset(presetName),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF38BDF8), size: 14),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    final displayVal = unit.isNotEmpty
        ? '${value.toStringAsFixed(2)} $unit'
        : value.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                displayVal,
                style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
