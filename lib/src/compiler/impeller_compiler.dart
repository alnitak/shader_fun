import 'dart:typed_data';

import '../core/shadertoy_uniforms.dart';
import 'compile_process.dart';

/// Result of an `impellerc` shader compilation.
class CompileResult {
  const CompileResult.success(this.bundleBytes)
    : isSuccess = true,
      errorMessage = null;

  const CompileResult.error(this.errorMessage)
    : isSuccess = false,
      bundleBytes = null;

  final bool isSuccess;
  final Uint8List? bundleBytes;
  final String? errorMessage;
}

/// Represents a user-declared or injected custom uniform mapping.
class CustomUniformDeclaration {
  const CustomUniformDeclaration({
    required this.name,
    required this.type,
    required this.slot,
  });

  final String name;
  final String type; // 'float', 'int', 'vec2', 'vec3', 'vec4'
  final int slot;
}

/// Compiler service that wraps Shadertoy GLSL code into modern Vulkan GLSL 4.60,
/// generates full-screen quad vertex shader geometry, and invokes `impellerc`
/// to produce Flutter GPU `.shaderbundle` binaries or extract compilation errors.
class ImpellerCompiler {
  /// Locates the `impellerc` offline compiler binary from system PATH or Flutter SDK cache.
  static String? findImpellerc() => findImpellercBinary();

  /// The full-screen quad vertex shader source.
  static const String quadVertexShader = '''#version 460 core
layout(location = 0) in vec2 position;
void main() {
    gl_Position = vec4(position, 0.0, 1.0);
}
''';

  static final RegExp _commentRegex = RegExp(
    r'//.*$|/\*[\s\S]*?\*/',
    multiLine: true,
  );

  /// Returns true if [code] references `iChannel$channelIndex` outside of comments.
  static bool shaderUsesChannel(String code, int channelIndex) {
    final clean = code.replaceAll(_commentRegex, '');
    return RegExp('\\biChannel$channelIndex\\b').hasMatch(clean);
  }

  static final _customUniformRegex = RegExp(
    r'^\s*uniform\s+(float|int|vec2|vec3|vec4)\s+([a-zA-Z0-9_]+)\s*;',
    multiLine: true,
  );

  static const _builtInUniformNames = {
    'iResolution',
    'iTime',
    'iTimeDelta',
    'iFrameRate',
    'iFrame',
    'iMouse',
    'iDate',
    'iSampleRate',
    'iChannelResolution',
    'iChannelTime',
    'iChannel0',
    'iChannel1',
    'iChannel2',
    'iChannel3',
  };

  /// Extracts user-declared custom uniforms from GLSL code.
  /// Looks for top-level `uniform <type> <name>;` lines where type is
  /// `float`, `int`, `vec2`, `vec3`, or `vec4`.
  static List<CustomUniformDeclaration> extractCustomUniforms(
    String glsl, {
    Map<String, int>? existingSlots,
  }) {
    final uniforms = <CustomUniformDeclaration>[];
    final assignedSlots = <int>{...?existingSlots?.values};
    final seen = <String>{};

    int getNextSlot(String name) {
      if (existingSlots != null && existingSlots.containsKey(name)) {
        return existingSlots[name]!;
      }
      for (int i = 0; i < ShaderToyUniforms.maxCustomUniformSlots; i++) {
        if (!assignedSlots.contains(i)) {
          assignedSlots.add(i);
          return i;
        }
      }
      return 0;
    }

    for (final match in _customUniformRegex.allMatches(glsl)) {
      final type = match.group(1)!;
      final name = match.group(2)!;
      if (_builtInUniformNames.contains(name) || seen.contains(name)) {
        continue;
      }
      seen.add(name);
      final slot = getNextSlot(name);
      uniforms.add(
        CustomUniformDeclaration(name: name, type: type, slot: slot),
      );
    }
    return uniforms;
  }

