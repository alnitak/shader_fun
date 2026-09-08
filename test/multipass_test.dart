import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/src/channels/shader_channel.dart';
import 'package:shader_fun/src/controller/shadertoy_controller.dart';
import 'package:shader_fun/src/core/shader_pass.dart';
import 'package:shader_fun/src/models/shadertoy_json.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Multi-pass pipeline & BufferChannel resolution', () {
    test('correctly maps Shadertoy buffer IDs and previz paths to bufferIndex', () {
      final file = File('example/shaders/mouse_paint_eroded_mountains.json');
      expect(file.existsSync(), isTrue);

      final jsonMap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final project = ShaderToyProject.fromJson(jsonMap);

      // Verify passes exist
      expect(project.hasPass(PassType.bufferA), isTrue);
      expect(project.hasPass(PassType.bufferB), isTrue);
      expect(project.hasPass(PassType.bufferC), isTrue);
      expect(project.hasPass(PassType.image), isTrue);

      // Buffer A samples Buffer A (self-reference, id: 257)
      final passA = project.getPass(PassType.bufferA)!;
      expect(passA.channels[0], isA<BufferChannel>());
      final chA0 = passA.channels[0] as BufferChannel;
      expect(chA0.bufferIndex, 0, reason: 'Buffer A channel 0 should point to Buffer A (0)');

      // Buffer B samples Buffer A (id: 257)
      final passB = project.getPass(PassType.bufferB)!;
      expect(passB.channels[0], isA<BufferChannel>());
      final chB0 = passB.channels[0] as BufferChannel;
      expect(chB0.bufferIndex, 0, reason: 'Buffer B channel 0 should point to Buffer A (0)');

      // Image samples Buffer B (id: 258) on channel 0, and Buffer C (id: 259) on channel 1
      final imagePass = project.getPass(PassType.image)!;
      expect(imagePass.channels[0], isA<BufferChannel>());
      final chImg0 = imagePass.channels[0] as BufferChannel;
      expect(chImg0.bufferIndex, 1, reason: 'Image channel 0 should point to Buffer B (1)');

      expect(imagePass.channels[1], isA<BufferChannel>());
      final chImg1 = imagePass.channels[1] as BufferChannel;
      expect(chImg1.bufferIndex, 2, reason: 'Image channel 1 should point to Buffer C (2)');
    });

    test('compileAllPasses compiles all passes of Mouse Paint Eroded Mountains', () async {
      final file = File('example/shaders/mouse_paint_eroded_mountains.json');
      final jsonMap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final project = ShaderToyProject.fromJson(jsonMap);

      final controller = ShaderToyController(
        initialProject: project,
        autoPlay: false,
      );

      final success = await controller.compileAllPasses();
      expect(controller.lastError, isNull);
      expect(success, isTrue);

      controller.dispose();
    });
  });
}
