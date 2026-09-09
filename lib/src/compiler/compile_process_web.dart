import 'dart:convert';

import 'package:flutter/foundation.dart';

// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as sbg;
import 'package:flat_buffers/flat_buffers.dart' as fb;
import '../core/shadertoy_uniforms.dart';
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

/// Wraps Shadertoy GLSL code into modern WebGL2 GLSL ES 3.00 with
/// std140 uniform block, sampler bindings, compatibility definitions,
/// and main() entrypoint.
String _wrapShadertoyGlslWeb({
  required String userGlsl,
  String? commonGlsl,
  required List<int> declaredChannels,
  Map<String, int>? customUniformSlots,
}) {
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
    // ${ShaderToyUniforms.maxCustomUniformSlots} vec4 registers = ${ShaderToyUniforms.customUniformsSizeBytes} bytes reserved for custom uniforms.
    // Total FrameInfo buffer size: ${ShaderToyUniforms.totalUniformBufferSize} bytes.
    vec4 iCustom[${ShaderToyUniforms.maxCustomUniformSlots}];
};
''');

  final codeForUniforms =
      (commonGlsl != null && commonGlsl.trim().isNotEmpty)
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
  final sanitizedCommonGlsl =
      commonGlsl != null ? sanitizeUniforms(commonGlsl) : null;

  for (final ch in declaredChannels) {
    sb.writeln('uniform highp sampler2D iChannel$ch;');
  }

  sb.writeln('layout(location = 0) out highp vec4 fragColor;');
  sb.writeln();

  // Backward compatibility aliases for older Shadertoy GLSL
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

void main() {
    vec2 fragCoord = vec2(gl_FragCoord.x, iResolution.y - gl_FragCoord.y);
    mainImage(fragColor, fragCoord);''');

  sb.writeln('    if (iResolution.x < 0.0) {');
  sb.writeln('        fragColor += vec4(iTime);');
  for (final ch in declaredChannels) {
    sb.writeln('        fragColor += texture(iChannel$ch, vec2(0.0));');
  }
  sb.writeln('    }');

  sb.writeln('}');
  return sb.toString();
}