  /// Wraps user Shadertoy GLSL with Vulkan GLSL 4.60 headers, uniform buffers,
  /// optional samplers, macros, and standard main() entry point.
  /// If [commonGlsl] is provided, it is prepended so shared functions/structs
  /// are accessible to the pass.
  /// Uses `#line 1` so compiler error lines match the user's source lines.
  static String wrapShadertoyGlsl(
    String userGlsl, {
    String? commonGlsl,
    Map<String, int>? customUniformSlots,
  }) {
    final sb = StringBuffer();
    sb.writeln('''#version 460 core

layout(std140, set = 0, binding = 0) uniform FrameInfo {
    vec3 iResolution;
    float iTime;
    float iTimeDelta;
    float iFrameRate;
    int iFrame;
    vec4 iMouse;
    vec4 iDate;
    float iSampleRate;
    vec3 iChannelResolution[4];
    // ${ShaderToyUniforms.maxCustomUniformSlots} vec4 registers = ${ShaderToyUniforms.customUniformsSizeBytes} bytes reserved for custom uniforms.
    // Total FrameInfo buffer size: ${ShaderToyUniforms.totalUniformBufferSize} bytes.
    // Controlled globally via [ShaderToyUniforms.maxCustomUniformSlots] and [ShaderToyUniforms.totalUniformBufferSize].
    vec4 iCustom[${ShaderToyUniforms.maxCustomUniformSlots}];
};
''');

    final codeForChannels = (commonGlsl != null && commonGlsl.trim().isNotEmpty)
        ? '$commonGlsl\n$userGlsl'
        : userGlsl;

    final declaredCustoms = extractCustomUniforms(
      codeForChannels,
      existingSlots: customUniformSlots,
    );

    final handledNames = <String>{};
    for (final u in declaredCustoms) {
      handledNames.add(u.name);
      switch (u.type) {
        case 'float':
          sb.writeln('#define ${u.name} (iCustom[${u.slot}].x)');
        case 'int':
          sb.writeln('#define ${u.name} (int(iCustom[${u.slot}].x))');
        case 'vec2':
          sb.writeln('#define ${u.name} (iCustom[${u.slot}].xy)');
        case 'vec3':
          sb.writeln('#define ${u.name} (iCustom[${u.slot}].xyz)');
        case 'vec4':
          sb.writeln('#define ${u.name} (iCustom[${u.slot}])');
      }
    }

    if (customUniformSlots != null) {
      for (final entry in customUniformSlots.entries) {
        if (!handledNames.contains(entry.key) &&
            !_builtInUniformNames.contains(entry.key)) {
          sb.writeln('#define ${entry.key} (iCustom[${entry.value}].x)');
        }
      }
    }

    String sanitizeUniforms(String code) {
      return code.replaceAllMapped(_customUniformRegex, (m) {
        final name = m.group(2)!;
        if (_builtInUniformNames.contains(name)) {
          return m.group(0)!;
        }
        return '// ${m.group(0)}';
      });
    }

    final sanitizedUserGlsl = sanitizeUniforms(userGlsl);
    final sanitizedCommonGlsl =
        commonGlsl != null ? sanitizeUniforms(commonGlsl) : null;

    final declaredChannels = <int>[];
    for (int i = 0; i < 4; i++) {
      if (shaderUsesChannel(codeForChannels, i)) {
        declaredChannels.add(i);
        sb.writeln(
          'layout(set = 0, binding = ${i + 1}) uniform sampler2D iChannel$i;',
        );
      }
    }

    sb.writeln('layout(location = 0) out vec4 fragColor;');
    sb.writeln();

    if (declaredChannels.isNotEmpty) {
      // In Vulkan and Metal, render target textures have (0, 0) at the top-left,
      // whereas Shadertoy and OpenGL use bottom-left conventions.
      // Sampling offscreen buffer textures with hardware UVs would invert the Y
      // axis on every pass/frame, causing alternating ping-pong flip flickering.
      // These wrappers invert Y so that sampling is always consistent with Shadertoy.
      sb.writeln('''
vec4 st_texture(sampler2D s, vec2 uv) {
    return texture(s, vec2(uv.x, 1.0 - uv.y));
}
vec4 st_texture(sampler2D s, vec2 uv, float bias) {
    return texture(s, vec2(uv.x, 1.0 - uv.y), bias);
}
vec4 st_textureLod(sampler2D s, vec2 uv, float lod) {
    return textureLod(s, vec2(uv.x, 1.0 - uv.y), lod);
}
vec4 st_texelFetch(sampler2D s, ivec2 p, int lod) {
    return texelFetch(s, ivec2(p.x, textureSize(s, lod).y - 1 - p.y), lod);
}
#define texture st_texture
#define textureLod st_textureLod
#define texelFetch st_texelFetch
''');
    }

    sb.writeln('''
// Metal Shading Language translates pow(x, y) to powr(x, y), which produces
// undefined results / NaNs if x < 0. In GLSL on OpenGL/Vulkan, hardware drivers
// often clamp or handle negative bases gracefully. st_pow clamps the base to >= 0.0
// to avoid Metal NaN poisoning across procedural distance and lighting functions.
float st_pow(float x, float y) { return pow(max(0.0, x), y); }
vec2 st_pow(vec2 x, vec2 y) { return pow(max(vec2(0.0), x), y); }
vec3 st_pow(vec3 x, vec3 y) { return pow(max(vec3(0.0), x), y); }
vec4 st_pow(vec4 x, vec4 y) { return pow(max(vec4(0.0), x), y); }
vec2 st_pow(vec2 x, float y) { return pow(max(vec2(0.0), x), vec2(y)); }
vec3 st_pow(vec3 x, float y) { return pow(max(vec3(0.0), x), vec3(y)); }
vec4 st_pow(vec4 x, float y) { return pow(max(vec4(0.0), x), vec4(y)); }
#define pow st_pow
''');

    if (sanitizedCommonGlsl != null && sanitizedCommonGlsl.trim().isNotEmpty) {
      sb.writeln('// Common Tab source');
      sb.writeln(sanitizedCommonGlsl);
      sb.writeln();
    }

    sb.writeln('''#line 1
$sanitizedUserGlsl

void main() {
    vec2 fragCoord = vec2(gl_FragCoord.x, iResolution.y - gl_FragCoord.y);
    mainImage(fragColor, fragCoord);''');

    if (declaredChannels.isNotEmpty) {
      // Force impellerc / SPIRV-Cross to retain all declared samplers in the
      // target shader function signature (assigning valid ext_res_0 indices).
      // If a channel is declared but not sampled in active user code (e.g. inside
      // an inactive #if), impellerc would otherwise assign UINT32_MAX to its
      // slot, causing Metal/driver SIGBUS crashes when bindTexture is called.
      // iResolution.x is always >= 0.0 at runtime, so this branch is never taken.
      sb.writeln('    if (iResolution.x < 0.0) {');
      for (final ch in declaredChannels) {
        sb.writeln('        fragColor += texture(iChannel$ch, vec2(0.0));');
      }
      sb.writeln('    }');
    }

    sb.writeln('}');
    return sb.toString();
  }

