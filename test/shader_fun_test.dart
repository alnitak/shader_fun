import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/shader_fun.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShaderToyUniforms', () {
    test('initializes with valid defaults and pack to Float32List', () {
      final uniforms = CommonUniforms(
        resolution: const Size(1920, 1080),
        time: 5.25,
        frame: 315,
        mouse: const Offset4(100, 200, 100, 200),
      );

      final floats = uniforms.toFloat32List();
      expect(floats.length, 32);
      expect(floats[0], 1920.0);
      expect(floats[1], 1080.0);
      expect(floats[3], 5.25);
      expect(floats[5], 315.0);
      expect(floats[8], 100.0);
      expect(floats[9], 200.0);
    });
  });

  ShaderProject createRaymarchingTestProject() {
    return ShaderProject(
      id: '4slGD4',
      name: 'Raymarching Primitives',
      author: 'Inigo Quilez',
      passes: [
        ShaderPass(
          type: PassType.image,
          name: 'Image',
          code: '''// Raymarching Primitives
float sdSphere(vec3 p, float s) { return length(p) - s; }
float sdPlane(vec3 p) { return p.y; }
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(1.0);
}''',
        ),
      ],
    );
  }

  ShaderProject createFeedbackTestProject() {
    final bufferPass = ShaderPass(
      type: PassType.bufferA,
      name: 'Buffer A',
      code: 'void mainImage(out vec4 fragColor, in vec2 fragCoord) { fragColor = vec4(0.0); }',
    );
    bufferPass.setChannel(0, BufferChannel(bufferIndex: 0));
    final imagePass = ShaderPass(
      type: PassType.image,
      name: 'Image',
      code: 'void mainImage(out vec4 fragColor, in vec2 fragCoord) { fragColor = vec4(1.0); }',
    );
    imagePass.setChannel(0, BufferChannel(bufferIndex: 0));
    return ShaderProject(
      id: 'feedback_test',
      name: 'Feedback Test',
      passes: [bufferPass, imagePass],
    );
  }

  group('ShaderToyProject JSON Format', () {
    test(
      'serializes and deserializes correctly matching ShaderToy JSON structure',
      () {
        final original = createRaymarchingTestProject();
        final jsonMap = original.toJson();

        expect(jsonMap.containsKey('Shader'), isTrue);
        final shader = jsonMap['Shader'] as Map<String, dynamic>;
        expect(shader['info']['id'], '4slGD4');
        expect(shader['info']['name'], 'Raymarching Primitives');
        expect(shader['renderpass'] is List, isTrue);

        final jsonString = original.toJsonString();
        final parsed = ShaderProject.parseJsonString(jsonString);

        expect(parsed.id, '4slGD4');
        expect(parsed.name, 'Raymarching Primitives');
        expect(parsed.passes.length, original.passes.length);
        expect(parsed.passes.first.type, PassType.image);
        expect(parsed.passes.first.code, contains('mainImage'));
      },
    );

    test('multi-pass feedback project serializes channels and passes', () {
      final project = createFeedbackTestProject();
      final jsonMap = project.toJson();
      final parsed = ShaderProject.fromJson(jsonMap);

      expect(parsed.passes.length, 2);
      expect(parsed.passes.any((p) => p.type == PassType.bufferA), isTrue);
      expect(parsed.passes.any((p) => p.type == PassType.image), isTrue);

      final bufferA = parsed.passes.firstWhere(
        (p) => p.type == PassType.bufferA,
      );
      expect(bufferA.channels[0], isNotNull);
      expect(bufferA.channels[0]?.type, ChannelType.buffer);
    });
  });

  group('AudioChannel Texture Generator', () {
    test('generates audio texture pixel buffer conforming to spec', () {
      final channel = SoLoudAudioChannel();
      expect(channel.resolution.width, kAudioTextureWidth.toDouble());
      expect(channel.resolution.height, kAudioTextureHeight.toDouble());
      expect(
        channel.pixelData.length,
        kAudioTextureWidth * kAudioTextureHeight * 4,
      );

      // Update audio data with test FFT and Wave buffers
      final testFft = Float32List(kAudioTextureWidth);
      testFft[0] = 0.8;
      final testWave = Float32List(kAudioTextureWidth);
      testWave[0] = 0.5; // [-1.0, 1.0] -> normalized to 0.75
      channel.updateAudioData(newFft: testFft, newWave: testWave);

      // Row 0: FFT magnitude in R, G, B channels
      expect(channel.pixelData[0], greaterThan(0));
      expect(channel.pixelData[3], 255); // Alpha is 255

      // Row 1: Waveform amplitude
      final row1Offset = kAudioTextureWidth * 4;
      expect(channel.pixelData[row1Offset], greaterThan(0));
      expect(channel.pixelData[row1Offset + 3], 255);
    });
  });

  group('ShaderToyController', () {
    test('manages playback state and pass navigation', () async {
      final project = createFeedbackTestProject();
      final controller = ShaderController(
        initialProject: project,
        initialResolution: const Size(800, 450),
      );

      expect(controller.isPlaying, isFalse);
      expect(controller.activePassIndex, 0);
      expect(controller.activePass?.type, PassType.bufferA);

      controller.setActivePass(1);
      expect(controller.activePassIndex, 1);
      expect(controller.activePass?.type, PassType.image);

      controller.play();
      expect(controller.isPlaying, isTrue);

      controller.pause();
      expect(controller.isPlaying, isFalse);

      controller.rewind();
      expect(controller.time, 0.0);
      expect(controller.frame, 0);

      await controller.renderSingleFrame();
      controller.dispose();
    });

    test('updateActivePassCode updates pass code and re-renders', () {
      final project = createRaymarchingTestProject();
      final controller = ShaderController(
        initialProject: project,
        initialResolution: const Size(800, 450),
      );

      controller.updateActivePassCode(
        'void mainImage() { fragColor = vec4(1.0, 0.0, 0.0, 1.0); }',
      );
      expect(controller.activePass?.code, contains('1.0, 0.0, 0.0'));
      controller.dispose();
    });

    test('compile with invalid sourceCode does not mutate active pass code on failure', () async {
      final project = createRaymarchingTestProject();
      final originalCode = project.passes.first.code;
      final controller = ShaderController(
        initialProject: project,
        initialResolution: const Size(800, 450),
      );

      // Attempt to compile broken GLSL code
      final success = await controller.compile(
        sourceCode: 'invalid GLSL syntax !!!',
      );
      expect(success, isFalse);
      expect(controller.hasError, isTrue);
      // Ensure the active pass code was not overwritten with the broken code
      expect(controller.activePass?.code, equals(originalCode));
      controller.dispose();
    });
  });

  group('ShaderCodeEvaluator', () {
    test('extracts direct fragColor assignment', () {
      const code =
          'void mainImage() { fragColor = vec4(1.0, 0.5, 0.25, 1.0); }';
      final color = ShaderCodeEvaluator.extractDirectFragColor(code);
      expect(color, isNotNull);
      expect((color!.a * 255).round(), 255);
      expect((color.r * 255).round(), 255);
      expect((color.g * 255).round(), 128);
      expect((color.b * 255).round(), 64);
    });

    test('parses dynamic audio tunnel config from modified GLSL code', () {
      const code = '''
        void mainImage(out vec4 fragColor, in vec2 fragCoord) {
          float tunnel = sin(25.0 * r - iTime * 8.0 + fft * 5.0);
          float waveLine = 1.0 - smoothstep(0.0, 0.02, abs(uv.y - (wave - 0.5) * 1.5));
          col += vec3(1.0, 0.0, 0.0) * waveLine * 4.0;
        }
      ''';
      final config = ShaderCodeEvaluator.parseAudioTunnelConfig(code);
      expect(config.tunnelFrequency, 25.0);
      expect(config.tunnelSpeed, 8.0);
      expect(config.fftMultiplier, 5.0);
      expect(config.waveIntensity, 4.0);
      expect(config.waveAmplitudeMultiplier, 1.5);
      expect(config.waveLineColor, const Color(0xFFFF0000)); // Bright red
    });

    test('parses dynamic raymarching config from modified GLSL code', () {
      const code = '''
        float map(vec3 p) {
          float d = min(sdPlane(p), sdSphere(p - vec3(1.0, 2.0, 3.0), 2.5));
          return d;
        }
        void mainImage() {
          float an = 1.5 * iTime;
          col = vec3(0.1, 0.9, 0.2) * dif + vec3(0.4, 0.3, 0.5) * amb;
        }
      ''';
      final config = ShaderCodeEvaluator.parseRaymarchingConfig(code);
      expect(config.spheres.length, 1);
      expect(config.spheres.first.radius, 2.5);
      expect(config.spheres.first.center.dx, 1.0);
      expect(config.spheres.first.center.dy, 2.0);
      expect(config.rotationSpeed, 1.5);
      expect(
        (config.diffuseColor.g * 255).round(),
        greaterThan(200),
      ); // Vibrant green
    });

    test('evaluates raymarching and audio tunnel shaders to images', () async {
      final uniforms = CommonUniforms(
        resolution: const Size(800, 450),
        time: 1.0,
      );

      final rmImg = await ShaderCodeEvaluator.evaluateRaymarchingShader(
        code: '''
float sdSphere(vec3 p, float s) { return length(p) - s; }
float sdPlane(vec3 p) { return p.y; }
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(0.8, 0.7, 0.6, 1.0);
}
''',
        uniforms: uniforms,
        width: 800,
        height: 450,
      );
      expect(rmImg, isNotNull);
      expect(rmImg!.width, 120);
      rmImg.dispose();

      final audioImg = await ShaderCodeEvaluator.evaluateAudioTunnelShader(
        code: '''
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(0.0, 1.0, 1.0, 1.0);
}
''',
        uniforms: uniforms,
        width: 800,
        height: 450,
      );
      expect(audioImg, isNotNull);
      expect(audioImg!.width, 120);
      audioImg.dispose();
    });

    test('ImpellerCompiler wraps GLSL with UBO, samplers, and #line 1', () {
      const userCode =
          'void mainImage(out vec4 fragColor, in vec2 fragCoord) { fragColor = texture(iChannel0, fragCoord); }';
      final wrapped = ImpellerCompiler.wrapShaderGlsl(userCode);

      expect(wrapped, contains('#version 460 core'));
      expect(wrapped, contains('uniform FrameInfo'));
      expect(wrapped, contains('uniform sampler2D iChannel0'));
      expect(wrapped, isNot(contains('uniform sampler2D iChannel1')));
      expect(wrapped, contains('#line 1'));
      expect(wrapped, contains(userCode));
      expect(wrapped, contains('mainImage(fragColor, fragCoord);'));
    });

    test('ImpellerCompiler shaderUsesChannel detects used channels and ignores comments', () {
      const code = '''
        // iChannel1 is in a comment
        /* iChannel2 in block comment */
        void mainImage(out vec4 fragColor, in vec2 fragCoord) {
          fragColor = texture(iChannel0, fragCoord);
        }
      ''';

      expect(ImpellerCompiler.shaderUsesChannel(code, 0), isTrue);
      expect(ImpellerCompiler.shaderUsesChannel(code, 1), isFalse);
      expect(ImpellerCompiler.shaderUsesChannel(code, 2), isFalse);
      expect(ImpellerCompiler.shaderUsesChannel(code, 3), isFalse);
    });

    test('ShaderToyProject serializes and restores src for URLs, local paths, and assets', () {
      final project = ShaderProject(
        name: 'Source Test',
        passes: [
          ShaderPass(
            name: 'Image',
            type: PassType.image,
            code: 'void mainImage(out vec4 c, in vec2 u) { c = vec4(1.0); }',
            channels: [
              SoLoudAudioChannel(src: 'assets/audio/neon_pulse.mp3'),
              TextureChannel(src: 'https://example.com/texture.png'),
              SoLoudAudioChannel(src: '/Users/deimos/Music/song.wav'),
              BufferChannel(bufferIndex: 0),
            ],
          ),
        ],
      );

      final jsonMap = project.toJson();
      final parsed = ShaderProject.fromJson(jsonMap);

      expect(parsed.passes.first.channels[0]?.type, ChannelType.audio);
      final ch0 = parsed.passes.first.channels[0] as SoLoudAudioChannel;
      expect(ch0.src, 'assets/audio/neon_pulse.mp3');

      final ch1 = parsed.passes.first.channels[1] as TextureChannel;
      expect(ch1.src, 'https://example.com/texture.png');

      final ch2 = parsed.passes.first.channels[2] as SoLoudAudioChannel;
      expect(ch2.src, '/Users/deimos/Music/song.wav');
    });

    test('ShaderToyProject parses concise settings JSON format', () {
      final jsonMap = {
        'name': 'Concise Shader',
        'imageCode': 'void mainImage(out vec4 fragColor, in vec2 fragCoord) { fragColor = vec4(1.0); }',
        'buffers': {
          'A': 'void mainImage(out vec4 col, in vec2 uv) { col = vec4(0.0); }',
        },
        'channels': {
          '0': {'type': 'audio', 'src': 'assets/audio/track.mp3'},
          '1': {'type': 'mic'},
          '2': {'type': 'texture', 'src': 'https://example.com/art.jpg'},
        },
      };

      final project = ShaderProject.fromSettingsJson(jsonMap);
      expect(project.name, 'Concise Shader');
      expect(project.passes.length, 2);
      expect(project.passes.first.channels[0]?.type, ChannelType.audio);
      expect(project.passes.first.channels[1]?.type, ChannelType.mic);
      expect(project.passes.first.channels[2]?.type, ChannelType.texture);
    });

    test('ShaderToyController manages channels and source code', () {
      final controller = ShaderController();
      controller.setImagePassCode(
        'void mainImage(out vec4 c, in vec2 u) { c = vec4(1.0); }',
      );
      expect(controller.imagePassCode, contains('vec4(1.0)'));

      controller.setBufferChannel(0, PassType.bufferA);
      expect(controller.getChannel(0), isA<BufferChannel>());

      controller.removeChannel(0);
      expect(controller.getChannel(0), isNull);

      controller.dispose();
    });

    test('ShaderToyController supports package:listen ChangeNotifier and ValueNotifiers', () {
      final controller = ShaderController();
      int controllerNotifications = 0;
      int isPlayingNotifications = 0;

      controller.addListener(() {
        controllerNotifications++;
      });

      controller.isPlayingNotifier.addListener(() {
        isPlayingNotifications++;
      });

      controller.play();
      expect(controller.isPlaying, isTrue);
      expect(controller.isPlayingNotifier.value, isTrue);
      expect(isPlayingNotifications, 1);
      expect(controllerNotifications, greaterThanOrEqualTo(1));

      controller.pause();
      expect(controller.isPlaying, isFalse);
      expect(isPlayingNotifications, 2);

      controller.dispose();
    });

    test(
      'ShaderPass and AudioChannel handle multiple dispose calls idempotently',
      () {
        final pass = ShaderPass(
          type: PassType.image,
          name: 'Image',
          code: 'void mainImage(out vec4 c, in vec2 u) {}',
        );
        final ch1 = SoLoudAudioChannel();
        pass.setChannel(0, ch1);

        // Replacing with another channel triggers disposal of ch1
        final ch2 = SoLoudAudioChannel();
        pass.setChannel(0, ch2);
        expect(ch1.isDisposed, isTrue);

        // Calling dispose again directly must be an idempotent no-op (no Bad state exception)
        ch1.dispose();
        expect(ch1.isDisposed, isTrue);

        pass.dispose();
        expect(ch2.isDisposed, isTrue);
      },
    );
  });
}
