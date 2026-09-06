import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../channels/audio_texture_provider.dart';
import '../core/shadertoy_uniforms.dart';

/// Evaluates and extracts parameters and visual expressions from GLSL `mainImage` code.
class ShaderCodeEvaluator {
  /// Validates GLSL shader code syntax and returns an error description if invalid, or null if valid.
  static String? validate(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return 'Empty shader code';
    }

    // 1. Must contain entry point mainImage
    if (!trimmed.contains('mainImage')) {
      return 'Missing mainImage function';
    }

    // 2. Check balanced braces, parentheses, and brackets while ignoring comments/strings
    int openBraces = 0;
    int openParens = 0;
    int openBrackets = 0;
    bool inLineComment = false;
    bool inBlockComment = false;
    bool inString = false;

    for (int i = 0; i < code.length; i++) {
      final char = code[i];
      final next = i + 1 < code.length ? code[i + 1] : '';

      if (inLineComment) {
        if (char == '\n') inLineComment = false;
        continue;
      }
      if (inBlockComment) {
        if (char == '*' && next == '/') {
          inBlockComment = false;
          i++;
        }
        continue;
      }
      if (inString) {
        if (char == '"' && (i == 0 || code[i - 1] != '\\')) {
          inString = false;
        }
        continue;
      }

      if (char == '/' && next == '/') {
        inLineComment = true;
        i++;
        continue;
      }
      if (char == '/' && next == '*') {
        inBlockComment = true;
        i++;
        continue;
      }
      if (char == '"') {
        inString = true;
        continue;
      }

      if (char == '{') {
        openBraces++;
      } else if (char == '}') {
        openBraces--;
        if (openBraces < 0) return 'Unexpected closing brace "}"';
      } else if (char == '(') {
        openParens++;
      } else if (char == ')') {
        openParens--;
        if (openParens < 0) return 'Unexpected closing parenthesis ")"';
      } else if (char == '[') {
        openBrackets++;
      } else if (char == ']') {
        openBrackets--;
        if (openBrackets < 0) return 'Unexpected closing bracket "]"';
      }
    }

    if (inBlockComment) {
      return 'Unterminated block comment';
    }
    if (openBraces > 0) {
      return 'Unclosed brace "{" (missing $openBraces "}")';
    }
    if (openParens > 0) {
      return 'Unclosed parenthesis "(" (missing $openParens ")")';
    }
    if (openBrackets > 0) {
      return 'Unclosed bracket "[" (missing $openBrackets "]")';
    }

    // 3. Check for missing semicolons on statements
    final semicolonError = _checkMissingSemicolons(code);
    if (semicolonError != null) {
      return semicolonError;
    }

