import 'package:example/studio_example/widgets/studio_code_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    test('insertStr and Enter do not increment loadCount and preserve cursor', () {
      final controller = GlslCodeController(language: glsl);
      controller.loadCode('float x = 1.0;\nfloat y = 2.0;');
      final initialLoadCount = controller.loadCount;

      // Position cursor at end of line 1
      controller.selection = const TextSelection.collapsed(offset: 14);

      // Simulates pressing Enter
      controller.onEnterKeyAction();

      // loadCount must NOT increment (preventing scroll reset to line 1)
      expect(controller.loadCount, initialLoadCount);
      // Cursor must have advanced to new line (not reset to 0)
      expect(controller.selection.baseOffset, greaterThan(14));
      expect(controller.text.contains('\n'), isTrue);

      controller.dispose();
    });

    test('onKey handles Tab key without losing focus and indents', () {
      final controller = GlslCodeController(language: glsl);
      controller.loadCode('float x = 1.0;');
      final initialLoadCount = controller.loadCount;

      controller.selection = const TextSelection.collapsed(offset: 0);

      // Simulate pressing Tab key
      final result = controller.onKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.tab,
          logicalKey: LogicalKeyboardKey.tab,
          timeStamp: Duration.zero,
        ),
      );

      // Must be handled so Flutter FocusTraversalGroup does not steal focus
      expect(result, KeyEventResult.handled);
      expect(controller.loadCount, initialLoadCount);
      // Indentation spaces should have been inserted
      expect(controller.text.startsWith('  float x = 1.0;'), isTrue);
      expect(controller.selection.baseOffset, 2);

      controller.dispose();
    });

    test('onKey handles Shift+Tab to outdent and returns handled', () async {
      final controller = GlslCodeController(language: glsl);
      controller.loadCode('  float x = 1.0;');
      final initialLoadCount = controller.loadCount;

      controller.selection = const TextSelection.collapsed(offset: 2);

      // Simulate Shift key down in hardware
      await simulateKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      final result = controller.onKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.tab,
          logicalKey: LogicalKeyboardKey.tab,
          timeStamp: Duration.zero,
        ),
      );

      await simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(result, KeyEventResult.handled);
      expect(controller.text, 'float x = 1.0;');
      expect(controller.loadCount, initialLoadCount);

      controller.dispose();
    });

    test('onKey handles Numpad Enter identically to Enter', () {
      final controller = GlslCodeController(language: glsl);
      controller.loadCode('float x = 1.0;');
      final initialLoadCount = controller.loadCount;

      controller.selection = const TextSelection.collapsed(offset: 14);

      final result = controller.onKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.numpadEnter,
          logicalKey: LogicalKeyboardKey.numpadEnter,
          timeStamp: Duration.zero,
        ),
      );

      expect(result, KeyEventResult.handled);
      expect(controller.loadCount, initialLoadCount);
      expect(controller.selection.baseOffset, greaterThan(14));

      controller.dispose();
    });

    test('onKey handles Home key: jumps to indent, then column 0', () {
      final controller = GlslCodeController(language: glsl);
      controller.loadCode('    float x = 1.0;');
      // Position cursor at end of line (offset 18)
      controller.selection = const TextSelection.collapsed(offset: 18);

      // First press of Home: jumps to first non-whitespace (offset 4)
      final result1 = controller.onKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.home,
          logicalKey: LogicalKeyboardKey.home,
          timeStamp: Duration.zero,
        ),
      );
      expect(result1, KeyEventResult.handled);
      expect(controller.selection.extentOffset, 4);

      // Second press of Home (already at non-whitespace): jumps to column 0
      final result2 = controller.onKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.home,
          logicalKey: LogicalKeyboardKey.home,
          timeStamp: Duration.zero,
        ),
      );
      expect(result2, KeyEventResult.handled);
      expect(controller.selection.extentOffset, 0);

      controller.dispose();
    });

    test('onKey handles End key: jumps to end of current line', () {
      final controller = GlslCodeController(language: glsl);
      controller.loadCode('    float x = 1.0;\n    float y = 2.0;');
      // Position cursor at start of line 1 (offset 4)
      controller.selection = const TextSelection.collapsed(offset: 4);

      final result = controller.onKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.end,
          logicalKey: LogicalKeyboardKey.end,
          timeStamp: Duration.zero,
        ),
      );
      expect(result, KeyEventResult.handled);
      // Line 1 ends at offset 18 (before the newline)
      expect(controller.selection.extentOffset, 18);

      controller.dispose();
    });

    test('onKey handles Shift+End and Shift+Home to expand selection', () async {
      final controller = GlslCodeController(language: glsl);
      controller.loadCode('    float x = 1.0;');
      controller.selection = const TextSelection.collapsed(offset: 4);

      await simulateKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      final resultEnd = controller.onKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.end,
          logicalKey: LogicalKeyboardKey.end,
          timeStamp: Duration.zero,
        ),
      );
      expect(resultEnd, KeyEventResult.handled);
      expect(controller.selection.baseOffset, 4);
      expect(controller.selection.extentOffset, 18);

      final resultHome1 = controller.onKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.home,
          logicalKey: LogicalKeyboardKey.home,
          timeStamp: Duration.zero,
        ),
      );
      expect(resultHome1, KeyEventResult.handled);
      expect(controller.selection.baseOffset, 4);
      expect(controller.selection.extentOffset, 4);

      final resultHome2 = controller.onKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.home,
          logicalKey: LogicalKeyboardKey.home,
          timeStamp: Duration.zero,
        ),
      );
      expect(resultHome2, KeyEventResult.handled);
      expect(controller.selection.baseOffset, 4);
      expect(controller.selection.extentOffset, 0);

      await simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft);
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
