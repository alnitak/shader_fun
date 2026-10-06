import 'dart:convert';

import 'package:flutter/foundation.dart';

// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as sbg;
import 'package:flat_buffers/flat_buffers.dart' as fb;

import '../core/common_uniforms.dart';
import '../core/shader_pass.dart';
import '../gpu/gpu.dart' as gpu;

import 'impeller_compiler.dart';

String? findImpellercBinary() => null;

/// Quad vertex shader tailored for WebGL2 in flutter_scene.
const String _quadVertexGlslWeb = '''#version 300 es
uniform float _impeller_y_flip;
layout(location = 0) in vec2 position;
void main() {
    gl_Position = vec4(position.x, position.y, 0.0, 1.0);
    gl_Position.y *= _impeller_y_flip;
}
''';

/// Wraps shader GLSL code into modern WebGL2 GLSL ES 3.00 with
/// std140 uniform block, sampler bindings, compatibility definitions,
/// and main() entrypoint.
String _wrapShaderGlslWeb({
  required String userGlsl,
  String? commonGlsl,
  required List<int> declaredChannels,
  Map<String, int>? customUniformSlots,
  PassType passType = PassType.image,
  int soundTextureWidth = 256,
}) {
  final cleanUserCode = userGlsl.replaceAll(
    RegExp(r'//.*$|/\*[\s\S]*?\*/', multiLine: true),
    '',
  );
  final isSound =
      passType == PassType.sound ||
      (passType != PassType.common &&
          !cleanUserCode.contains('mainImage') &&
          cleanUserCode.contains('mainSound'));

  final sb = StringBuffer();
  sb.writeln('''#version 300 es
precision highp float;
precision highp int;

layout(std140) uniform FrameInfo {
    vec3 iResolution;
    float iTime;
    float iTimeDelta;
    float iFrameRate;
    int iFrame;
    vec4 iMouse;
    vec4 iDate;
    float iSampleRate;
    vec3 iChannelResolution[4];
    // ${CommonUniforms.maxCustomUniformSlots} vec4 registers = ${CommonUniforms.customUniformsSizeBytes} bytes reserved for custom uniforms.
    // Total FrameInfo buffer size: ${CommonUniforms.totalUniformBufferSize} bytes.
    vec4 iCustom[${CommonUniforms.maxCustomUniformSlots}];
};
''');

  if (isSound) {
    sb.writeln('#define iBlockOffset iTime');
  }

  final codeForUniforms = (commonGlsl != null && commonGlsl.trim().isNotEmpty)
      ? '$commonGlsl\n$userGlsl'
      : userGlsl;

  final declaredCustoms = ImpellerCompiler.extractCustomUniforms(
    codeForUniforms,
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
      if (!handledNames.contains(entry.key)) {
        sb.writeln('#define ${entry.key} (iCustom[${entry.value}].x)');
      }
    }
  }

  String sanitizeUniforms(String code) {
    return code.replaceAllMapped(
      RegExp(
        r'^\s*uniform\s+(float|int|vec2|vec3|vec4)\s+([a-zA-Z0-9_]+)\s*;',
        multiLine: true,
      ),
      (m) => '// ${m.group(0)}',
    );
  }

  final sanitizedUserGlsl = sanitizeUniforms(userGlsl);
  final sanitizedCommonGlsl = commonGlsl != null
      ? sanitizeUniforms(commonGlsl)
      : null;

  for (final ch in declaredChannels) {
    sb.writeln('uniform highp sampler2D iChannel$ch;');
  }

  sb.writeln('layout(location = 0) out highp vec4 fragColor;');
  sb.writeln();

  // Backward compatibility aliases for older shader GLSL
  sb.writeln('''
#define texture2D texture
#define textureCube texture
''');

  if (declaredChannels.isNotEmpty) {
    sb.writeln('''
vec4 st_texture(highp sampler2D s, vec2 uv) {
    return texture(s, vec2(uv.x, 1.0 - uv.y));
}
vec4 st_texture(highp sampler2D s, vec2 uv, float bias) {
    return texture(s, vec2(uv.x, 1.0 - uv.y), bias);
}
vec4 st_textureLod(highp sampler2D s, vec2 uv, float lod) {
    return textureLod(s, vec2(uv.x, 1.0 - uv.y), lod);
}
vec4 st_texelFetch(highp sampler2D s, ivec2 p, int lod) {
    return texelFetch(s, ivec2(p.x, textureSize(s, lod).y - 1 - p.y), lod);
}
#define texture st_texture
#define textureLod st_textureLod
#define texelFetch st_texelFetch
''');
  }

  sb.writeln('''
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
''');

  if (isSound) {
    final bool takesSamp = RegExp(r'\bmainSound\s*\(\s*(in\s+)?int\b')
        .hasMatch(cleanUserCode);
    final callMainSound = takesSamp
        ? 'mainSound(samp, time)'
        : 'mainSound(time)';

    sb.writeln('''
void main() {
    float pixelIndex = floor(gl_FragCoord.x) + floor(gl_FragCoord.y) * ${soundTextureWidth.toDouble()};
    int samp = int(pixelIndex + iBlockOffset * iSampleRate);
    float time = float(samp) / iSampleRate;

    vec2 sound = $callMainSound;
    fragColor = vec4(sound.x, sound.y, 0.0, 1.0);
''');
  } else {
    sb.writeln('''
void main() {
    vec2 fragCoord = vec2(gl_FragCoord.x, iResolution.y - gl_FragCoord.y);
    mainImage(fragColor, fragCoord);
''');
  }

  sb.writeln('    if (iResolution.x < 0.0) {');
  sb.writeln('        fragColor += vec4(iTime);');
  for (final ch in declaredChannels) {
    sb.writeln('        fragColor += texture(iChannel$ch, vec2(0.0));');
  }
  sb.writeln('    }');

  sb.writeln('}');
  return sb.toString();
}

