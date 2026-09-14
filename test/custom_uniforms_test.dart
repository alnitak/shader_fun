import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/shader_fun.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Custom Uniforms', () {
    test('ShaderToyUniforms buffer constants and size consistency', () {
      expect(
        CommonUniforms.customUniformsSizeBytes,
        CommonUniforms.maxCustomUniformSlots * 16,
      );
      expect(
        CommonUniforms.totalUniformBufferSize,
        CommonUniforms.standardUniformsSizeBytes +
            CommonUniforms.customUniformsSizeBytes,
      );
    });

    test('ShaderToyUniforms stores and packs custom uniform types', () {
      final uniforms = CommonUniforms();

      uniforms.setCustomUniform('progress', 0.75);
      uniforms.setCustomUniform('count', 42);
      uniforms.setCustomUniform('center', const Offset(0.5, 0.25));
      uniforms.setCustomUniform('dimensions', const Size(1920, 1080));
      uniforms.setCustomUniform('tint', const Color.fromARGB(255, 255, 128, 0));

      expect(uniforms.getCustomUniform('progress'), 0.75);
      expect(uniforms.getCustomUniform('count'), 42);
      expect(uniforms.getCustomUniform('center'), const Offset(0.5, 0.25));
      expect(uniforms.getCustomUniform('dimensions'), const Size(1920, 1080));

      final progressSlot = uniforms.getOrAssignSlot('progress');
      expect(uniforms.customData[progressSlot * 4], closeTo(0.75, 0.0001));

      final centerSlot = uniforms.getOrAssignSlot('center');
      expect(uniforms.customData[centerSlot * 4], closeTo(0.5, 0.0001));
      expect(uniforms.customData[centerSlot * 4 + 1], closeTo(0.25, 0.0001));

      final tintSlot = uniforms.getOrAssignSlot('tint');
      expect(uniforms.customData[tintSlot * 4], closeTo(1.0, 0.0001)); // r
      expect(
        uniforms.customData[tintSlot * 4 + 1],
        closeTo(128 / 255.0, 0.01),
      ); // g
      expect(uniforms.customData[tintSlot * 4 + 2], closeTo(0.0, 0.0001)); // b
      expect(uniforms.customData[tintSlot * 4 + 3], closeTo(1.0, 0.0001)); // a
    });

    test('ImpellerCompiler extracts and wraps custom uniforms', () {
      const glsl = '''
uniform float progress;
uniform vec2 focusPoint;
uniform vec4 glowColor;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = glowColor * progress;
}
''';

      final extracted = ImpellerCompiler.extractCustomUniforms(glsl);
      expect(extracted.length, 3);
      expect(extracted[0].name, 'progress');
      expect(extracted[0].type, 'float');
      expect(extracted[1].name, 'focusPoint');
      expect(extracted[1].type, 'vec2');
      expect(extracted[2].name, 'glowColor');
      expect(extracted[2].type, 'vec4');

      final wrapped = ImpellerCompiler.wrapShaderGlsl(glsl);
      expect(wrapped, contains('vec4 iCustom[16];'));
      expect(wrapped, contains('#define progress (iCustom[0].x)'));
      expect(wrapped, contains('#define focusPoint (iCustom[1].xy)'));
      expect(wrapped, contains('#define glowColor (iCustom[2])'));
      // Verifies original bare uniform lines are sanitized/commented out
      expect(wrapped, contains('// uniform float progress;'));
    });

    test('ShaderToyController setUniform updates uniforms without error', () {
      final project = ShaderProject(
        name: 'Uniform Test',
        passes: [
          ShaderPass(
            name: 'Image',
            type: PassType.image,
            code: '''
uniform float progress;
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(progress);
}
''',
          ),
        ],
      );

      final controller = ShaderController(initialProject: project);
      controller.setUniform('progress', 0.85);

      expect(controller.getUniform('progress'), 0.85);
      expect(controller.customUniforms['progress'], 0.85);
      controller.dispose();
    });
  });
}
