import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/shader_fun.dart';

void main() {
  group('ShaderToyProject dynamic pass management', () {
    test('adds and removes tabs while keeping Image permanent', () {
      final project = ShaderToyProject.empty();
      expect(project.passes.length, 1);
      expect(project.imagePass, isNotNull);

      // Cannot remove Image pass
      expect(project.removePass(PassType.image), isFalse);
      expect(project.passes.length, 1);

      // Add Common pass
      final common = project.addPass(PassType.common);
      expect(common, isNotNull);
      expect(project.hasPass(PassType.common), isTrue);

      // Add Buffer A and Buffer B
      final bufA = project.addPass(PassType.bufferA);
      expect(bufA, isNotNull);
      final bufB = project.addPass(PassType.bufferB);
      expect(bufB, isNotNull);

      // Verify pass order: Common -> Buffer A -> Buffer B -> Image
      expect(project.passes[0].type, PassType.common);
      expect(project.passes[1].type, PassType.bufferA);
      expect(project.passes[2].type, PassType.bufferB);
      expect(project.passes[3].type, PassType.image);

      // Remove Buffer A
      expect(project.removePass(PassType.bufferA), isTrue);
      expect(project.hasPass(PassType.bufferA), isFalse);

      // Remove Buffer B
      expect(project.removePass(PassType.bufferB), isTrue);
      expect(project.hasPass(PassType.bufferB), isFalse);

      expect(project.passes.length, 2);
    });
  });
}
