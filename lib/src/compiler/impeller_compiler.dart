import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// Compiler service that wraps Shadertoy GLSL code into modern Vulkan GLSL 4.60,
/// generates full-screen quad vertex shader geometry, and invokes `impellerc`
/// to produce Flutter GPU `.shaderbundle` binaries or extract compilation errors.
class ImpellerCompiler {
  static String? _cachedImpellercPath;

  /// Locates the `impellerc` offline compiler binary from system PATH or Flutter SDK cache.
  static String? findImpellerc() {
    try {
      if (_cachedImpellercPath != null &&
          File(_cachedImpellercPath!).existsSync()) {
        return _cachedImpellercPath;
      }
    } catch (_) {}

    // 1. Check environment variables
    try {
      final flutterRoot = Platform.environment['FLUTTER_ROOT'];
      if (flutterRoot != null) {
        final candidate = _findInFlutterRoot(flutterRoot);
        if (candidate != null) {
          _cachedImpellercPath = candidate;
          return candidate;
        }
      }
    } catch (_) {}

    // 2. Check system PATH via 'which' or 'where'
    try {
      final whichCmd = Platform.isWindows ? 'where' : 'which';
      final result = Process.runSync(whichCmd, ['flutter']);
      if (result.exitCode == 0) {
        final flutterPath = result.stdout.toString().trim().split('\n').first;
        // flutter is typically in <flutter_dir>/bin/flutter
        final flutterDir = File(flutterPath).parent.parent.path;
        final candidate = _findInFlutterRoot(flutterDir);
        if (candidate != null) {
          _cachedImpellercPath = candidate;
          return candidate;
        }
      }
    } catch (_) {}

    // 3. Fallback common developer directories on macOS / Linux / Windows
    final commonPaths = [
      '/Volumes/NVME/dev/flutter',
      Platform.environment['HOME'] != null
          ? '${Platform.environment['HOME']}/development/flutter'
          : null,
      Platform.environment['HOME'] != null
          ? '${Platform.environment['HOME']}/flutter'
          : null,
    ];

    for (final dir in commonPaths) {
      if (dir == null) continue;
      try {
        if (Directory(dir).existsSync()) {
          final candidate = _findInFlutterRoot(dir);
          if (candidate != null) {
            _cachedImpellercPath = candidate;
            return candidate;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  static String? _findInFlutterRoot(String flutterRoot) {
    final exeName = Platform.isWindows ? 'impellerc.exe' : 'impellerc';

    // 1. Check known host architecture subdirectories directly to avoid directory listing
    final hostArchs = [
      'darwin-arm64',
      'darwin-x64',
      'windows-x64',
      'linux-x64',
      'linux-arm64',
    ];

    for (final arch in hostArchs) {
      try {
        final candidateFile =
            File('$flutterRoot/bin/cache/artifacts/engine/$arch/$exeName');
        if (candidateFile.existsSync()) {
          return candidateFile.path;
        }
      } catch (_) {}
    }

    // 2. Fallback to directory listing if allowed
    try {
      final engineArtifacts =
          Directory('$flutterRoot/bin/cache/artifacts/engine');
      if (engineArtifacts.existsSync()) {
        final subdirs = engineArtifacts.listSync();
        for (final entity in subdirs) {
          if (entity is Directory) {
            final file = File('${entity.path}/$exeName');
            if (file.existsSync()) {
              return file.path;
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// The full-screen quad vertex shader source.
  static const String quadVertexShader = '''#version 460 core
layout(location = 0) in vec2 position;
void main() {
    gl_Position = vec4(position, 0.0, 1.0);
}
''';

  static final RegExp _commentRegex =
      RegExp(r'//.*$|/\*[\s\S]*?\*/', multiLine: true);

  /// Returns true if [code] references `iChannel$channelIndex` outside of comments.
  static bool shaderUsesChannel(String code, int channelIndex) {
    final clean = code.replaceAll(_commentRegex, '');
    return RegExp('\\biChannel$channelIndex\\b').hasMatch(clean);
  }

  /// Wraps user Shadertoy GLSL with Vulkan GLSL 4.60 headers, uniform buffers,
  /// Wraps user-provided Shadertoy GLSL code with Flutter GPU (Impeller) compatible
  /// uniforms (std140 FrameInfo uniform block at set 0, binding 0), optional
  /// samplers, macros, and standard main() entry point.
  /// If [commonGlsl] is provided, it is prepended so shared functions/structs
  /// are accessible to the pass.
  /// Uses `#line 1` so compiler error lines match the user's source lines.
  static String wrapShadertoyGlsl(String userGlsl, {String? commonGlsl}) {
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
};
''');


    final codeForChannels = (commonGlsl != null && commonGlsl.trim().isNotEmpty)
        ? '$commonGlsl\n$userGlsl'
        : userGlsl;

    final declaredChannels = <int>[];
    for (int i = 0; i < 4; i++) {
      if (shaderUsesChannel(codeForChannels, i)) {
        declaredChannels.add(i);
        sb.writeln('layout(set = 0, binding = ${i + 1}) uniform sampler2D iChannel$i;');
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

    if (commonGlsl != null && commonGlsl.trim().isNotEmpty) {
      sb.writeln('// Common Tab source');
      sb.writeln(commonGlsl);
      sb.writeln();
    }

    sb.writeln('''#line 1
$userGlsl

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
  }) async {
    final impellerc = customImpellercPath ?? findImpellerc();
    if (impellerc == null) {
      return const CompileResult.error(
        'Could not locate "impellerc" compiler binary in Flutter SDK. '
        'Please ensure Flutter is installed and on PATH.',
      );
    }

    final tempDir = await Directory.systemTemp.createTemp('shadertoy_compile_');
    try {
      final vertFile = File('${tempDir.path}/quad.vert');
      final fragFile = File('${tempDir.path}/shadertoy.frag');
      final bundleFile = File('${tempDir.path}/output.shaderbundle');

      await vertFile.writeAsString(quadVertexShader);
      await fragFile.writeAsString(
        wrapShadertoyGlsl(shadertoyGlsl, commonGlsl: commonGlsl),
      );

      final manifestJson = json.encode({
        'QuadVertex': {
          'type': 'vertex',
          'file': vertFile.path,
        },
        'ShadertoyFragment': {
          'type': 'fragment',
          'file': fragFile.path,
        },
      });

      // Target platform flag
      final String platformFlag;
      if (Platform.isMacOS) {
        platformFlag = '--metal-desktop';
      } else if (Platform.isIOS) {
        platformFlag = '--metal-ios';
      } else {
        platformFlag = '--vulkan';
      }

      final result = await Process.run(
        impellerc,
        [
          platformFlag,
          '--gles-language-version=300',
          '--shader-bundle=$manifestJson',
          '--sl=${bundleFile.path}',
          '--verbose',
        ],
        workingDirectory: tempDir.path,
      );


      if (result.exitCode != 0) {
        final stderr = result.stderr.toString().trim();
        final stdout = result.stdout.toString().trim();
        final rawMsg = stderr.isNotEmpty ? stderr : stdout;

        return CompileResult.error(_cleanCompilerError(rawMsg));
      }

      if (!await bundleFile.exists()) {
        return const CompileResult.error(
          'impellerc succeeded but output.shaderbundle was not produced.',
        );
      }

      final bytes = await bundleFile.readAsBytes();
      return CompileResult.success(bytes);
    } catch (e) {
      return CompileResult.error('Compilation exception: $e');
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Cleans and formats raw impellerc stderr for human-friendly UI display.
  static String _cleanCompilerError(String raw) {
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