  /// Compiles a Shadertoy GLSL code string using `impellerc`.
  /// If [commonGlsl] is specified, it is injected before [shadertoyGlsl].
  /// Returns [CompileResult.success] with the compiled `.shaderbundle` bytes,
  /// or [CompileResult.error] with the exact compiler diagnostics from `stderr`.
  static Future<CompileResult> compile({
    required String shadertoyGlsl,
    String? commonGlsl,
    String? customImpellercPath,
    Map<String, int>? customUniformSlots,
  }) {
    return runImpellerCompile(
      quadVertexShader: quadVertexShader,
      wrappedFragGlsl: wrapShadertoyGlsl(
        shadertoyGlsl,
        commonGlsl: commonGlsl,
        customUniformSlots: customUniformSlots,
      ),
      customImpellercPath: customImpellercPath,
      rawUserGlsl: shadertoyGlsl,
      rawCommonGlsl: commonGlsl,
    );
  }

  /// Cleans and formats raw impellerc stderr for human-friendly UI display.
  static String cleanCompilerError(String raw) {
    final lines = raw.split('\n');
    final cleaned = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // Filter internal compilation notices that clutter UI
      if (trimmed.startsWith('Compilation failed for bundled shader')) continue;
      if (trimmed.contains('GLSL to SPIRV failed; Compilation error')) continue;
      cleaned.add(trimmed);
    }

    if (cleaned.isEmpty) {
      return raw.trim();
    }
    return cleaned.join('\n');
  }
}
