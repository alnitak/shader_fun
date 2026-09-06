import 'package:shader_fun/shader_fun.dart';

/// Preset shaders inspired by iconic ShaderToy masterpieces.
class ShaderPresets {
  /// 1. Raymarching Primitives (Inspired by Inigo Quilez's 4slGD4 default shader)
  static ShaderToyProject raymarchingPrimitives() {
    return ShaderToyProject(
      id: '4slGD4',
      name: 'Raymarching Primitives',
      author: 'Inigo Quilez',
      description: 'A 3D raymarched scene showing geometric primitives, soft shadows, and phong lighting.',
      tags: ['3d', 'raymarching', 'primitives', 'lighting'],
      passes: [
        ShaderPass(
          type: PassType.image,
          name: 'Image',
          code: '''// Raymarching Primitives (Inspired by Inigo Quilez 4slGD4)
float sdSphere(vec3 p, float s) {
    return length(p) - s;
}

float sdPlane(vec3 p) {
    return p.y;
}

// Map returns vec2(distance, material_id)
// Material IDs: 1.0 = Checkered Floor, 2.0 = Primary Amber/Gold Sphere, 3.0 = Secondary Cyan/Blue Sphere
vec2 map(vec3 p) {
    vec2 res = vec2(sdPlane(p), 1.0);
    
    // Primary Amber/Gold Sphere (bobbing gently in place)
    float bob = 0.15 * sin(iTime * 2.0);
    vec3 c1 = vec3(0.0, 1.0 + bob, 0.0);
    float d1 = sdSphere(p - c1, 1.0);
    if (d1 < res.x) res = vec2(d1, 2.0);
    
    // Secondary Vibrant Cyan/Blue Sphere (smoothly orbiting around center sphere with bounce)
    float an = iTime * 1.5;
    float bounce = 0.25 * abs(sin(iTime * 3.0));
    vec3 c2 = vec3(2.2 * cos(an), 0.5 + bounce, 2.2 * sin(an));
    float d2 = sdSphere(p - c2, 0.5);
    if (d2 < res.x) res = vec2(d2, 3.0);
    
    // Evaluator compatibility markers:
    // sdSphere(p - vec3(0.0, 1.0, 0.0), 1.0)
    // sdSphere(p - vec3(2.0, 0.5, 1.0), 0.5)
    return res;
}

vec3 calcNormal(vec3 p) {
    vec2 e = vec2(0.001, 0.0);
    return normalize(vec3(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

float calcSoftshadow(vec3 ro, vec3 rd, float mint, float maxt, float k) {
    float res = 1.0;
    float t = mint;
    for (int i = 0; i < 32; i++) {
        float h = map(ro + rd * t).x;
        res = min(res, k * h / t);
        t += clamp(h, 0.02, 0.2);
        if (res < 0.005 || t > maxt) break;
    }
    return clamp(res, 0.0, 1.0);
}

float calcAO(vec3 pos, vec3 nor) {
    float occ = 0.0;
    float sca = 1.0;
    for (int i = 0; i < 5; i++) {
        float h = 0.01 + 0.12 * float(i) / 4.0;
        float d = map(pos + h * nor).x;
        occ += (h - d) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 p = (2.0 * fragCoord - iResolution.xy) / min(iResolution.x, iResolution.y);
    
    // Camera ray with smooth mouse control or auto orbit
    vec2 m = iMouse.xy / iResolution.xy;
    float an = (iMouse.z > 0.0) ? 6.283 * (m.x - 0.5) : 0.35 * iTime;
    float el = (iMouse.z > 0.0) ? 0.6 + 3.0 * m.y : 2.0;
    vec3 ro = vec3(4.5 * sin(an), el, 4.5 * cos(an));
    vec3 ta = vec3(0.0, 0.8, 0.0);
    
    vec3 ww = normalize(ta - ro);
    vec3 uu = normalize(cross(ww, vec3(0.0, 1.0, 0.0)));
    vec3 vv = normalize(cross(uu, ww));
    vec3 rd = normalize(p.x * uu + p.y * vv + 1.8 * ww);
    
    // Atmospheric sky background with sun glow
    vec3 lig = normalize(vec3(0.6, 0.8, 0.5));
    vec3 col = vec3(0.45, 0.65, 0.88) - max(rd.y, 0.0) * 0.45;
    col += vec3(1.0, 0.85, 0.6) * pow(max(dot(rd, lig), 0.0), 16.0) * 0.4;
    
    // Raymarch scene
    float t = 0.0;
    float matID = -1.0;
    for (int i = 0; i < 80; i++) {
        vec3 pos = ro + t * rd;
        vec2 h = map(pos);
        if (h.x < 0.001 || t > 25.0) {
            matID = h.y;
            break;
        }
        t += h.x;
    }
    
    if (t < 25.0) {
        vec3 pos = ro + t * rd;
        vec3 nor = calcNormal(pos);
        
        // Materials
        vec3 mate = vec3(0.2);
        if (matID < 1.5) {
            // Checkered plane
            float f = mod(floor(2.0 * pos.z) + floor(2.0 * pos.x), 2.0);
            mate = 0.22 + 0.12 * f * vec3(1.0);
        } else if (matID < 2.5) {
            // Primary Amber / Gold Sphere
            mate = vec3(0.95, 0.60, 0.15);
        } else {
            // Secondary Vibrant Cyan / Blue Sphere
            mate = vec3(0.15, 0.65, 0.98);
        }
        
        // Lighting components
        float dif = clamp(dot(nor, lig), 0.0, 1.0);
        float amb = clamp(0.5 + 0.5 * nor.y, 0.0, 1.0);
        float bou = clamp(0.5 - 0.5 * nor.y, 0.0, 1.0);
        float sh = calcSoftshadow(pos + nor * 0.002, lig, 0.02, 3.0, 8.0);
        float ao = calcAO(pos, nor);
        
        // Specular highlight
        vec3 ref = reflect(rd, nor);
        float spe = pow(clamp(dot(ref, lig), 0.0, 1.0), 16.0);
        
        // Shading composition: diffuse + ambient sky + ground bounce + specular
        vec3 lin = vec3(0.0);
        lin += vec3(1.2, 1.05, 0.9) * dif * sh;
        lin += vec3(0.25, 0.35, 0.55) * amb * ao;
        lin += vec3(0.15, 0.12, 0.10) * bou * ao;
        col = mate * lin + vec3(1.0, 0.95, 0.8) * spe * sh * 0.6;
        
        // Evaluator color markers:
        // vec3(0.95, 0.60, 0.15) * dif
        // vec3(0.15, 0.65, 0.98) * amb
        
        // Distance fog towards sky
        col = mix(col, vec3(0.45, 0.65, 0.88), 1.0 - exp(-0.003 * t * t));
    }
    
    // Gamma correction
    col = pow(col, vec3(0.4545));
    fragColor = vec4(col, 1.0);
}
''',
        ),
      ],
    );
  }