/// Builds an in-memory FlatBuffer .shaderbundle containing QuadVertex and
/// ShadertoyFragment with reflection metadata for WebGL2.
Uint8List _buildWebShaderBundle({
  required String vertexGlsl,
  required String fragmentGlsl,
  required List<int> channelIndices,
}) {
  final vertBytes = Uint8List.fromList(utf8.encode(vertexGlsl));
  final fragBytes = Uint8List.fromList(utf8.encode(fragmentGlsl));

  // 1. Vertex inputs for QuadVertex: position attribute (location 0, vecSize 2)
  final vertexInputs = [
    sbg.ShaderInputObjectBuilder(
      name: 'position',
      location: 0,
      vecSize: 2,
      offset: 0,
      type: sbg.InputDataType.kFloat,
    ),
  ];

  // 2. Vertex BackendShader
  final vertBackend = sbg.BackendShaderObjectBuilder(
    entrypoint: 'main',
    stage: sbg.ShaderStage.kVertex,
    shader: vertBytes,
    inputs: vertexInputs,
  );

  // 3. Fragment Uniform Struct: FrameInfo (std140 layout matching ShaderToyUniforms)
  final frameInfoFields = [
    sbg.ShaderUniformStructFieldObjectBuilder(
      name: 'iResolution',
      offsetInBytes: 0,
      vecSize: 3,
      columns: 1,
      arrayElements: 0,
      totalSizeInBytes: 12,
      type: sbg.UniformDataType.kFloat,
    ),
    sbg.ShaderUniformStructFieldObjectBuilder(
      name: 'iTime',
      offsetInBytes: 12,
      vecSize: 1,
      columns: 1,
      arrayElements: 0,
      totalSizeInBytes: 4,
      type: sbg.UniformDataType.kFloat,
    ),
    sbg.ShaderUniformStructFieldObjectBuilder(
      name: 'iTimeDelta',
      offsetInBytes: 16,
      vecSize: 1,
      columns: 1,
      arrayElements: 0,
      totalSizeInBytes: 4,
      type: sbg.UniformDataType.kFloat,
    ),
    sbg.ShaderUniformStructFieldObjectBuilder(
      name: 'iFrameRate',
      offsetInBytes: 20,
      vecSize: 1,
      columns: 1,
      arrayElements: 0,
      totalSizeInBytes: 4,
      type: sbg.UniformDataType.kFloat,
    ),
    sbg.ShaderUniformStructFieldObjectBuilder(
      name: 'iFrame',
      offsetInBytes: 24,
      vecSize: 1,
      columns: 1,
      arrayElements: 0,
      totalSizeInBytes: 4,
      type: sbg.UniformDataType.kSignedInt,
    ),
    sbg.ShaderUniformStructFieldObjectBuilder(
      name: 'iMouse',
      offsetInBytes: 32,
      vecSize: 4,
      columns: 1,
      arrayElements: 0,
      totalSizeInBytes: 16,
      type: sbg.UniformDataType.kFloat,
    ),
    sbg.ShaderUniformStructFieldObjectBuilder(
      name: 'iDate',
      offsetInBytes: 48,
      vecSize: 4,
      columns: 1,
      arrayElements: 0,
      totalSizeInBytes: 16,
      type: sbg.UniformDataType.kFloat,
    ),
    sbg.ShaderUniformStructFieldObjectBuilder(
      name: 'iSampleRate',
      offsetInBytes: 64,
      vecSize: 1,
      columns: 1,
      arrayElements: 0,
      totalSizeInBytes: 4,
      type: sbg.UniformDataType.kFloat,
    ),
    sbg.ShaderUniformStructFieldObjectBuilder(
      name: 'iChannelResolution',
      offsetInBytes: 80,
      vecSize: 3,
      columns: 1,
      arrayElements: 4,
      totalSizeInBytes: 64,
      type: sbg.UniformDataType.kFloat,
    ),
    sbg.ShaderUniformStructFieldObjectBuilder(
      name: 'iCustom',
      offsetInBytes: ShaderToyUniforms.standardUniformsSizeBytes,
      vecSize: 4,
      columns: 1,
      arrayElements: ShaderToyUniforms.maxCustomUniformSlots,
      totalSizeInBytes: ShaderToyUniforms.customUniformsSizeBytes,
      type: sbg.UniformDataType.kFloat,
    ),
  ];

  final uniformStructs = [
    sbg.ShaderUniformStructObjectBuilder(
      name: 'FrameInfo',
      sizeInBytes: ShaderToyUniforms.totalUniformBufferSize,
      fields: frameInfoFields,
    ),
  ];

  // 4. Fragment Uniform Textures (iChannel0..3)
  final uniformTextures = channelIndices.map((ch) {
    return sbg.ShaderUniformTextureObjectBuilder(
      name: 'iChannel$ch',
    );
  }).toList();

  // 5. Fragment BackendShader
  final fragBackend = sbg.BackendShaderObjectBuilder(
    entrypoint: 'main',
    stage: sbg.ShaderStage.kFragment,
    shader: fragBytes,
    uniformStructs: uniformStructs,
    uniformTextures: uniformTextures,
  );

  // 6. Root Bundle with QuadVertex and ShadertoyFragment
  final bundleObj = sbg.ShaderBundleObjectBuilder(
    formatVersion: 2,
    shaders: [
      sbg.ShaderObjectBuilder(
        name: 'QuadVertex',
        openglEs: vertBackend,
      ),
      sbg.ShaderObjectBuilder(
        name: 'ShadertoyFragment',
        openglEs: fragBackend,
      ),
    ],
  );

  final builder = fb.Builder();
  final offset = bundleObj.finish(builder);
  builder.finish(offset);
  return builder.buffer;
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
    RegExp(r'^Exception:\s*Failed to link shader program:\s*', multiLine: false),
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
}) async {
  try {
    final userCode = rawUserGlsl ?? wrappedFragGlsl;
    final codeForChannels = (rawCommonGlsl != null && rawCommonGlsl.trim().isNotEmpty)
        ? '$rawCommonGlsl\n$userCode'
        : userCode;

    final declaredChannels = <int>[];
    for (int i = 0; i < 4; i++) {
      if (ImpellerCompiler.shaderUsesChannel(codeForChannels, i)) {
        declaredChannels.add(i);
      }
    }

    final fragGlslWeb = _wrapShadertoyGlslWeb(
      userGlsl: userCode,
      commonGlsl: rawCommonGlsl,
      declaredChannels: declaredChannels,
      customUniformSlots: customUniformSlots,
    );

    final bundleBytes = _buildWebShaderBundle(
      vertexGlsl: _quadVertexGlslWeb,
      fragmentGlsl: fragGlslWeb,
      channelIndices: declaredChannels,
    );

    // On Web, validate compilation and linking against the browser WebGL2 context
    if (kIsWeb) {
      final byteData = ByteData.sublistView(bundleBytes);
      final lib = await gpu.loadShaderLibraryFromBytesAsync(byteData);
      if (lib == null) {
        return const CompileResult.error('Failed to parse shader library on Web.');
      }

      final vert = lib['QuadVertex'];
      final frag = lib['ShadertoyFragment'];
      if (vert != null && frag != null) {
        gpu.gpuContext.createRenderPipeline(vert, frag);
      }
    }

    return CompileResult.success(bundleBytes);
  } catch (e) {
    return CompileResult.error(_cleanWebGlShaderError(e.toString()));
  }
}