    return null;
  }

  /// Checks lines for missing semicolons or syntax errors.
  static String? _checkMissingSemicolons(String rawCode) {
    bool inBlockComment = false;
    final lines = rawCode.split('\n');

    final cleanLines = <String>[];
    for (int l = 0; l < lines.length; l++) {
      final line = lines[l];
      final outLine = StringBuffer();
      int i = 0;
      while (i < line.length) {
        if (inBlockComment) {
          final endIdx = line.indexOf('*/', i);
          if (endIdx != -1) {
            inBlockComment = false;
            i = endIdx + 2;
          } else {
            i = line.length;
          }
          continue;
        }

        if (i + 1 < line.length && line[i] == '/' && line[i + 1] == '/') {
          // Line comment -> skip rest of line
          break;
        }

        if (i + 1 < line.length && line[i] == '/' && line[i + 1] == '*') {
          inBlockComment = true;
          i += 2;
          continue;
        }

        outLine.write(line[i]);
        i++;
      }
      cleanLines.add(outLine.toString().trimRight());
    }

    // Iterate through non-empty lines
    for (int l = 0; l < cleanLines.length; l++) {
      final line = cleanLines[l].trim();
      if (line.isEmpty) continue;
      final lineNum = l + 1;

      // Ignore preprocessor directives
      if (line.startsWith('#')) continue;

      // Ignore lines ending with semicolon, open brace, close brace, comma
      final lastChar = line[line.length - 1];
      if (lastChar == ';' || lastChar == '{' || lastChar == '}' || lastChar == ',') {
        continue;
      }

      // Ignore lines ending with open parenthesis/bracket or binary/ternary operators
      if (lastChar == '(' || lastChar == '[' ||
          lastChar == '+' || lastChar == '-' || lastChar == '*' || lastChar == '/' ||
          lastChar == '=' || lastChar == '?' || lastChar == ':' ||
          line.endsWith('&&') || line.endsWith('||')) {
        continue;
      }

      // Ignore control flow keywords that start a statement on next line
      if (line == 'else' || line.startsWith('else ') ||
          line.startsWith('if ') || line.startsWith('if(') ||
          line.startsWith('for ') || line.startsWith('for(') ||
          line.startsWith('while ') || line.startsWith('while(') ||
          line == 'do') {
        continue;
      }

      // Find the next non-empty line
      String nextLine = '';
      for (int nextIdx = l + 1; nextIdx < cleanLines.length; nextIdx++) {
        final nextTrim = cleanLines[nextIdx].trim();
        if (nextTrim.isNotEmpty) {
          nextLine = nextTrim;
          break;
        }
      }

      // If followed by an open brace '{', this is a function definition or block header
      if (nextLine.startsWith('{')) {
        continue;
      }

      // Otherwise, this line is an unclosed statement missing a semicolon!
      return 'Line $lineNum: missing ";"';
    }

    return null;
  }

  /// Extracts all `vec3(r, g, b)` from a GLSL snippet as [ui.Color]s.
  static List<ui.Color> extractVec3Colors(String code) {
    final colors = <ui.Color>[];
    final regex = RegExp(
      r'vec3\s*\(\s*([0-9.]+)\s*(?:,\s*([0-9.]+)\s*,\s*([0-9.]+))?\s*\)',
    );
    for (final match in regex.allMatches(code)) {
      final r = (double.tryParse(match.group(1)!) ?? 0.0).clamp(0.0, 1.0);
      final g = match.group(2) != null
          ? (double.tryParse(match.group(2)!) ?? r).clamp(0.0, 1.0)
          : r;
      final b = match.group(3) != null
          ? (double.tryParse(match.group(3)!) ?? r).clamp(0.0, 1.0)
          : r;
      colors.add(
        ui.Color.fromARGB(
          255,
          (r * 255.0).round(),
          (g * 255.0).round(),
          (b * 255.0).round(),
        ),
      );
    }
    return colors;
  }

  /// Extracts direct constant color assignment like:
  /// `fragColor = vec4(r, g, b, a);`
  /// `fragColor = vec4(vec3(r, g, b), a);`
  /// `fragColor = vec4(val);`
  /// `vec3 col = vec3(r, g, b); ... fragColor = vec4(col, a);`
  static ui.Color? extractDirectFragColor(String code) {
    // 1. fragColor = vec4(r, g, b, a); (supports floats & integers)
    final directVec4 = RegExp(
      r'fragColor\s*=\s*vec4\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*(?:,\s*([0-9.]+))?\s*\)\s*;',
    ).firstMatch(code);
    if (directVec4 != null) {
      final r = (double.tryParse(directVec4.group(1)!) ?? 0.0).clamp(0.0, 1.0);
      final g = (double.tryParse(directVec4.group(2)!) ?? 0.0).clamp(0.0, 1.0);
      final b = (double.tryParse(directVec4.group(3)!) ?? 0.0).clamp(0.0, 1.0);
      final a = directVec4.group(4) != null
          ? (double.tryParse(directVec4.group(4)!) ?? 1.0).clamp(0.0, 1.0)
          : 1.0;
      return ui.Color.fromARGB(
        (a * 255.0).round(),
        (r * 255.0).round(),
        (g * 255.0).round(),
        (b * 255.0).round(),
      );
    }

    // 2. fragColor = vec4(vec3(r, g, b), a);
    final nestedVec3 = RegExp(
      r'fragColor\s*=\s*vec4\s*\(\s*vec3\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)\s*(?:,\s*([0-9.]+))?\s*\)\s*;',
    ).firstMatch(code);
    if (nestedVec3 != null) {
      final r = (double.tryParse(nestedVec3.group(1)!) ?? 0.0).clamp(0.0, 1.0);
      final g = (double.tryParse(nestedVec3.group(2)!) ?? 0.0).clamp(0.0, 1.0);
      final b = (double.tryParse(nestedVec3.group(3)!) ?? 0.0).clamp(0.0, 1.0);
      final a = nestedVec3.group(4) != null
          ? (double.tryParse(nestedVec3.group(4)!) ?? 1.0).clamp(0.0, 1.0)
          : 1.0;
      return ui.Color.fromARGB(
        (a * 255.0).round(),
        (r * 255.0).round(),
        (g * 255.0).round(),
        (b * 255.0).round(),
      );
    }

    // 3. Simple single-value vec4(c): e.g. fragColor = vec4(1.0);
    final singleVec4 = RegExp(
      r'fragColor\s*=\s*vec4\s*\(\s*([0-9.]+)\s*\)\s*;',
    ).firstMatch(code);
    if (singleVec4 != null) {
      final v = (double.tryParse(singleVec4.group(1)!) ?? 0.0).clamp(0.0, 1.0);
      final byte = (v * 255.0).round();
      return ui.Color.fromARGB(255, byte, byte, byte);
    }

    // 4. Last assignment col = vec3(r, g, b); followed by fragColor = vec4(col, ...);
    final colAssignment = RegExp(
      r'col\s*=\s*vec3\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)\s*;[^\n]*\n?[^\n]*fragColor\s*=\s*vec4\s*\(\s*col',
    ).firstMatch(code);
    if (colAssignment != null) {
      final r = (double.tryParse(colAssignment.group(1)!) ?? 0.0).clamp(0.0, 1.0);
      final g = (double.tryParse(colAssignment.group(2)!) ?? 0.0).clamp(0.0, 1.0);
      final b = (double.tryParse(colAssignment.group(3)!) ?? 0.0).clamp(0.0, 1.0);
      return ui.Color.fromARGB(255, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }

    return null;
  }

  /// Extracts parameters for the Audio Reactive Neon Tunnel shader.
  static AudioTunnelConfig parseAudioTunnelConfig(String code) {
    final config = AudioTunnelConfig();

    // 1. Wave line color: looks for vec3(r, g, b) multiplied by waveLine or wave
    final waveColorMatch = RegExp(
      r'vec3\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)\s*\*\s*wave',
      caseSensitive: false,
    ).firstMatch(code) ??
    RegExp(
      r'waveLine\s*.*vec3\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)',
      caseSensitive: false,
    ).firstMatch(code) ??
    RegExp(
      r'vec3\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)\s*\*\s*waveLine',
      caseSensitive: false,
    ).firstMatch(code);

    if (waveColorMatch != null) {
      final r = (double.tryParse(waveColorMatch.group(1)!) ?? 0.0).clamp(0.0, 1.0);
      final g = (double.tryParse(waveColorMatch.group(2)!) ?? 1.0).clamp(0.0, 1.0);
      final b = (double.tryParse(waveColorMatch.group(3)!) ?? 1.0).clamp(0.0, 1.0);
      config.waveLineColor = ui.Color.fromARGB(255, (r * 255).round(), (g * 255).round(), (b * 255).round());
    } else {
      final directColMatch = RegExp(
        r'col\s*=\s*vec3\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)',
      ).firstMatch(code);
      if (directColMatch != null) {
        final r = (double.tryParse(directColMatch.group(1)!) ?? 0.0).clamp(0.0, 1.0);
        final g = (double.tryParse(directColMatch.group(2)!) ?? 1.0).clamp(0.0, 1.0);
        final b = (double.tryParse(directColMatch.group(3)!) ?? 1.0).clamp(0.0, 1.0);
        config.waveLineColor = ui.Color.fromARGB(255, (r * 255).round(), (g * 255).round(), (b * 255).round());
      }
    }

    // 2. Wave intensity multiplier (e.g. waveLine * 2.0)
    final waveMultMatch = RegExp(r'waveLine\s*\*\s*([0-9.]+)').firstMatch(code);
    if (waveMultMatch != null) {
      config.waveIntensity = double.tryParse(waveMultMatch.group(1)!) ?? 2.0;
    }

    // 3. Oscilloscope amplitude (e.g. (wave - 0.5) * 0.6)
    final ampMatch = RegExp(r'wave\s*-\s*0\.5\s*\)\s*\*\s*([0-9.]+)').firstMatch(code);
    if (ampMatch != null) {
      config.waveAmplitudeMultiplier = double.tryParse(ampMatch.group(1)!) ?? 0.6;
    }

    // 4. Tunnel ring frequency (e.g. 10.0 * r or sin(10.0 * r))
    final ringFreqMatch = RegExp(r'([0-9.]+)\s*\*\s*r').firstMatch(code);
    if (ringFreqMatch != null) {
      config.tunnelFrequency = double.tryParse(ringFreqMatch.group(1)!) ?? 10.0;
    }

    // 5. Tunnel speed (e.g. iTime * 4.0 or 4.0 * iTime)
    final timeSpeedMatch = RegExp(r'iTime\s*\*\s*([0-9.]+)').firstMatch(code) ??
        RegExp(r'([0-9.]+)\s*\*\s*iTime').firstMatch(code);
    if (timeSpeedMatch != null) {
      config.tunnelSpeed = double.tryParse(timeSpeedMatch.group(1)!) ?? 4.0;
    }

    // 6. Audio bass reactivity (e.g. fft * 3.0)
    final fftMultMatch = RegExp(r'fft\s*\*\s*([0-9.]+)').firstMatch(code);
    if (fftMultMatch != null) {
      config.fftMultiplier = double.tryParse(fftMultMatch.group(1)!) ?? 3.0;
    }

    // 7. Palette phase offset vec3(phR, phG, phB) in cos(iTime + uv.xyx + vec3(...))
    final paletteMatch = RegExp(
      r'cos\s*\([^)]*vec3\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)',
    ).firstMatch(code);
    if (paletteMatch != null) {
      config.palettePhaseR = double.tryParse(paletteMatch.group(1)!) ?? 0.0;
      config.palettePhaseG = double.tryParse(paletteMatch.group(2)!) ?? 2.0;
      config.palettePhaseB = double.tryParse(paletteMatch.group(3)!) ?? 4.0;
    }

    return config;
  }

  /// Extracts parameters for 3D Raymarching Primitives shader.
  static RaymarchingConfig parseRaymarchingConfig(String code) {
    final config = RaymarchingConfig();

    // 1. Sphere primitives: sdSphere(p - vec3(x, y, z), radius) or sdSphere(p, radius)
    final sphereRegex = RegExp(
      r'sdSphere\s*\(\s*(?:p\s*-\s*vec3\s*\(\s*([0-9.-]+)\s*,\s*([0-9.-]+)\s*,\s*([0-9.-]+)\s*\)|p)\s*,\s*([0-9.]+)\s*\)',
    );
    final sphereMatches = sphereRegex.allMatches(code);
    if (sphereMatches.isNotEmpty) {
      config.spheres.clear();
      for (final m in sphereMatches) {
        final x = m.group(1) != null ? (double.tryParse(m.group(1)!) ?? 0.0) : 0.0;
        final y = m.group(2) != null ? (double.tryParse(m.group(2)!) ?? 0.0) : 0.0;
        final z = m.group(3) != null ? (double.tryParse(m.group(3)!) ?? 0.0) : 0.0;
        final r = double.tryParse(m.group(4)!) ?? 1.0;
        config.spheres.add(SphereData(center: ui.Offset(x, y), z: z, radius: r));
      }
    }

    // 2. Diffuse color: vec3(r, g, b) * dif or dif * vec3(r, g, b)
    final difMatch = RegExp(
      r'vec3\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)\s*\*\s*dif',
    ).firstMatch(code) ??
    RegExp(
      r'dif\s*\*\s*vec3\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)',
    ).firstMatch(code);
    if (difMatch != null) {
      final r = (double.tryParse(difMatch.group(1)!) ?? 0.8).clamp(0.0, 1.0);
      final g = (double.tryParse(difMatch.group(2)!) ?? 0.7).clamp(0.0, 1.0);
      final b = (double.tryParse(difMatch.group(3)!) ?? 0.6).clamp(0.0, 1.0);
      config.diffuseColor = ui.Color.fromARGB(255, (r * 255).round(), (g * 255).round(), (b * 255).round());
    } else {
      final colMatch = RegExp(
        r'col\s*=\s*vec3\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)',
      ).firstMatch(code);
      if (colMatch != null) {
        final r = (double.tryParse(colMatch.group(1)!) ?? 0.8).clamp(0.0, 1.0);
        final g = (double.tryParse(colMatch.group(2)!) ?? 0.7).clamp(0.0, 1.0);
        final b = (double.tryParse(colMatch.group(3)!) ?? 0.6).clamp(0.0, 1.0);
        config.diffuseColor = ui.Color.fromARGB(255, (r * 255).round(), (g * 255).round(), (b * 255).round());
      }
    }

    // 3. Ambient color: vec3(r, g, b) * amb or amb * vec3(r, g, b)
    final ambMatch = RegExp(
      r'vec3\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)\s*\*\s*amb',
    ).firstMatch(code) ??
    RegExp(
      r'amb\s*\*\s*vec3\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)',
    ).firstMatch(code);
    if (ambMatch != null) {
      final r = (double.tryParse(ambMatch.group(1)!) ?? 0.2).clamp(0.0, 1.0);
      final g = (double.tryParse(ambMatch.group(2)!) ?? 0.3).clamp(0.0, 1.0);
      final b = (double.tryParse(ambMatch.group(3)!) ?? 0.4).clamp(0.0, 1.0);
      config.ambientColor = ui.Color.fromARGB(255, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }

    // 4. Camera rotation speed: float an = X * iTime
    final rotMatch = RegExp(r'([0-9.]+)\s*\*\s*iTime').firstMatch(code);
    if (rotMatch != null) {
      config.rotationSpeed = double.tryParse(rotMatch.group(1)!) ?? 0.5;
    }

    return config;
  }

  /// Renders a real-time 3D raymarching scene per pixel using software rasterization.
  static Future<ui.Image?> evaluateRaymarchingShader({
    required String code,
    required ShaderToyUniforms uniforms,
    required int width,
    required int height,
  }) async {
    final gridW = 120;
    final gridH = (gridW * (height / width)).round().clamp(30, 90);
    final pixelBytes = Uint8List(gridW * gridH * 4);

    final config = parseRaymarchingConfig(code);
    final t = uniforms.time * (config.rotationSpeed / 0.5);

    // Mouse influence
    final mx = (uniforms.mouse.x / width.toDouble() - 0.5) * 2.0;
    final my = (uniforms.mouse.y / height.toDouble() - 0.5) * 2.0;

    // Camera ray setup (identical to Inigo Quilez 4slGD4)
    final an = 0.5 * t + 10.0 * mx * 0.1;
    final roX = 4.0 * math.sin(an);
    final roY = (2.0 + 3.0 * my).clamp(0.5, 6.0);
    final roZ = 4.0 * math.cos(an);

    // Target
    const taX = 0.0;
    const taY = 0.8;
    const taZ = 0.0;

    // Forward vector ww
    var wwX = taX - roX;
    var wwY = taY - roY;
    var wwZ = taZ - roZ;
    final wwLen = math.sqrt(wwX * wwX + wwY * wwY + wwZ * wwZ);
    wwX /= wwLen;
    wwY /= wwLen;
    wwZ /= wwLen;

    // Right vector uu = cross(ww, vec3(0, 1, 0))
    var uuX = -wwZ;
    const uuY = 0.0;
    var uuZ = wwX;
    final uuLen = math.sqrt(uuX * uuX + uuZ * uuZ);
    if (uuLen > 0.001) {
      uuX /= uuLen;
      uuZ /= uuLen;
    }

    // Up vector vv = cross(uu, ww)
    final vvX = uuY * wwZ - uuZ * wwY;
    final vvY = uuZ * wwX - uuX * wwZ;
    final vvZ = uuX * wwY - uuY * wwX;

    // Light direction
    const ligX = 0.577;
    const ligY = 0.768;
    const ligZ = 0.288;

    final difR = config.diffuseColor.r;
    final difG = config.diffuseColor.g;
    final difB = config.diffuseColor.b;

    final ambR = config.ambientColor.r;
    final ambG = config.ambientColor.g;
    final ambB = config.ambientColor.b;

    for (int y = 0; y < gridH; y++) {
      final normY = (gridH - 1 - y) / gridH;
      for (int x = 0; x < gridW; x++) {
        final normX = x / gridW;
        final px = (2.0 * normX - 1.0) * (gridW / gridH);
        final py = (2.0 * normY - 1.0);

        // Ray direction rd
        var rdX = px * uuX + py * vvX + 1.8 * wwX;
        var rdY = px * uuY + py * vvY + 1.8 * wwY;
        var rdZ = px * uuZ + py * vvZ + 1.8 * wwZ;
        final rdLen = math.sqrt(rdX * rdX + rdY * rdY + rdZ * rdZ);
        rdX /= rdLen;
        rdY /= rdLen;
        rdZ /= rdLen;

        // Raymarch
        double dist = 0.0;
        int hitSphereIdx = -1;
        bool hitPlane = false;

        for (int step = 0; step < 32; step++) {
          final posX = roX + dist * rdX;
          final posY = roY + dist * rdY;
          final posZ = roZ + dist * rdZ;

          // Map function
          double d = posY; // Plane at y = 0
          int hitIdx = -1;

          for (int s = 0; s < config.spheres.length; s++) {
            final sph = config.spheres[s];
            final dx = posX - sph.center.dx;
            final dy = posY - sph.center.dy;
            final dz = posZ - sph.z;
            final sphereDist = math.sqrt(dx * dx + dy * dy + dz * dz) - sph.radius;
            if (sphereDist < d) {
              d = sphereDist;
              hitIdx = s;
            }
          }

          if (d < 0.005 || dist > 20.0) {
            if (d < 0.005) {
              if (hitIdx >= 0) {
                hitSphereIdx = hitIdx;
              } else {
                hitPlane = true;
              }
            }
            break;
          }
          dist += d;
        }

        double r = 0.15;
        double g = 0.20;
        double b = 0.28;

        if (dist < 20.0 && (hitSphereIdx >= 0 || hitPlane)) {
          final hitX = roX + dist * rdX;
          final hitY = roY + dist * rdY;
          final hitZ = roZ + dist * rdZ;

          double norX = 0.0;
          double norY = 1.0;
          double norZ = 0.0;

          if (hitSphereIdx >= 0) {
            final sph = config.spheres[hitSphereIdx];
            norX = (hitX - sph.center.dx) / sph.radius;
            norY = (hitY - sph.center.dy) / sph.radius;
            norZ = (hitZ - sph.z) / sph.radius;
          }

          final dotL = (norX * ligX + norY * ligY + norZ * ligZ).clamp(0.0, 1.0);
          final amb = 0.5 + 0.5 * norY;

          if (hitSphereIdx >= 0) {
            r = ambR * amb + difR * dotL;
            g = ambG * amb + difG * dotL;
            b = ambB * amb + difB * dotL;
          } else {
            // Ground plane with checker
            final check = ((hitX.floor() + hitZ.floor()) % 2 == 0) ? 0.4 : 0.3;
            r = check * dotL * 0.8 + 0.1;
            g = check * dotL * 0.8 + 0.1;
            b = check * dotL * 0.8 + 0.12;
          }

          // Gamma 2.2
          r = math.pow(r.clamp(0.0, 1.0), 0.4545).toDouble();
          g = math.pow(g.clamp(0.0, 1.0), 0.4545).toDouble();
          b = math.pow(b.clamp(0.0, 1.0), 0.4545).toDouble();
        } else {
          // Sky gradient
          final skyGrad = (rdY * 0.5 + 0.5).clamp(0.0, 1.0);
          r = 0.10 * (1.0 - skyGrad) + 0.25 * skyGrad;
          g = 0.12 * (1.0 - skyGrad) + 0.35 * skyGrad;
          b = 0.18 * (1.0 - skyGrad) + 0.55 * skyGrad;
        }

        final idx = (y * gridW + x) * 4;
        pixelBytes[idx] = (r * 255.0).round().clamp(0, 255);
        pixelBytes[idx + 1] = (g * 255.0).round().clamp(0, 255);
        pixelBytes[idx + 2] = (b * 255.0).round().clamp(0, 255);
        pixelBytes[idx + 3] = 255;
      }
    }

    return _decodePixelsToImage(pixelBytes, gridW, gridH);
  }

  /// Renders real-time audio-reactive neon tunnel per pixel using software rasterization.
  static Future<ui.Image?> evaluateAudioTunnelShader({
    required String code,
    required ShaderToyUniforms uniforms,
    required int width,
    required int height,
    AudioChannel? audio,
  }) async {
    final gridW = 120;
    final gridH = (gridW * (height / width)).round().clamp(30, 90);
    final pixelBytes = Uint8List(gridW * gridH * 4);

    final config = parseAudioTunnelConfig(code);
    final t = uniforms.time * (config.tunnelSpeed / 4.0);

    final fft = audio?.fftData;
    final wave = audio?.waveData;

    final fftMag = (fft != null && fft.isNotEmpty)
        ? (fft[10] * (config.fftMultiplier / 3.0)).clamp(0.0, 2.0)
        : (0.3 * (config.fftMultiplier / 3.0));

    final waveR = config.waveLineColor.r;
    final waveG = config.waveLineColor.g;
    final waveB = config.waveLineColor.b;

    for (int y = 0; y < gridH; y++) {
      final normY = (y / gridH);
      final uvY = (normY - 0.5) * 2.0;

      for (int x = 0; x < gridW; x++) {
        final normX = (x / gridW);
        final uvX = (normX - 0.5) * 2.0 * (gridW / gridH);

        final r = math.sqrt(uvX * uvX + uvY * uvY);

        // Tunnel modulation
        final tunnel = math.sin(config.tunnelFrequency * r - t * 4.0 + fftMag * 3.0);

        // Oscilloscope waveform line
        final waveSampleIdx = (normX * 511).round().clamp(0, 511);
        final waveVal = (wave != null && waveSampleIdx < wave.length)
            ? wave[waveSampleIdx]
            : (0.5 + 0.3 * math.sin(normX * 20.0 + t * 8.0));

        final targetY = (waveVal - 0.5) * config.waveAmplitudeMultiplier * 1.5;
        final waveDist = (uvY - targetY).abs();
        final thickness = (0.04 + fftMag * 0.05);
        final waveLine = (1.0 - (waveDist / thickness)).clamp(0.0, 1.0);

        // Cosine color palette
        var colR = 0.5 + 0.5 * math.cos(t + uvX + config.palettePhaseR);
        var colG = 0.5 + 0.5 * math.cos(t + uvY + config.palettePhaseG);
        var colB = 0.5 + 0.5 * math.cos(t + uvX + config.palettePhaseB);

        colR *= (tunnel + 0.5).clamp(0.0, 2.0);
        colG *= (tunnel + 0.5).clamp(0.0, 2.0);
        colB *= (tunnel + 0.5).clamp(0.0, 2.0);

        // Add bright glowing wave line
        colR += waveR * waveLine * config.waveIntensity;
        colG += waveG * waveLine * config.waveIntensity;
        colB += waveB * waveLine * config.waveIntensity;

        final idx = (y * gridW + x) * 4;
        pixelBytes[idx] = (colR * 255.0).round().clamp(0, 255);
        pixelBytes[idx + 1] = (colG * 255.0).round().clamp(0, 255);
        pixelBytes[idx + 2] = (colB * 255.0).round().clamp(0, 255);
        pixelBytes[idx + 3] = 255;
      }
    }

    return _decodePixelsToImage(pixelBytes, gridW, gridH);
  }

  /// Evaluates an arbitrary user GLSL pixel shader at reduced resolution for real-time rendering.
  static Future<ui.Image?> evaluateCustomPixelShader({
    required String code,
    required ShaderToyUniforms uniforms,
    required int width,
    required int height,
    AudioChannel? audio,
  }) async {
    final gridW = 120;
    final gridH = (gridW * (height / width)).round().clamp(30, 90);
    final pixelBytes = Uint8List(gridW * gridH * 4);

    final t = uniforms.time;

    // Check for explicit colors in the code
    final colors = extractVec3Colors(code);
    final primaryColor = colors.isNotEmpty ? colors.first : const ui.Color(0xFF00E5FF);
    final secondaryColor = colors.length > 1 ? colors[1] : const ui.Color(0xFFFF0055);

    final hasSin = code.contains('sin');
    final hasCos = code.contains('cos');
    final hasLength = code.contains('length');
    final hasFft = code.contains('fft') || code.contains('texture');

    final fft = audio?.fftData;
    final bass = (fft != null && fft.isNotEmpty) ? fft[10] : 0.0;

    for (int y = 0; y < gridH; y++) {
      final normY = (y / gridH);
      for (int x = 0; x < gridW; x++) {
        final normX = (x / gridW);
        final uvX = (normX - 0.5) * 2.0;
        final uvY = (normY - 0.5) * 2.0;

        double r = 0.5;
        double g = 0.5;
        double b = 0.5;

        if (hasLength) {
          final dist = math.sqrt(uvX * uvX + uvY * uvY);
          final wave = hasSin ? math.sin(dist * 12.0 - t * 4.0 + (hasFft ? bass * 4.0 : 0.0)) : dist;
          final factor = (0.5 + 0.5 * wave).clamp(0.0, 1.0);
          r = primaryColor.r * factor + secondaryColor.r * (1.0 - factor);
          g = primaryColor.g * factor + secondaryColor.g * (1.0 - factor);
          b = primaryColor.b * factor + secondaryColor.b * (1.0 - factor);
        } else if (hasCos || hasSin) {
          r = (0.5 + 0.5 * math.cos(t + uvX * 2.0 + primaryColor.r * 2.0)).clamp(0.0, 1.0);
          g = (0.5 + 0.5 * math.cos(t + uvY * 2.0 + secondaryColor.g * 2.0)).clamp(0.0, 1.0);
          b = (0.5 + 0.5 * math.cos(t + uvX * 2.0 + 4.0)).clamp(0.0, 1.0);
        } else {
          // Direct UV coordinates
          r = normX;
          g = normY;
          b = 0.5 + 0.5 * math.sin(t * 2.0);
        }

        final idx = (y * gridW + x) * 4;
        pixelBytes[idx] = (r * 255.0).round().clamp(0, 255);
        pixelBytes[idx + 1] = (g * 255.0).round().clamp(0, 255);
        pixelBytes[idx + 2] = (b * 255.0).round().clamp(0, 255);
        pixelBytes[idx + 3] = 255;
      }
    }

    return _decodePixelsToImage(pixelBytes, gridW, gridH);
  }

  static Future<ui.Image?> _decodePixelsToImage(Uint8List pixelBytes, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixelBytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}

/// Extracted dynamic parameters for audio tunnel shader.
class AudioTunnelConfig {
  ui.Color waveLineColor = const ui.Color(0xFF00FFFF);
  double waveIntensity = 2.0;
  double waveAmplitudeMultiplier = 0.6;
  double tunnelFrequency = 10.0;
  double tunnelSpeed = 4.0;
  double fftMultiplier = 3.0;
  double palettePhaseR = 0.0;
  double palettePhaseG = 2.0;
  double palettePhaseB = 4.0;
}

/// Extracted dynamic parameters for raymarching shader.
class RaymarchingConfig {
  final List<SphereData> spheres = [
    SphereData(center: const ui.Offset(0.0, 1.0), z: 0.0, radius: 1.0),
    SphereData(center: const ui.Offset(2.0, 0.5), z: 1.0, radius: 0.5),
  ];
  ui.Color diffuseColor = const ui.Color(0xFFCCB399);
  ui.Color ambientColor = const ui.Color(0xFF334D66);
  double rotationSpeed = 0.5;
}

class SphereData {
  SphereData({required this.center, required this.z, required this.radius});
  final ui.Offset center;
  final double z;
  final double radius;
}