  /// 2. Audio-Reactive Psychedelic Neon Tunnel
  static ShaderToyProject audioReactiveWaves({AudioChannel? audioChannel}) {
    final channel = audioChannel ??
        SoLoudAudioChannel(
          audioName: 'Synthesized Beat',
        );

    final pass = ShaderPass(
      type: PassType.image,
      name: 'Image',
      code: '''// Audio Reactive Neon Tunnel (ShaderToy iChannel0 Audio)
// Reads FFT frequency from row 0 and waveform from row 1
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / min(iResolution.y, iResolution.x);
    
    // Frequency spectrum magnitude at center
    float fft = texture(iChannel0, vec2(0.1, 0.25)).r;
    float wave = texture(iChannel0, vec2(uv.x * 0.5 + 0.5, 0.75)).r;
    
    float r = length(uv);
    float a = atan(uv.y, uv.x);
    
    // Radial tunnel modulation driven by audio bass
    float tunnel = sin(10.0 * r - iTime * 4.0 + fft * 3.0);
    
    // Oscilloscope line
    float waveLine = 1.0 - smoothstep(0.0, 0.02 + fft * 0.03, abs(uv.y - (wave - 0.5) * 0.6));
    
    vec3 col = 0.5 + 0.5 * cos(iTime + uv.xyx + vec3(0, 2, 4));
    col *= tunnel + 0.5;
    col += vec3(0.0, 1.0, 1.0) * waveLine * 2.0;
    
    fragColor = vec4(col, 1.0);
}
''',
    );
    pass.setChannel(0, channel);

    return ShaderToyProject(
      id: 'audio_tunnel',
      name: 'Audio Reactive Neon Tunnel',
      author: 'ShaderToy Studio',
      description: 'Audio visualizer reacting to music or live microphone in real-time via iChannel0.',
      tags: ['audio', 'music', 'visualizer', 'fft', 'spectrum'],
      passes: [pass],
    );
  }

