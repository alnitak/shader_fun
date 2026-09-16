import 'dart:math' as math;
import 'dart:ui' as ui;

import '../channels/audio_texture_provider.dart';
import '../core/shader_pass.dart';
import '../core/common_uniforms.dart';
import 'shader_code_evaluator.dart';

/// Canvas-based compositor renderer for multi-pass simulation and fallback rendering.
class CompositorRenderer {
  CompositorRenderer({this.width = 800, this.height = 450});

  int width;
  int height;

  final Map<int, ui.Image> _bufferTextures = {};

  void resize(int newWidth, int newHeight) {
    if (newWidth <= 0 || newHeight <= 0) return;
    width = newWidth;
    height = newHeight;
    _bufferTextures.clear();
  }

  /// Renders a frame using the Canvas compositor.
  Future<ui.Image> renderFrame({
    required CommonUniforms uniforms,
    required List<ShaderPass> passes,
    AudioChannel? activeAudioChannel,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    // Dark canvas background
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF0F0F12),
    );

    // Find active Image pass and Buffer passes
    final imagePass = passes.firstWhere(
      (p) => p.type == PassType.image && p.enabled,
      orElse: () => ShaderPass(type: PassType.image, name: 'Image', code: ''),
    );

    // Determine what effect to render based on the active shader preset
    await _renderProceduralShader(
      canvas: canvas,
      size: ui.Size(width.toDouble(), height.toDouble()),
      uniforms: uniforms,
      pass: imagePass,
      audio: activeAudioChannel,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    return image;
  }

