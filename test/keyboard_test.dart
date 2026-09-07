import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/shader_fun.dart';
import 'package:shader_fun/src/core/keyboard_state.dart';

void main() {
  group('ShaderToyKeyboardState', () {
    test('maps standard keys to JavaScript keyCodes', () {
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.backspace), 8);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.tab), 9);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.enter), 13);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.numpadEnter), 13);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.shift), 16);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.shiftLeft), 16);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.control), 17);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.alt), 18);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.space), 32);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.arrowLeft), 37);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.arrowUp), 38);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.arrowRight), 39);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.arrowDown), 40);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.keyA), 65);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.keyZ), 90);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.digit0), 48);
      expect(ShaderToyKeyboardState.logicalKeyToKeyCode(LogicalKeyboardKey.digit9), 57);
    });

    test('tracks key-down, key-press, and key-toggle states across frames', () {
      final kb = ShaderToyKeyboardState();
      expect(kb.hasActiveInput, isFalse);

      // 1. Press Backspace (keyCode 8)
      kb.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.backspace,
          logicalKey: LogicalKeyboardKey.backspace,
          timeStamp: Duration.zero,
        ),
      );

      expect(kb.hasActiveInput, isTrue);
      expect(kb.isKeyDown(8), isTrue);
      expect(kb.isKeyPressed(8), isTrue);
      expect(kb.isKeyToggled(8), isTrue);

      // Verify pixelData buffer layout
      final data1 = kb.pixelData;
      // Metal Row 0 (Toggle - Shadertoy row 2): offset = (0 * 256 + 8) * 4
      expect(data1[(0 * 256 + 8) * 4], 255);
      // Metal Row 1 (Press - Shadertoy row 1): offset = (1 * 256 + 8) * 4
      expect(data1[(1 * 256 + 8) * 4], 255);
      // Metal Row 2 (Down - Shadertoy row 0): offset = (2 * 256 + 8) * 4
      expect(data1[(2 * 256 + 8) * 4], 255);

      // 2. End frame clears key-press trigger
      kb.endFrame();
      expect(kb.isKeyDown(8), isTrue);
      expect(kb.isKeyPressed(8), isFalse);
      expect(kb.isKeyToggled(8), isTrue);

      final data2 = kb.pixelData;
      expect(data2[(1 * 256 + 8) * 4], 0);
      expect(data2[(2 * 256 + 8) * 4], 255);

      // 3. Release Backspace
      kb.handleKeyEvent(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.backspace,
          logicalKey: LogicalKeyboardKey.backspace,
          timeStamp: Duration.zero,
        ),
      );

      expect(kb.isKeyDown(8), isFalse);
      expect(kb.isKeyPressed(8), isFalse);
      expect(kb.isKeyToggled(8), isTrue); // Toggle persists

      // 4. Press Backspace again -> toggle flips to false
      kb.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.backspace,
          logicalKey: LogicalKeyboardKey.backspace,
          timeStamp: Duration.zero,
        ),
      );
      expect(kb.isKeyDown(8), isTrue);
      expect(kb.isKeyPressed(8), isTrue);
      expect(kb.isKeyToggled(8), isFalse); // Toggled off

      // 5. Reset
      kb.reset();
      expect(kb.hasActiveInput, isFalse);
      expect(kb.isKeyDown(8), isFalse);
      expect(kb.isKeyToggled(8), isFalse);
    });
  });

  group('KeyboardChannel JSON serialization', () {
    test('parses ctype: keyboard in fromJson and serializes in toJson', () {
      final json = {
        'Shader': {
          'ver': '0.1',
          'info': {'id': 'testKb', 'name': 'Test Keyboard'},
          'renderpass': [
            {
              'name': 'Image',
              'type': 'image',
              'code': 'void mainImage(out vec4 c, in vec2 f) { c = vec4(1.0); }',
              'inputs': [
                {
                  'id': 33,
                  'src': '',
                  'ctype': 'keyboard',
                  'channel': 1,
                  'sampler': {
                    'filter': 'nearest',
                    'wrap': 'clamp',
                    'vflip': 'false',
                  },
                }
              ],
            }
          ],
        }
      };

      final project = ShaderToyProject.fromJson(json);
      final pass = project.getPass(PassType.image);
      expect(pass, isNotNull);

      final ch1 = pass!.getChannel(1);
      expect(ch1, isNotNull);
      expect(ch1, isA<KeyboardChannel>());
      expect(ch1!.type, ChannelType.keyboard);
      expect(ch1.resolution.width, 256);
      expect(ch1.resolution.height, 3);

      final serialized = project.toJson();
      final renderpasses = (serialized['Shader'] as Map)['renderpass'] as List;
      final inputs = (renderpasses.first as Map)['inputs'] as List;
      expect(inputs.length, 1);
      final input = inputs.first as Map;
      expect(input['ctype'], 'keyboard');
      expect(input['channel'], 1);
    });
  });
}
