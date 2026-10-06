import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as sbg;
import 'package:shader_fun/shader_fun.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Custom Vertex & Fragment Shader Support', () {
    test('ShaderPass defaults to shaderToy mode and 6 vertices', () {
      final pass = ShaderPass(
        type: PassType.image,
        name: 'Image',
        code: 'void mainImage(out vec4 fragColor, in vec2 fragCoord) {}',
      );

      expect(pass.mode, ShaderPassMode.shaderToy);
      expect(pass.vertexCode, isNull);
      expect(pass.vertexCount, 6);
      expect(pass.customVertices, isNull);
    });

    test(
      'ShaderPass custom mode with custom vertex code and triangle vertices',
      () {
        final triangleVertices = Float32List.fromList([
          -0.5,
          -0.5,
          0.5,
          -0.5,
          0.0,
          0.5,
        ]);

        final pass = ShaderPass(
          type: PassType.image,
          name: 'Custom Triangle',
          mode: ShaderPassMode.custom,
          vertexCount: 3,
          customVertices: triangleVertices,
          vertexCode: '''#version 460 core
layout(location = 0) in vec2 position;
void main() {
    gl_Position = vec4(position, 0.0, 1.0);
}
''',
          code: '''#version 460 core
layout(location = 0) out vec4 fragColor;
void main() {
    fragColor = vec4(1.0, 0.0, 0.0, 1.0);
}
''',
        );

        expect(pass.mode, ShaderPassMode.custom);
        expect(
          pass.vertexCode,
          contains('layout(location = 0) in vec2 position'),
        );
        expect(pass.vertexCount, 3);
        expect(pass.customVertices, triangleVertices);
      },
    );

    test('ShaderCodeEvaluator.validate allows main() in custom mode', () {
      const customCode = '''
#version 460 core
layout(location = 0) out vec4 fragColor;
void main() {
    fragColor = vec4(0.0, 1.0, 0.0, 1.0);
}
''';

      // Under ShaderToy mode, missing mainImage returns an error
      final shaderToyError = ShaderCodeEvaluator.validate(
        customCode,
        mode: ShaderPassMode.shaderToy,
      );
      expect(shaderToyError, contains('Missing mainImage function'));

      // Under Custom mode, valid main() succeeds
      final customError = ShaderCodeEvaluator.validate(
        customCode,
        mode: ShaderPassMode.custom,
      );
      expect(customError, isNull);
    });

    test(
      'ShaderProject JSON serialization preserves custom pass properties',
      () {
        final triangleVertices = Float32List.fromList([
          -0.2,
          -0.2,
          0.2,
          -0.2,
          0.0,
          0.3,
        ]);

        final project = ShaderProject(
          name: 'Custom Pipeline Test',
          passes: [
            ShaderPass(
              type: PassType.bufferA,
              name: 'ShaderToy Background',
              code: 'void mainImage(out vec4 fragColor, in vec2 fragCoord) { fragColor = vec4(1.0); }',
            ),
            ShaderPass(
              type: PassType.image,
              name: 'Custom Triangle',
              mode: ShaderPassMode.custom,
              vertexCount: 3,
              customVertices: triangleVertices,
              vertexCode: 'void main() { gl_Position = vec4(0.0); }',
              code: 'void main() { fragColor = vec4(0.5); }',
            ),
          ],
        );

        final jsonMap = project.toJson();
        final jsonString = jsonEncode(jsonMap);
        final decodedProject = ShaderProject.fromJson(
          jsonDecode(jsonString) as Map<String, dynamic>,
        );

        expect(decodedProject.passes.length, 2);

        final pass1 = decodedProject.passes[0];
        expect(pass1.mode, ShaderPassMode.shaderToy);
        expect(pass1.name, 'ShaderToy Background');

        final pass2 = decodedProject.passes[1];
        expect(pass2.mode, ShaderPassMode.custom);
        expect(pass2.name, 'Custom Triangle');
        expect(pass2.vertexCount, 3);
        expect(pass2.customVertices, isNotNull);
        expect(pass2.customVertices!.length, 6);
        expect(pass2.vertexCode, contains('gl_Position'));
      },
    );

    test(
      'ImpellerCompiler compiles raw custom vertex and fragment shaders',
      () async {
        const vertCode = '''#version 460 core
layout(location = 0) in vec2 position;
void main() {
    gl_Position = vec4(position, 0.0, 1.0);
}
''';

        const fragCode = '''#version 460 core
layout(location = 0) out vec4 fragColor;
void main() {
    fragColor = vec4(0.2, 0.4, 0.8, 1.0);
}
''';

        final res = await ImpellerCompiler.compile(
          shaderGlsl: fragCode,
          vertexGlsl: vertCode,
          mode: ShaderPassMode.custom,
        );

        expect(
          res.isSuccess,
          isTrue,
          reason: 'Compilation failed: ${res.errorMessage}',
        );
        expect(res.bundleBytes, isNotNull);
      },
    );

    test('Moving triangle vertex shader with FrameInfo compiles', () async {
      const vertCode = '''#version 460 core
layout(location = 0) in vec2 position;

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
    vec4 iCustom[16];
};

out vec2 v_uv;

void main() {
    v_uv = position * 0.5 + 0.5;
    vec2 offset = vec2(sin(iTime * 1.5) * 0.45, cos(iTime * 2.0) * 0.35);
    vec2 pos = position * 0.4 + offset;
    gl_Position = vec4(pos, 0.0, 1.0);
}
''';

      const fragCode = '''#version 460 core
precision highp float;

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
    vec4 iCustom[16];
};

layout(set = 0, binding = 1) uniform sampler2D iChannel0;

in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

void main() {
    vec2 screenUv = gl_FragCoord.xy / iResolution.xy;
    vec4 bg = texture(iChannel0, screenUv);
    fragColor = vec4(bg.rgb + vec3(v_uv, 0.5), 1.0);
}
''';

      final res = await ImpellerCompiler.compile(
        shaderGlsl: fragCode,
        vertexGlsl: vertCode,
        mode: ShaderPassMode.custom,
      );

      expect(res.isSuccess, isTrue, reason: res.errorMessage);

      final bundle = sbg.ShaderBundle(res.bundleBytes!);
      final fragShader = bundle.shaders!.firstWhere(
        (s) => s.name == 'ShaderFragment',
      );
      final fragBackend =
          fragShader.metalDesktop ?? fragShader.openglEs ?? fragShader.vulkan;
      // ignore: avoid_print
      print(
        'Frag uniformTextures: ${fragBackend?.uniformTextures?.map((t) => '${t.name}@${t.binding}').toList()}',
      );
      // ignore: avoid_print
      print(
        'Frag uniformStructs: ${fragBackend?.uniformStructs?.map((u) => '${u.name}@${u.binding} (size ${u.sizeInBytes})').toList()}',
      );
    });
  });
}