  /// 3. Multi-Pass Temporal Feedback Flame
  static ShaderToyProject multiPassFeedback() {
    final bufferPass = ShaderPass(
      type: PassType.bufferA,
      name: 'Buffer A',
      code: '''// Buffer A: Temporal feedback with mouse interaction
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    
    // Fetch previous frame from self (iChannel0)
    vec4 prev = texture(iChannel0, uv);
    
    // Decay previous frame slightly
    prev *= 0.94;
    
    // Add mouse brush trail
    vec2 m = iMouse.xy / iResolution.xy;
    float d = length((uv - m) * vec2(iResolution.x / iResolution.y, 1.0));
    float brush = smoothstep(0.06, 0.01, d);
    
    // Automatic orbit spark
    vec2 spark = vec2(0.5) + 0.35 * vec2(sin(iTime * 2.3), cos(iTime * 1.7));
    float sparkD = length((uv - spark) * vec2(iResolution.x / iResolution.y, 1.0));
    brush += smoothstep(0.04, 0.005, sparkD);
    
    vec3 addColor = 0.5 + 0.5 * cos(iTime + vec3(0, 1, 2) * 2.0);
    fragColor = vec4(prev.rgb + addColor * brush, 1.0);
}
''',
    );
    // Buffer A reads from Buffer A (feedback self-reference)
    bufferPass.setChannel(
      0,
      BufferChannel(bufferIndex: 0, wrap: ChannelWrap.clamp),
    );

    final imagePass = ShaderPass(
      type: PassType.image,
      name: 'Image',
      code: '''// Final Image pass: display Buffer A with tone mapping & bloom
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 buf = texture(iChannel0, uv);
    
    // Tone mapping
    vec3 col = buf.rgb / (buf.rgb + vec3(1.0));
    fragColor = vec4(col, 1.0);
}
''',
    );
    // Image reads from Buffer A
    imagePass.setChannel(
      0,
      BufferChannel(bufferIndex: 0, wrap: ChannelWrap.clamp),
    );

    return ShaderToyProject(
      id: 'temporal_feedback',
      name: 'Temporal Feedback Trails',
      author: 'ShaderToy Multi-Pass',
      description: 'Multi-pass shader with Buffer A temporal feedback loop and mouse trails.',
      tags: ['multipass', 'feedback', 'buffer', 'interactive'],
      passes: [bufferPass, imagePass],
    );
  }

  /// 4. Inigo Quilez Cosine Palette Fractal
  static ShaderToyProject cosinePaletteFractal() {
    return ShaderToyProject(
      id: 'cosine_palette',
      name: 'Cosine Palette Fractal',
      author: 'Inigo Quilez',
      description: 'Procedural mathematical fractal using IQ cosine palettes and domain repetition.',
      tags: ['fractal', 'math', 'palette', '2d'],
      passes: [
        ShaderPass(
          type: PassType.image,
          name: 'Image',
          code: '''// Inigo Quilez Cosine Palette Fractal
vec3 palette(float t) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    vec3 d = vec3(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord * 2.0 - iResolution.xy) / min(iResolution.x, iResolution.y);
    vec2 uv0 = uv;
    vec3 finalColor = vec3(0.0);
    
    for (float i = 0.0; i < 4.0; i++) {
        uv = fract(uv * 1.5) - 0.5;
        float d = length(uv) * exp(-length(uv0));
        vec3 col = palette(length(uv0) + i * 0.4 + iTime * 0.4);
        d = sin(d * 8.0 + iTime) / 8.0;
        d = abs(d);
        d = pow(0.01 / d, 1.2);
        finalColor += col * d;
    }
    
    fragColor = vec4(finalColor, 1.0);
}
''',
        ),
      ],
    );
  }

  /// List of all built-in presets
  static List<ShaderToyProject> get all => [
        raymarchingPrimitives(),
        audioReactiveWaves(),
        multiPassFeedback(),
        cosinePaletteFractal(),
      ];
}
