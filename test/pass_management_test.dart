import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/shader_fun.dart';

void main() {
  group('ShaderProject dynamic pass management', () {
    test('adds and removes tabs while keeping Image permanent', () {
      final project = ShaderProject.empty();
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

    test('loadProject completely replaces passes, deletes absent tabs, and sets Image as active', () async {
      final multiPassProject = ShaderProject(
        name: 'MultiPass',
        passes: [
          ShaderPass(
            type: PassType.common,
            name: 'Common',
            code: '// common 1',
          ),
          ShaderPass(
            type: PassType.bufferA,
            name: 'Buffer A',
            code: '// bufA 1',
          ),
          ShaderPass(
            type: PassType.bufferB,
            name: 'Buffer B',
            code: '// bufB 1',
          ),
          ShaderPass(type: PassType.image, name: 'Image', code: '// image 1'),
        ],
      );

      final controller = ShaderController(
        initialProject: multiPassProject,
        autoPlay: false,
      );

      expect(controller.project.passes.length, 4);
      expect(controller.project.hasPass(PassType.common), isTrue);
      expect(controller.project.hasPass(PassType.bufferA), isTrue);
      expect(controller.project.hasPass(PassType.bufferB), isTrue);
      expect(controller.project.hasPass(PassType.image), isTrue);
      expect(controller.activePass?.code, '// common 1');

      // Now load a single-pass project with completely different code
      final singlePassProject = ShaderProject(
        name: 'SinglePass',
        passes: [
          ShaderPass(
            type: PassType.image,
            name: 'Image',
            code: '// new image only',
          ),
        ],
      );

      await controller.loadProject(singlePassProject, autoCompile: false);

      // Verify that all absent passes were deleted:
      expect(controller.project.passes.length, 1);
      expect(controller.project.hasPass(PassType.common), isFalse);
      expect(controller.project.hasPass(PassType.bufferA), isFalse);
      expect(controller.project.hasPass(PassType.bufferB), isFalse);
      expect(controller.project.hasPass(PassType.image), isTrue);

      // Verify that the Image pass code was replaced:
      expect(controller.project.imagePass?.code, '// new image only');
      expect(controller.activePass?.code, '// new image only');
      expect(controller.activePassIndex, 0);

      // Now load back a 5-pass project (like Mouse Paint Eroded Mountains)
      final fivePassProject = ShaderProject(
        name: 'FivePass',
        passes: [
          ShaderPass(
            type: PassType.common,
            name: 'Common',
            code: '// new common',
          ),
          ShaderPass(
            type: PassType.bufferA,
            name: 'Buffer A',
            code: '// new bufA',
          ),
          ShaderPass(
            type: PassType.bufferB,
            name: 'Buffer B',
            code: '// new bufB',
          ),
          ShaderPass(
            type: PassType.bufferC,
            name: 'Buffer C',
            code: '// new bufC',
          ),
          ShaderPass(
            type: PassType.image,
            name: 'Image',
            code: '// new image 2',
          ),
        ],
      );

      await controller.loadProject(fivePassProject, autoCompile: false);

      expect(controller.project.passes.length, 5);
      expect(controller.project.hasPass(PassType.common), isTrue);
      expect(controller.project.hasPass(PassType.bufferA), isTrue);
      expect(controller.project.hasPass(PassType.bufferB), isTrue);
      expect(controller.project.hasPass(PassType.bufferC), isTrue);
      expect(controller.project.hasPass(PassType.image), isTrue);

      // Active pass should default to Image (index 4)
      expect(controller.activePassIndex, 4);
      expect(controller.activePass?.type, PassType.image);
      expect(controller.activePass?.code, '// new image 2');

      controller.dispose();
    });

    test('parses and serializes url in Shader.info', () {
      final json = {
        'Shader': {
          'ver': '0.1',
          'info': {
            'id': 'sf23W1',
            'name': 'Mouse-Paint Eroded Mountains',
            'url': 'https://www.shadertoy.com/view/sf23W1',
          },
          'renderpass': [
            {
              'name': 'Image',
              'type': 'image',
              'code':
                  'void mainImage(out vec4 c, in vec2 f) { c = vec4(1.0); }',
            },
          ],
        },
      };

      final project = ShaderProject.fromJson(json);
      expect(project.url, 'https://www.shadertoy.com/view/sf23W1');

      final serialized = project.toJson();
      final info = (serialized['Shader'] as Map)['info'] as Map;
      expect(info['url'], 'https://www.shadertoy.com/view/sf23W1');
    });
  });
}