int _buildInput(
  fb.Builder b, {
  required String name,
  required int location,
  required int vecSize,
  required int offset,
}) {
  final nameOffset = b.writeString(name);
  b.startTable(9);
  b.addOffset(0, nameOffset);
  b.addUint32(1, location);
  b.addUint32(2, 0); // set
  b.addUint32(3, 0); // binding
  b.addUint32(4, sbg.InputDataType.kFloat.value);
  b.addUint32(5, 32); // bitWidth
  b.addUint32(6, vecSize);
  b.addUint32(7, 1); // columns
  b.addUint32(8, offset);
  return b.endTable();
}

int _buildField(
  fb.Builder b, {
  required String name,
  required int offsetInBytes,
  required int vecSize,
  required int totalSizeInBytes,
  sbg.UniformDataType type = sbg.UniformDataType.kFloat,
  int columns = 1,
  int arrayElements = 0,
}) {
  final nameOffset = b.writeString(name);
  b.startTable(8);
  b.addOffset(0, nameOffset);
  b.addUint32(1, type.value);
  b.addUint32(2, offsetInBytes);
  b.addUint32(3, 4); // elementSizeInBytes
  b.addUint32(4, totalSizeInBytes);
  b.addUint32(5, arrayElements);
  b.addUint32(6, vecSize);
  b.addUint32(7, columns);
  return b.endTable();
}

int _buildUniformStruct(
  fb.Builder b, {
  required String name,
  required int sizeInBytes,
  required List<int> fieldOffsets,
}) {
  final nameOffset = b.writeString(name);
  final fieldsOffset = b.writeList(fieldOffsets);
  b.startTable(6);
  b.addOffset(0, nameOffset);
  b.addUint32(1, 0); // extRes0
  b.addUint32(2, 0); // set
  b.addUint32(3, 0); // binding
  b.addUint32(4, sizeInBytes);
  b.addOffset(5, fieldsOffset);
  return b.endTable();
}

int _buildTexture(fb.Builder b, {required String name, required int binding}) {
  final nameOffset = b.writeString(name);
  b.startTable(4);
  b.addOffset(0, nameOffset);
  b.addUint32(1, 0); // extRes0
  b.addUint32(2, 0); // set
  b.addUint32(3, binding);
  return b.endTable();
}

