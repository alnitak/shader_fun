import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flat_buffers/flat_buffers.dart' as fb;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as sbg;
import 'package:shader_fun/src/compiler/compile_process_web.dart' as web_compiler;
import 'package:shader_fun/src/core/shader_pass.dart';

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
  int columns = 1,
  int arrayElements = 0,
}) {
  final nameOffset = b.writeString(name);
  b.startTable(8);
  b.addOffset(0, nameOffset);
  b.addUint32(1, sbg.UniformDataType.kFloat.value);
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

Uint8List buildWebShaderBundleTest({
  required String vertexGlsl,
  required String fragmentGlsl,
  required List<int> channelIndices,
}) {
  final b = fb.Builder();
  final vertBytes = Uint8List.fromList(utf8.encode(vertexGlsl));
  final fragBytes = Uint8List.fromList(utf8.encode(fragmentGlsl));

  // Vertex shader
  final vertInputOffset = _buildInput(
    b,
    name: 'position',
    location: 0,
    vecSize: 2,
    offset: 0,
  );
  final vertBackend = _buildBackendShader(
    b,
    stage: sbg.ShaderStage.kVertex,
    entrypoint: 'main',
    sourceBytes: vertBytes,
    inputOffsets: [vertInputOffset],
  );
  final vertShader = _buildShader(
    b,
    name: 'QuadVertex',
    backendOffset: vertBackend,
  );

  // Fragment shader
  final fieldOffsets = [
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
  ];
  final structOffset = _buildUniformStruct(
    b,
    name: 'FrameInfo',
    sizeInBytes: 16,
    fieldOffsets: fieldOffsets,
  );
  final texOffsets = channelIndices
      .map((ch) => _buildTexture(b, name: 'iChannel$ch', binding: ch))
      .toList();

  final fragBackend = _buildBackendShader(
    b,
    stage: sbg.ShaderStage.kFragment,
    entrypoint: 'main',
    sourceBytes: fragBytes,
    structOffsets: [structOffset],
    textureOffsets: texOffsets,
  );
  final fragShader = _buildShader(
    b,
    name: 'ShaderFragment',
    backendOffset: fragBackend,
  );

  final shadersOffset = b.writeList([vertShader, fragShader]);
  b.startTable(2);
  b.addOffset(0, shadersOffset);
  b.addUint32(1, 2); // formatVersion: 2
  final rootOffset = b.endTable();
  b.finish(rootOffset);
  return b.buffer;
}

void main() {
  test(
    'Web-safe FlatBuffer reader correctly decodes bundle without Uint64 calls',
    () {
      final bundleBytes = buildWebShaderBundleTest(
        vertexGlsl: 'void main() {}',
        fragmentGlsl: 'void main() {}',
        channelIndices: [0, 1],
      );

      final bundle = sbg.ShaderBundle(bundleBytes);
      expect(bundle.formatVersion, equals(2));
      expect(bundle.shaders?.length, equals(2));

      final quadVert = bundle.shaders!.firstWhere(
        (s) => s.name == 'QuadVertex',
      );
      expect(quadVert.openglEs?.entrypoint, equals('main'));
      expect(quadVert.openglEs?.inputs?.length, equals(1));
      expect(quadVert.openglEs?.inputs![0].name, equals('position'));
      expect(quadVert.openglEs?.inputs![0].vecSize, equals(2));

      final frag = bundle.shaders!.firstWhere(
        (s) => s.name == 'ShaderFragment',
      );
      expect(frag.openglEs?.entrypoint, equals('main'));
      expect(frag.openglEs?.uniformStructs?.length, equals(1));
      expect(frag.openglEs?.uniformStructs![0].name, equals('FrameInfo'));
      expect(frag.openglEs?.uniformStructs![0].fields?.length, equals(2));
      expect(
        frag.openglEs?.uniformStructs![0].fields![0].name,
        equals('iResolution'),
      );
      expect(
        frag.openglEs?.uniformStructs![0].fields![0].offsetInBytes,
        equals(0),
      );
      expect(frag.openglEs?.uniformTextures?.length, equals(2));
      expect(frag.openglEs?.uniformTextures![0].name, equals('iChannel0'));
      expect(frag.openglEs?.uniformTextures?[1].name, equals('iChannel1'));
    },
  );

  test(
    'runImpellerCompile for Web adapts custom GLSL 460 shaders with set/binding and multi-attributes',
    () async {
      const vertGlsl = '''#version 460 core
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;

layout(std140, set = 0, binding = 0) uniform FrameInfo {
    vec3 iResolution;
    float iTime;
};

void main() {
    gl_Position = vec4(position + normal * 0.1, 1.0);
}
''';

      const fragGlsl = '''#version 460 core
precision highp float;

layout(std140, set = 0, binding = 0) uniform FrameInfo {
    vec3 iResolution;
    float iTime;
};

layout(binding = 0) uniform sampler2D iChannel0;
layout(location = 0) out vec4 fragColor;

void main() {
    fragColor = texture(iChannel0, vec2(0.5)) + vec4(iTime);
}
''';

      final result = await web_compiler.runImpellerCompile(
        quadVertexShader: vertGlsl,
        wrappedFragGlsl: fragGlsl,
        mode: ShaderPassMode.custom,
      );

      expect(result.isSuccess, isTrue);
      expect(result.bundleBytes, isNotNull);

      final bundle = sbg.ShaderBundle(result.bundleBytes!);
      expect(bundle.formatVersion, equals(2));
      expect(bundle.shaders?.length, equals(2));

      final vert = bundle.shaders!.firstWhere((s) => s.name == 'QuadVertex');
      final vertGlslDecoded = utf8.decode(vert.openglEs!.shader!);
      expect(vertGlslDecoded, contains('#version 300 es'));
      expect(vertGlslDecoded, contains('layout(std140) uniform FrameInfo'));
      expect(vertGlslDecoded, isNot(contains('set = 0')));
      expect(vertGlslDecoded, isNot(contains('binding = 0')));

      // Verify two vertex attributes: position (vec3) at offset 0, normal (vec3) at offset 12
      expect(vert.openglEs?.inputs?.length, equals(2));
      expect(vert.openglEs?.inputs![0].name, equals('position'));
      expect(vert.openglEs?.inputs![0].location, equals(0));
      expect(vert.openglEs?.inputs![0].vecSize, equals(3));
      expect(vert.openglEs?.inputs![0].offset, equals(0));

      expect(vert.openglEs?.inputs![1].name, equals('normal'));
      expect(vert.openglEs?.inputs![1].location, equals(1));
      expect(vert.openglEs?.inputs![1].vecSize, equals(3));
      expect(vert.openglEs?.inputs![1].offset, equals(12));

      final frag = bundle.shaders!.firstWhere((s) => s.name == 'ShaderFragment');
      final fragGlslDecoded = utf8.decode(frag.openglEs!.shader!);
      expect(fragGlslDecoded, contains('#version 300 es'));
      expect(fragGlslDecoded, contains('layout(std140) uniform FrameInfo'));
      expect(fragGlslDecoded, contains('uniform sampler2D iChannel0'));
      expect(fragGlslDecoded, isNot(contains('binding = 0')));
      expect(fragGlslDecoded, isNot(contains('set = 0')));
    },
  );
}
