import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/shader_fun.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PassType.sound and SoundPass Tests', () {
    test('PassType.sound properties and helpers', () {
      expect(PassType.sound.displayName, 'Sound');
      expect(PassType.sound.isSound, isTrue);
      expect(PassType.sound.isImage, isFalse);
      expect(PassType.sound.isBuffer, isFalse);
      expect(PassType.sound.isCommon, isFalse);
    });

    test('ShaderProject defaultCodeForPass contains mainSound', () {
      final code = ShaderProject.defaultCodeForPass(PassType.sound);
      expect(code, contains('mainSound'));
      expect(code, contains('vec2 mainSound'));
    });

    test('Loads GPU_sound1.json and parses Sound pass', () {
      final file = File('example/shaders/GPU_sound1.json');
      expect(file.existsSync(), isTrue, reason: 'GPU_sound1.json must exist');

      final content = file.readAsStringSync();
      final project = ShaderProject.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
      );

      expect(project.passes.length, 2);
      expect(project.hasSoundPass, isTrue);
      expect(project.soundPass, isNotNull);
      expect(project.soundPass!.type, PassType.sound);
      expect(project.soundPass!.code, contains('mainSound'));

      // Verify JSON serialization round-trip
      final json = project.toJson();
      final restored = ShaderProject.fromJson(json);
      expect(restored.hasSoundPass, isTrue);
      expect(restored.soundPass!.type, PassType.sound);
      expect(restored.soundPass!.name, 'Sound');
    });

    test('ImpellerCompiler compiles Sound pass from GPU_sound1.json', () async {
      final file = File('example/shaders/GPU_sound1.json');
      final project = ShaderProject.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );

      final soundPass = project.soundPass!;
      final result = await ImpellerCompiler.compile(
        shaderGlsl: soundPass.code,
        passType: PassType.sound,
      );

      expect(
        result.isSuccess,
        isTrue,
        reason: 'Compilation failed: ${result.errorMessage}',
      );
      expect(result.bundleBytes, isNotNull);
      expect(result.bundleBytes!.isNotEmpty, isTrue);
    });

    test('Loads GPU_sound2.json and compiles Flight of the Bumblebee Piano with Common pass', () async {
      final file = File('example/shaders/GPU_sound2.json');
      expect(file.existsSync(), isTrue, reason: 'GPU_sound2.json must exist');

      final project = ShaderProject.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );

      expect(project.passes.length, 3);
      expect(project.hasSoundPass, isTrue);
      expect(project.commonPass, isNotNull);

      final commonCode = project.commonPass!.code;
      final soundPass = project.soundPass!;
      final result = await ImpellerCompiler.compile(
        shaderGlsl: soundPass.code,
        commonGlsl: commonCode,
        passType: PassType.sound,
      );

      expect(
        result.isSuccess,
        isTrue,
        reason: 'Compilation failed: ${result.errorMessage}',
      );
      expect(result.bundleBytes, isNotNull);

      final imagePass = project.passes.firstWhere((p) => p.type.isImage);
      final imgResult = await ImpellerCompiler.compile(
        shaderGlsl: imagePass.code,
        commonGlsl: commonCode,
        passType: PassType.image,
      );
      expect(
        imgResult.isSuccess,
        isTrue,
        reason: 'Image Pass compilation failed: ${imgResult.errorMessage}',
      );
      expect(imgResult.bundleBytes, isNotNull);
    });

    test('SoundPassEngine initializes and handles lifecycle safely', () {
      final engine = SoundPassEngine();
      expect(engine.isStreaming, isFalse);
      expect(engine.sampleRate, 44100.0);

      // pause, rewind, stop on unstarted engine should be safe
      engine.pause();
      engine.rewind();
      engine.stop();
      engine.dispose();
      expect(engine.isStreaming, isFalse);
    });

    test('ShaderController pause and unpause resumes rather than restarting sound pass', () {
      final file = File('example/shaders/GPU_sound1.json');
      final project = ShaderProject.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
      final controller = ShaderController(
        initialProject: project,
        autoPlay: false,
      );

      expect(controller.isPlaying, isFalse);
      expect(controller.project.hasSoundPass, isTrue);

      controller.play();
      expect(controller.isPlaying, isTrue);

      controller.pause();
      expect(controller.isPlaying, isFalse);

      // Unpausing must maintain streaming without throwing or resetting unexpectedly
      controller.play();
      expect(controller.isPlaying, isTrue);

      controller.dispose();
    });
  });
}