int _buildBackendShader(
  fb.Builder b, {
  required sbg.ShaderStage stage,
  required String entrypoint,
  required Uint8List sourceBytes,
  List<int>? inputOffsets,
  List<int>? structOffsets,
  List<int>? textureOffsets,
}) {
  final entrypointOffset = b.writeString(entrypoint);
  final inputsOffset = inputOffsets != null ? b.writeList(inputOffsets) : null;
  final structsOffset = structOffsets != null
      ? b.writeList(structOffsets)
      : null;
  final texturesOffset = textureOffsets != null
      ? b.writeList(textureOffsets)
      : null;
  final shaderOffset = b.writeListUint8(sourceBytes);

  b.startTable(6);
  b.addInt8(0, stage.value);
  b.addOffset(1, entrypointOffset);
  b.addOffset(2, inputsOffset);
  b.addOffset(3, structsOffset);
  b.addOffset(4, texturesOffset);
  b.addOffset(5, shaderOffset);
  return b.endTable();
}

int _buildShader(
  fb.Builder b, {
  required String name,
  required int backendOffset,
}) {
  final nameOffset = b.writeString(name);
  b.startTable(6);
  b.addOffset(0, nameOffset);
  b.addOffset(1, null); // metalIos
  b.addOffset(2, null); // metalDesktop
  b.addOffset(3, backendOffset); // openglEs
  b.addOffset(4, null); // openglDesktop
  b.addOffset(5, null); // vulkan
  return b.endTable();
}

