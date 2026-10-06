import 'package:example/studio_example/widgets/studio_code_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight/languages/glsl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GlslCodeController', () {
    test('loadCode sets full text cleanly without prefix truncation', () {
      final controller = GlslCodeController(language: glsl);

      const code1 = '''
// Header comment in Shader 1
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(1.0, 0.0, 0.0, 1.0);
}
''';

      const code2 = '''
// Header comment in Shader 2 - completely different logic
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    fragColor = vec4(uv, 0.5, 1.0);
}
''';

      controller.loadCode(code1);
      expect(controller.fullText.trim(), code1.trim());
      expect(controller.selection.baseOffset, 0);
      expect(controller.loadCount, 1);

      controller.loadCode(code2);
      expect(controller.fullText.trim(), code2.trim());
      expect(
        controller.text.startsWith('// Header comment in Shader 2'),
        isTrue,
      );
      expect(controller.selection.baseOffset, 0);
      expect(controller.loadCount, 2);

      controller.dispose();
    });

    test('setting text property invokes loadCode without diff corruption', () {
      final controller = GlslCodeController(language: glsl);

      const initialCode = '''
/* Big comment header */
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(1.0);
}
''';

      const newCode = '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(0.0);
}
''';

      controller.text = initialCode;
      expect(controller.fullText.trim(), initialCode.trim());
      expect(controller.loadCount, 1);

      controller.text = newCode;
      expect(controller.fullText.trim(), newCode.trim());
      expect(controller.text.startsWith('void mainImage'), isTrue);
      expect(controller.loadCount, 2);

      controller.dispose();
    });

    test('unfolds previously folded blocks on new code load', () {
      final controller = GlslCodeController(language: glsl);

      const codeWithBlocks = '''
void helper() {
    float a = 1.0;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(1.0);
}
''';

      controller.loadCode(codeWithBlocks);
      // Fold the first block if present
      if (controller.code.foldableBlocks.isNotEmpty) {
        controller.foldAt(controller.code.foldableBlocks.first.firstLine);
        expect(controller.code.foldedBlocks, isNotEmpty);
      }

      const nextCode = '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(0.5);
}
''';

      controller.loadCode(nextCode);
      expect(controller.code.foldedBlocks, isEmpty);
      expect(controller.text, controller.fullText);

      controller.dispose();
    });

    test('regular value change (typing) does not increment loadCount', () {
      final controller = GlslCodeController(language: glsl);
      controller.loadCode('float x = 1.0;');
      final initialLoadCount = controller.loadCount;

      controller.value = const TextEditingValue(
        text: 'float x = 2.0;',
        selection: TextSelection.collapsed(offset: 14),
      );

      expect(controller.loadCount, initialLoadCount);

      controller.dispose();
    });
  });

  group('StudioCodeEditor Widget', () {
    testWidgets('renders CodeField with fresh Key when loadCount increments', (
      tester,
    ) async {
      final controller = GlslCodeController(language: glsl);
      controller.loadCode('void mainImage() {}');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioCodeEditor(
              codeController: controller,
              fontSize: 14.0,
              compileSuccess: true,
              compileStatus: 'Ready',
              hasError: false,
              lastError: null,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('code_field_1')), findsOneWidget);

      controller.loadCode('void mainImage() { /* updated */ }');
      await tester.pump();

      expect(find.byKey(const ValueKey('code_field_2')), findsOneWidget);

      controller.dispose();
    });
  });
}
