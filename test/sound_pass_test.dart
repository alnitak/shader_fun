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

    test('wrapSoundShaderGlsl uses sample rounding and includes biased st_texture', () {
      const soundCode = '''
vec2 mainSound( int samp, float time ) {
    return texture(iChannel0, vec2(0.5), 0.0).xy;
}
''';
      final wrapped = ImpellerCompiler.wrapSoundShaderGlsl(soundCode);
      expect(wrapped, contains('round(iBlockOffset * iSampleRate)'));
      expect(
        wrapped,
        contains('vec4 st_texture(sampler2D s, vec2 uv, float bias)'),
      );
    });

    test('SoundPassEngine.detectReactivePass distinguishes static and reactive passes', () {
      final staticPass = ShaderPass(
        type: PassType.sound,
        name: 'Sound',
        code: ShaderProject.defaultCodeForPass(PassType.sound),
      );
      expect(SoundPassEngine.detectReactivePass(staticPass), isFalse);

      final channelRefPass = ShaderPass(
        type: PassType.sound,
        name: 'Sound',
        code: '''
vec2 mainSound(int samp, float time) {
    return texelFetch(iChannel0, ivec2(0, 0), 0).xy;
}
''',
      );
      expect(SoundPassEngine.detectReactivePass(channelRefPass), isTrue);

      final customUniformPass = ShaderPass(
        type: PassType.sound,
        name: 'Sound',
        code: '''
uniform float uGain;
vec2 mainSound(int samp, float time) {
    return vec2(sin(440.0 * 6.2831 * time) * uGain);
}
''',
      );
      expect(SoundPassEngine.detectReactivePass(customUniformPass), isTrue);

      final commonUniformPass = ShaderPass(
        type: PassType.sound,
        name: 'Sound',
        code: ShaderProject.defaultCodeForPass(PassType.sound),
      );
      expect(
        SoundPassEngine.detectReactivePass(
          commonUniformPass,
          commonCode: 'uniform float uShared;\n',
        ),
        isTrue,
      );
    });

    test('Loads Bricks_Game.json, detects reactive BufferChannel sound, and compiles all passes', () async {
      final file = File('example/shaders/Bricks_Game.json');
      expect(file.existsSync(), isTrue, reason: 'Bricks_Game.json must exist');

      final project = ShaderProject.parseJsonString(file.readAsStringSync());

      expect(project.commonPass, isNotNull);
      expect(project.getPass(PassType.bufferA), isNotNull);
      expect(project.imagePass, isNotNull);
      expect(project.soundPass, isNotNull);

      final soundPass = project.soundPass!;
      final ch0 = soundPass.channels.isNotEmpty ? soundPass.channels[0] : null;
      expect(ch0, isA<BufferChannel>());
      expect((ch0 as BufferChannel).bufferIndex, 0);

      final commonCode = project.commonPass!.code;
      expect(
        SoundPassEngine.detectReactivePass(soundPass, commonCode: commonCode),
        isTrue,
      );

      for (final pass in [
        project.getPass(PassType.bufferA)!,
        project.imagePass!,
        soundPass,
      ]) {
        final result = await ImpellerCompiler.compile(
          shaderGlsl: pass.code,
          commonGlsl: commonCode,
          passType: pass.type,
        );
        expect(
          result.isSuccess,
          isTrue,
          reason: '${pass.name} compilation failed: ${result.errorMessage}',
        );
        expect(result.bundleBytes, isNotNull);
        expect(result.bundleBytes!.isNotEmpty, isTrue);
      }
    });

    test('Loads colliding_balls.json, verifies Common parameters, and compiles all passes', () async {
      final file = File('example/shaders/colliding_balls.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'colliding_balls.json must exist',
      );

      final project = ShaderProject.parseJsonString(file.readAsStringSync());

      expect(project.commonPass, isNotNull);
      expect(project.getPass(PassType.bufferA), isNotNull);
      expect(project.imagePass, isNotNull);
      expect(project.soundPass, isNotNull);

      final commonCode = project.commonPass!.code;
      expect(commonCode, contains('const int N ='));
      expect(commonCode, contains('const float mass ='));
      expect(commonCode, contains('const float initialSpeed ='));
      expect(commonCode, contains('const float ballRadius ='));
      expect(commonCode, contains('const float userBallRadius ='));
      expect(commonCode, contains('const float userBallMass ='));
      expect(commonCode, contains('const float friction ='));

      final soundPass = project.soundPass!;
      final ch0 = soundPass.channels.isNotEmpty ? soundPass.channels[0] : null;
      expect(ch0, isA<BufferChannel>());
      expect((ch0 as BufferChannel).bufferIndex, 0);

      expect(
        SoundPassEngine.detectReactivePass(soundPass, commonCode: commonCode),
        isTrue,
      );

      for (final pass in [
        project.getPass(PassType.bufferA)!,
        project.imagePass!,
        soundPass,
      ]) {
        final result = await ImpellerCompiler.compile(
          shaderGlsl: pass.code,
          commonGlsl: commonCode,
          passType: pass.type,
        );
        expect(
          result.isSuccess,
          isTrue,
          reason: '${pass.name} compilation failed: ${result.errorMessage}',
        );
        expect(result.bundleBytes, isNotNull);
        expect(result.bundleBytes!.isNotEmpty, isTrue);
      }
    });
  });
}