/// Builds an in-memory FlatBuffer .shaderbundle containing QuadVertex and
/// ShaderFragment with reflection metadata for WebGL2.
///
/// Uses 32-bit field serializers rather than 64-bit to remain 100% compatible
/// with `dart2js` on browsers (like Firefox) that do not support 64-bit `ByteData`
/// accessors. `flutter_scene`'s Web shader library deserializer only reads 32 bits
/// for reflection scalars, making this fully wire-compatible.
Uint8List _buildWebShaderBundle({
  required String vertexGlsl,
  required String fragmentGlsl,
  required List<int> channelIndices,
}) {
  final b = fb.Builder();
  final vertBytes = Uint8List.fromList(utf8.encode(vertexGlsl));
  final fragBytes = Uint8List.fromList(utf8.encode(fragmentGlsl));

  // 1. Vertex inputs: dynamically parsed from vertexGlsl, or default to position (vec2)
  final inputOffsets = <int>[];
  final inputMatches = RegExp(
    r'(?:layout\s*\(\s*location\s*=\s*(\d+)\s*\)\s*)?in\s+(float|vec2|vec3|vec4)\s+([A-Za-z0-9_]+)\s*;',
  ).allMatches(vertexGlsl);

  if (inputMatches.isNotEmpty) {
    int currentOffset = 0;
    int fallbackLocation = 0;
    for (final m in inputMatches) {
      final locStr = m.group(1);
      final location = locStr != null ? int.parse(locStr) : fallbackLocation;
      final typeStr = m.group(2)!;
      final name = m.group(3)!;
      final int vecSize = switch (typeStr) {
        'float' => 1,
        'vec2' => 2,
        'vec3' => 3,
        'vec4' => 4,
        _ => 2,
      };
      inputOffsets.add(
        _buildInput(
          b,
          name: name,
          location: location,
          vecSize: vecSize,
          offset: currentOffset,
        ),
      );
      currentOffset += vecSize * 4;
      fallbackLocation++;
    }
  } else {
    inputOffsets.add(
      _buildInput(
        b,
        name: 'position',
        location: 0,
        vecSize: 2,
        offset: 0,
      ),
    );
  }

  // 2. Uniform Struct: FrameInfo (std140 layout matching ShaderUniforms)
  final frameInfoFields = [
    _buildField(
      b,
      name: 'iResolution',
      offsetInBytes: 0,
      vecSize: 3,
      totalSizeInBytes: 12,
    ),
    _buildField(
      b,
      name: 'iTime',
      offsetInBytes: 12,
      vecSize: 1,
      totalSizeInBytes: 4,
    ),
    _buildField(
      b,
      name: 'iTimeDelta',
      offsetInBytes: 16,
      vecSize: 1,
      totalSizeInBytes: 4,
    ),
    _buildField(
      b,
      name: 'iFrameRate',
      offsetInBytes: 20,
      vecSize: 1,
      totalSizeInBytes: 4,
    ),
    _buildField(
      b,
      name: 'iFrame',
      offsetInBytes: 24,
      vecSize: 1,
      totalSizeInBytes: 4,
      type: sbg.UniformDataType.kSignedInt,
    ),
    _buildField(
      b,
      name: 'iMouse',
      offsetInBytes: 32,
      vecSize: 4,
      totalSizeInBytes: 16,
    ),
    _buildField(
      b,
      name: 'iDate',
      offsetInBytes: 48,
      vecSize: 4,
      totalSizeInBytes: 16,
    ),
    _buildField(
      b,
      name: 'iSampleRate',
      offsetInBytes: 64,
      vecSize: 1,
      totalSizeInBytes: 4,
    ),
    _buildField(
      b,
      name: 'iChannelResolution',
      offsetInBytes: 80,
      vecSize: 3,
      totalSizeInBytes: 64,
      arrayElements: 4,
    ),
    _buildField(
      b,
      name: 'iCustom',
      offsetInBytes: CommonUniforms.standardUniformsSizeBytes,
      vecSize: 4,
      totalSizeInBytes: CommonUniforms.customUniformsSizeBytes,
      arrayElements: CommonUniforms.maxCustomUniformSlots,
    ),
  ];

  final uniformStructOffset = _buildUniformStruct(
    b,
    name: 'FrameInfo',
    sizeInBytes: CommonUniforms.totalUniformBufferSize,
    fieldOffsets: frameInfoFields,
  );

  // 3. Vertex BackendShader
  final vertStructs =
      (vertexGlsl.contains('FrameInfo') || vertexGlsl.contains('iTime'))
      ? [uniformStructOffset]
      : null;
  final vertBackendOffset = _buildBackendShader(
    b,
    stage: sbg.ShaderStage.kVertex,
    entrypoint: 'main',
    sourceBytes: vertBytes,
    inputOffsets: inputOffsets,
    structOffsets: vertStructs,
  );
  final vertShaderOffset = _buildShader(
    b,
    name: 'QuadVertex',
    backendOffset: vertBackendOffset,
  );

  // 4. Fragment Uniform Textures (iChannel0..3)
  final texOffsets = channelIndices
      .map((ch) => _buildTexture(b, name: 'iChannel$ch', binding: ch))
      .toList();

  // 5. Fragment BackendShader
  final fragUsesFrameInfo =
      fragmentGlsl.contains('FrameInfo') ||
      fragmentGlsl.contains('iTime') ||
      fragmentGlsl.contains('iResolution');
  final fragStructs = fragUsesFrameInfo ? [uniformStructOffset] : null;

  final fragBackendOffset = _buildBackendShader(
    b,
    stage: sbg.ShaderStage.kFragment,
    entrypoint: 'main',
    sourceBytes: fragBytes,
    structOffsets: fragStructs,
    textureOffsets: texOffsets,
  );
  final fragShaderOffset = _buildShader(
    b,
    name: 'ShaderFragment',
    backendOffset: fragBackendOffset,
  );

  // 6. Root Bundle with QuadVertex and ShaderFragment
  final shadersOffset = b.writeList([vertShaderOffset, fragShaderOffset]);
  b.startTable(2);
  b.addOffset(0, shadersOffset);
  b.addUint32(1, 2); // formatVersion: 2
  final rootOffset = b.endTable();
  b.finish(rootOffset);
  return b.buffer;
}

/// Cleans WebGL2 shader compilation and linking error messages for display in UI.
String _cleanWebGlShaderError(String raw) {
  final sourceMarker = raw.indexOf('--- source ---');
  String logPart = sourceMarker != -1 ? raw.substring(0, sourceMarker) : raw;

  logPart = logPart.replaceFirst(
    RegExp(r'^Exception:\s*Failed to compile \w+ shader:\s*', multiLine: false),
    '',
  );
  logPart = logPart.replaceFirst(
    RegExp(
      r'^Exception:\s*Failed to link shader program:\s*',
      multiLine: false,
    ),
    '',
  );

  final lines = logPart.split('\n');
  final cleaned = <String>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      cleaned.add(trimmed);
    }
  }

  return cleaned.isNotEmpty ? cleaned.join('\n') : raw.trim();
}

