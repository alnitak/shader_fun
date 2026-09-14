import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as sbg;
import 'package:shader_fun/shader_fun.dart';
import 'package:shader_fun/src/compiler/compile_process_web.dart';

void main() {
  test(
    'Web shader bundle compiles and produces valid FlatBuffer schema',
    () async {
      const userShader = '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 col = texture(iChannel0, uv);
    fragColor = vec4(col.rgb * sin(iTime), 1.0);
}
''';

      final result = await runImpellerCompile(
        quadVertexShader: '',
        wrappedFragGlsl: '',
        rawUserGlsl: userShader,
        rawCommonGlsl: null,
      );

      expect(result.isSuccess, isTrue, reason: result.errorMessage);
      expect(result.bundleBytes, isNotNull);

      final bundle = sbg.ShaderBundle(result.bundleBytes!);
      expect(bundle.formatVersion, 2);
      expect(bundle.shaders?.length, 2);

      final vert = bundle.shaders!.firstWhere((s) => s.name == 'QuadVertex');
      expect(vert.openglEs, isNotNull);
      expect(vert.openglEs!.stage.value, 0); // vertex
      expect(vert.openglEs!.inputs?.length, 1);
      expect(vert.openglEs!.inputs!.first.name, 'position');
      expect(vert.openglEs!.inputs!.first.location, 0);
      expect(vert.openglEs!.inputs!.first.vecSize, 2);

      final frag = bundle.shaders!.firstWhere(
        (s) => s.name == 'ShadertoyFragment',
      );
      expect(frag.openglEs, isNotNull);
      expect(frag.openglEs!.stage.value, 1); // fragment

      // FrameInfo struct
      expect(frag.openglEs!.uniformStructs?.length, 1);
      final frameInfo = frag.openglEs!.uniformStructs!.first;
      expect(frameInfo.name, 'FrameInfo');
      expect(frameInfo.sizeInBytes, CommonUniforms.totalUniformBufferSize);
      expect(frameInfo.fields?.length, 10);

      // Channel textures
      expect(frag.openglEs!.uniformTextures?.length, 1);
      expect(frag.openglEs!.uniformTextures!.first.name, 'iChannel0');

      // Shader source check
      final src = utf8.decode(frag.openglEs!.shader!);
      expect(src.contains('#version 300 es'), isTrue);
      expect(src.contains('layout(std140) uniform FrameInfo'), isTrue);
      expect(src.contains('uniform highp sampler2D iChannel0;'), isTrue);
      expect(src.contains('#define texture2D texture'), isTrue);
    },
  );
}