  /// Renders visually rich procedural visuals matching the active shader.
  Future<void> _renderProceduralShader({
    required ui.Canvas canvas,
    required ui.Size size,
    required CommonUniforms uniforms,
    required ShaderPass pass,
    AudioChannel? audio,
  }) async {
    final code = pass.code;
    final lower = code.toLowerCase();

    // 1. Check for direct constant color assignment (e.g. fragColor = vec4(1.0, 0.0, 0.0, 1.0);)
    final directColor = ShaderCodeEvaluator.extractDirectFragColor(code);
    if (directColor != null) {
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, size.width, size.height),
        ui.Paint()..color = directColor,
      );
      return;
    }

    final isPresetRaymarching =
        pass.name == 'Raymarching Primitives' ||
        (lower.contains('sdsphere') && lower.contains('sdplane'));

    final isPresetAudio =
        pass.name == 'Audio Visualizer' ||
        pass.name == 'Audio Reactive Waves' ||
        lower.contains('createtunnel');

    final isPresetFeedback =
        pass.name == 'Feedback Trails' || lower.contains('feedbackpass');

    final isPresetCosine =
        pass.name == 'Cosine Fractal' ||
        (lower.contains('palette') && lower.contains('exp(-d0)'));

    if (isPresetRaymarching) {
      _renderRaymarchingPrimitives(canvas, size, uniforms, code);
    } else if (isPresetAudio) {
      _renderAudioVisualizer(canvas, size, uniforms, audio, code);
    } else if (isPresetFeedback) {
      _renderFeedbackTrails(canvas, size, uniforms, code);
    } else if (isPresetCosine) {
      _renderCosineFractal(canvas, size, uniforms, code);
    } else {
      _renderOfflineFallbackNotice(canvas, size);
    }
  }

  /// Renders a notice when custom shader code is loaded but Flutter GPU is offline.
  void _renderOfflineFallbackNotice(ui.Canvas canvas, ui.Size size) {
    final bgPaint = ui.Paint()..color = const ui.Color(0xFF0F0F14);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final gridPaint = ui.Paint()
      ..color = const ui.Color(0x18FFFFFF)
      ..strokeWidth = 1.0;
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(ui.Offset(x, 0), ui.Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(ui.Offset(0, y), ui.Offset(size.width, y), gridPaint);
    }

    final pb = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        fontSize: 15,
        fontWeight: ui.FontWeight.w600,
      ),
    );
    pb.pushStyle(ui.TextStyle(color: const ui.Color(0xFFFF8844)));
    pb.addText('Flutter GPU Offline\n');
    pb.pushStyle(
      ui.TextStyle(
        color: const ui.Color(0xFF94A3B8),
        fontSize: 12,
        fontWeight: ui.FontWeight.normal,
      ),
    );
    pb.addText(
      'Custom compiled GLSL requires the Impeller rendering backend.\n'
      'Restart the app with Impeller enabled to execute shaders on the GPU.',
    );
    final paragraph = pb.build()
      ..layout(ui.ParagraphConstraints(width: size.width - 40));
    canvas.drawParagraph(
      paragraph,
      ui.Offset(20, (size.height - paragraph.height) / 2),
    );
  }

  /// 1. Raymarching Primitives (Inigo Quilez 4slGD4 style)
  void _renderRaymarchingPrimitives(
    ui.Canvas canvas,
    ui.Size size,
    CommonUniforms uniforms,
    String code,
  ) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2.0;
    final cy = h / 2.0;

    final config = ShaderCodeEvaluator.parseRaymarchingConfig(code);
    final t = uniforms.time * (config.rotationSpeed / 0.5);

    // Mouse influence on camera
    final mx = (uniforms.mouse.x / w - 0.5) * 2.0;
    final my = (uniforms.mouse.y / h - 0.5) * 2.0;

    // Horizon sky gradient
    final skyPaint = ui.Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset.zero,
        ui.Offset(0, h),
        [
          const ui.Color(0xFF181E2E),
          const ui.Color(0xFF2C3E55),
          const ui.Color(0xFFD48248),
          const ui.Color(0xFF1E1714),
        ],
        [0.0, 0.45, 0.55, 1.0],
      );
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, w, h), skyPaint);

    // Perspective Ground Grid (like ShaderToy primitives plane)
    final horizonY = cy + my * 40.0;
    final groundPaint = ui.Paint()
      ..color = const ui.Color(0x33446688)
      ..strokeWidth = 1.0;

    for (int i = -10; i <= 10; i++) {
      final startX = cx + i * (w / 10.0) * 0.15;
      final endX = cx + i * (w / 8.0) * 1.6 + mx * 50.0;
      canvas.drawLine(
        ui.Offset(startX, horizonY),
        ui.Offset(endX, h),
        groundPaint,
      );
    }
    for (double y = horizonY + 5; y < h; y += (y - horizonY) * 0.25 + 3.0) {
      canvas.drawLine(ui.Offset(0, y), ui.Offset(w, y), groundPaint);
    }

    // Render spheres dynamically extracted from sdSphere in code
    final baseRadius = math.min(w, h) * 0.16;

    for (int i = 0; i < config.spheres.length; i++) {
      final sphere = config.spheres[i];
      final sphereRadius = (baseRadius * sphere.radius).clamp(
        5.0,
        math.min(w, h) * 0.5,
      );
      final isPrimary = i == 0;

      final sphereCenter = isPrimary
          ? ui.Offset(
              cx +
                  mx * 80.0 +
                  math.sin(t * 1.5) * 40.0 +
                  sphere.center.dx * 30.0,
              cy -
                  20.0 +
                  my * 60.0 +
                  math.sin(t * 2.0) * 15.0 -
                  (sphere.center.dy - 1.0) * 40.0,
            )
          : ui.Offset(
              cx +
                  (sphere.center.dx * 70.0) +
                  math.cos(t * 2.5 + i) * (sphereRadius * 1.5),
              cy +
                  (sphere.center.dy * 20.0) +
                  math.sin(t * 2.5 + i) * (sphereRadius * 0.8),
            );

      // Shadow on plane
      final shadowPaint = ui.Paint()
        ..color = const ui.Color(0x77000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 12);
      canvas.drawOval(
        ui.Rect.fromCenter(
          center: ui.Offset(sphereCenter.dx, horizonY + (h - horizonY) * 0.3),
          width: sphereRadius * 2.2,
          height: sphereRadius * 0.5,
        ),
        shadowPaint,
      );

      // Sphere Body with 3D Light gradient using parsed diffuse and ambient colors
      final lightPos = ui.Offset(
        sphereCenter.dx - sphereRadius * 0.4,
        sphereCenter.dy - sphereRadius * 0.4,
      );
      final sphereColor = isPrimary ? config.diffuseColor : config.ambientColor;
      final spherePaint = ui.Paint()
        ..shader = ui.Gradient.radial(
          lightPos,
          sphereRadius * 1.3,
          [
            const ui.Color(0xFFFFEEAA), // Specular highlight
            sphereColor, // Dynamic diffuse color from GLSL code
            ui.Color.fromARGB(
              255,
              (sphereColor.r * 255.0 * 0.6).round(),
              (sphereColor.g * 255.0 * 0.6).round(),
              (sphereColor.b * 255.0 * 0.6).round(),
            ),
            const ui.Color(0xFF1A0005), // Ambient occlusion
          ],
          [0.0, 0.35, 0.75, 1.0],
        );
      canvas.drawCircle(sphereCenter, sphereRadius, spherePaint);
    }
  }

  /// 2. Audio-Reactive Psychedelic Neon Tunnel
  void _renderAudioVisualizer(
    ui.Canvas canvas,
    ui.Size size,
    CommonUniforms uniforms,
    AudioChannel? audio,
    String code,
  ) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2.0;
    final cy = h / 2.0;

    final config = ShaderCodeEvaluator.parseAudioTunnelConfig(code);
    final t = uniforms.time * (config.tunnelSpeed / 4.0);

    final fft = audio?.fftData;
    final wave = audio?.waveData;

    // Background cosmic vortex with dynamic colors from code
    final bgPaint = ui.Paint()
      ..shader = ui.Gradient.radial(ui.Offset(cx, cy), math.max(w, h) * 0.7, [
        ui.Color.fromARGB(
          255,
          (30 + math.sin(t + config.palettePhaseR) * 20).toInt().clamp(0, 255),
          (math.cos(t + config.palettePhaseG) * 15).abs().toInt().clamp(0, 255),
          (40 + math.sin(t + config.palettePhaseB) * 25).toInt().clamp(0, 255),
        ),
        const ui.Color(0xFF08060D),
      ]);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, w, h), bgPaint);

    // Audio reactive rings driven by parsed tunnel frequency and bass
    final ringCount = (config.tunnelFrequency * 2.8).round().clamp(8, 60);
    for (int r = 0; r < ringCount; r++) {
      final normR = r / ringCount;
      final freqIdx = (normR * 255.0).toInt().clamp(0, 511);
      final rawFft = (fft != null && freqIdx < fft.length)
          ? fft[freqIdx]
          : (math.exp(-normR * 5.0) * (0.5 + 0.5 * math.sin(t * 8.0 + r)));
      final fftMag = rawFft * (config.fftMultiplier / 3.0);

      final radius = (normR * math.max(w, h) * 0.55) + fftMag * 60.0;
      final hue = (normR * 360.0 + t * 40.0) % 360.0;
      final color = _hslToColor(hue, 0.9, 0.6);

      final ringPaint = ui.Paint()
        ..color = color.withValues(alpha: (0.8 - normR * 0.5).clamp(0.1, 0.9))
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (2.0 + fftMag * 10.0).clamp(1.0, 30.0);

      canvas.drawCircle(ui.Offset(cx, cy), radius, ringPaint);
    }

    // Waveform Oscilloscope across center
    final wavePath = ui.Path();
    final pointCount = 128;
    for (int i = 0; i < pointCount; i++) {
      final px = (i / (pointCount - 1)) * w;
      final sampleIdx = ((i / pointCount) * 512).toInt().clamp(0, 511);
      final amp = (wave != null && sampleIdx < wave.length)
          ? (wave[sampleIdx] - 0.5) * (config.waveAmplitudeMultiplier * 3.3)
          : math.sin(i * 0.2 + t * 10.0) *
                (config.waveAmplitudeMultiplier * 0.6);
      final py = cy + amp * 120.0;

      if (i == 0) {
        wavePath.moveTo(px, py);
      } else {
        wavePath.lineTo(px, py);
      }
    }

    // Wave line colors dynamically extracted from GLSL code
    final waveGlowPaint = ui.Paint()
      ..color = config.waveLineColor.withValues(alpha: 0.8)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = (4.0 * (config.waveIntensity / 2.0)).clamp(1.0, 20.0)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    canvas.drawPath(wavePath, waveGlowPaint);

    final waveCorePaint = ui.Paint()
      ..color = config.waveLineColor == const ui.Color(0xFF00FFFF)
          ? const ui.Color(0xFFFFFFFF)
          : config.waveLineColor
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = (2.0 * (config.waveIntensity / 2.0)).clamp(0.5, 10.0);
    canvas.drawPath(wavePath, waveCorePaint);
  }

  /// 3. Multi-Pass Temporal Feedback Flame / Smoke
  void _renderFeedbackTrails(
    ui.Canvas canvas,
    ui.Size size,
    CommonUniforms uniforms,
    String code,
  ) {
    final w = size.width;
    final h = size.height;

    final speedMatch = RegExp(r'([0-9.]+)\s*\*\s*iTime').firstMatch(code);
    final speed = speedMatch != null
        ? (double.tryParse(speedMatch.group(1)!) ?? 1.8)
        : 1.8;
    final t = uniforms.time * speed;

    final colors = ShaderCodeEvaluator.extractVec3Colors(code);
    final primaryColor = colors.isNotEmpty ? colors.first : null;

    final trailPaint = ui.Paint()..style = ui.PaintingStyle.fill;

    // Glowing particles moving in Lissajous curves
    for (int p = 0; p < 18; p++) {
      final pt = t + p * 0.35;
      final px = (w * 0.5) + math.sin(pt * 1.2) * (w * 0.35);
      final py = (h * 0.5) + math.cos(pt * 1.9) * (h * 0.3);

      final hue = (p * 20.0 + t * 30.0) % 360.0;
      final col = primaryColor ?? _hslToColor(hue, 1.0, 0.55);

      trailPaint.shader = ui.Gradient.radial(ui.Offset(px, py), 55.0, [
        col,
        col.withValues(alpha: 0.0),
      ]);
      canvas.drawCircle(ui.Offset(px, py), 55.0, trailPaint);
    }

    // Mouse dynamic trail
    if (uniforms.mouse.z > 0 || uniforms.mouse.x > 0) {
      final mPaint = ui.Paint()
        ..shader = ui.Gradient.radial(
          ui.Offset(uniforms.mouse.x, uniforms.mouse.y),
          70.0,
          [const ui.Color(0xFFFF0055), const ui.Color(0x00FF0055)],
        );
      canvas.drawCircle(
        ui.Offset(uniforms.mouse.x, uniforms.mouse.y),
        70.0,
        mPaint,
      );
    }
  }

  /// 4. Inigo Quilez Cosine Palette Fractal
  void _renderCosineFractal(
    ui.Canvas canvas,
    ui.Size size,
    CommonUniforms uniforms,
    String code,
  ) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2.0;
    final cy = h / 2.0;

    final speedMatch = RegExp(r'([0-9.]+)\s*\*\s*iTime').firstMatch(code);
    final speed = speedMatch != null
        ? (double.tryParse(speedMatch.group(1)!) ?? 0.8)
        : 0.8;
    final t = uniforms.time * speed;

    final colors = ShaderCodeEvaluator.extractVec3Colors(code);
    final tint = colors.isNotEmpty ? colors.first : const ui.Color(0xFF4ADE80);

    for (int i = 0; i < 30; i++) {
      final norm = i / 30.0;
      final angle = t + norm * math.pi * 4.0;
      final dist = (norm * math.min(w, h) * 0.48);

      final px = cx + math.cos(angle) * dist;
      final py = cy + math.sin(angle) * dist;

      // Inigo Quilez palette formula
      final r = (0.5 + 0.5 * math.cos(6.28318 * (norm * 1.0 + t * 0.2))).clamp(
        0.0,
        1.0,
      );
      final g = (0.5 + 0.5 * math.cos(6.28318 * (norm * 1.0 + t * 0.2 + 0.33)))
          .clamp(0.0, 1.0);
      final b = (0.5 + 0.5 * math.cos(6.28318 * (norm * 1.0 + t * 0.2 + 0.67)))
          .clamp(0.0, 1.0);

      final paint = ui.Paint()
        ..color = ui.Color.fromARGB(
          200,
          ((r * tint.r) * 255).round().clamp(0, 255),
          ((g * tint.g) * 255).round().clamp(0, 255),
          ((b * tint.b) * 255).round().clamp(0, 255),
        )
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);

      canvas.drawCircle(ui.Offset(px, py), 12.0 + norm * 18.0, paint);
    }
  }

  static ui.Color _hslToColor(double h, double s, double l) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = l - c / 2;

    double r = 0, g = 0, b = 0;
    if (h < 60) {
      r = c;
      g = x;
    } else if (h < 120) {
      r = x;
      g = c;
    } else if (h < 180) {
      g = c;
      b = x;
    } else if (h < 240) {
      g = x;
      b = c;
    } else if (h < 300) {
      r = x;
      b = c;
    } else {
      r = c;
      b = x;
    }

    return ui.Color.fromARGB(
      255,
      ((r + m) * 255).round(),
      ((g + m) * 255).round(),
      ((b + m) * 255).round(),
    );
  }

  void dispose() {
    _bufferTextures.clear();
  }
}