/// Web-compatible runtime shader compilation using browser WebGL2 engine.
Future<CompileResult> runImpellerCompile({
  required String quadVertexShader,
  required String wrappedFragGlsl,
  String? customImpellercPath,
  String? rawUserGlsl,
  String? rawCommonGlsl,
  Map<String, int>? customUniformSlots,
  PassType passType = PassType.image,
  ShaderPassMode mode = ShaderPassMode.shaderToy,
}) async {
  try {
    final userCode = rawUserGlsl ?? wrappedFragGlsl;
    final codeForChannels =
        (rawCommonGlsl != null && rawCommonGlsl.trim().isNotEmpty)
        ? '$rawCommonGlsl\n$userCode'
        : userCode;

    final declaredChannels = <int>[];
    for (int i = 0; i < 4; i++) {
      if (ImpellerCompiler.shaderUsesChannel(codeForChannels, i)) {
        declaredChannels.add(i);
      }
    }

    final String vertGlslWeb;
    final String fragGlslWeb;

    if (mode == ShaderPassMode.custom) {
      String adaptToWebGlsl(String glsl, {bool isVertex = false}) {
        var res = glsl;
        if (res.contains('#version 460 core')) {
          res = res.replaceFirst(
            '#version 460 core',
            '#version 300 es\nprecision highp float;\nprecision highp int;\n',
          );
        } else if (!res.contains('#version 300 es')) {
          res =
              '#version 300 es\nprecision highp float;\nprecision highp int;\n$res';
        }
        if (isVertex && !res.contains('_impeller_y_flip')) {
          res = res.replaceFirst(
            '#version 300 es\n',
            '#version 300 es\nuniform float _impeller_y_flip;\n',
          );
        }

        // Clean layout qualifiers for WebGL2:
        // Strip `set = X` and `binding = Y` which are not supported in GLSL ES 3.00.
        res = res.replaceAllMapped(
          RegExp(r'layout\s*\(([^)]*)\)', multiLine: true),
          (match) {
            final content = match.group(1)!;
            final qualifiers = content
                .split(',')
                .map((q) => q.trim())
                .where((q) => q.isNotEmpty)
                .toList();

            final validQualifiers = qualifiers.where((q) {
              final lower = q.toLowerCase();
              return !lower.startsWith('set') && !lower.startsWith('binding');
            }).toList();

            if (validQualifiers.isEmpty) {
              return '';
            }
            return 'layout(${validQualifiers.join(', ')})';
          },
        );

        // Ensure uniform blocks in WebGL2 have layout(std140)
        res = res.replaceAllMapped(
          RegExp(
            r'(?:layout\s*\([^)]*\)\s*)?uniform\s+([A-Za-z0-9_]+)\s*\{',
            multiLine: true,
          ),
          (match) {
            final blockName = match.group(1)!;
            return 'layout(std140) uniform $blockName {';
          },
        );

        return res;
      }

      fragGlslWeb = adaptToWebGlsl(wrappedFragGlsl);
      vertGlslWeb = adaptToWebGlsl(quadVertexShader, isVertex: true);
    } else {
      vertGlslWeb = _quadVertexGlslWeb;
      fragGlslWeb = _wrapShaderGlslWeb(
        userGlsl: userCode,
        commonGlsl: rawCommonGlsl,
        declaredChannels: declaredChannels,
        customUniformSlots: customUniformSlots,
        passType: passType,
      );
    }

    final bundleBytes = _buildWebShaderBundle(
      vertexGlsl: vertGlslWeb,
      fragmentGlsl: fragGlslWeb,
      channelIndices: declaredChannels,
    );

    // On Web, validate compilation and linking against the browser WebGL2 context
    if (kIsWeb) {
      final byteData = ByteData.sublistView(bundleBytes);
      final lib = await gpu.loadShaderLibraryFromBytesAsync(byteData);
      if (lib == null) {
        return const CompileResult.error(
          'Failed to parse shader library on Web.',
        );
      }

      final vert = lib['QuadVertex'];
      final frag = lib['ShaderFragment'];
      if (vert != null && frag != null) {
        gpu.gpuContext.createRenderPipeline(vert, frag);
      }
    }

    return CompileResult.success(bundleBytes);
  } catch (e) {
    return CompileResult.error(_cleanWebGlShaderError(e.toString()));
  }
}
