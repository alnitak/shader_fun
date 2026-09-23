import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/src/channels/audio_texture_provider.dart';
import 'package:shader_fun/src/channels/shader_channel.dart';
import 'package:shader_fun/src/core/shader_pass.dart';
import 'package:shader_fun/src/models/shader_project.dart';

void main() {
  group('ShaderProject Feature Detection Labels', () {
    test('detects mouse usage when iMouse is referenced in GLSL code', () {
      final projectWithMouse = ShaderProject(
        passes: [
          ShaderPass(
            name: 'Image',
            type: PassType.image,
            code:
                'void mainImage(out vec4 c, in vec2 f) { vec2 m = iMouse.xy; }',
          ),
        ],
      );
      expect(projectWithMouse.usesMouse, isTrue);

      final projectWithoutMouse = ShaderProject(
        passes: [
          ShaderPass(
            name: 'Image',
            type: PassType.image,
            code: 'void mainImage(out vec4 c, in vec2 f) { c = vec4(1.0); }',
          ),
        ],
      );
      expect(projectWithoutMouse.usesMouse, isFalse);
    });

    test('detects audio channel usage when SoLoudAudioChannel is present', () {
      final passWithAudioChannel = ShaderPass(
        name: 'Image',
        type: PassType.image,
        code: '',
      );
      passWithAudioChannel.setChannel(0, SoLoudAudioChannel());
      final projectWithAudio = ShaderProject(passes: [passWithAudioChannel]);
      expect(projectWithAudio.usesAudio, isTrue);
      expect(projectWithAudio.usesAudioChannel, isTrue);
      expect(projectWithAudio.hasSoundPass, isFalse);
      expect(projectWithAudio.usesMic, isFalse);
    });

    test('detects GPU sound when sound pass is present', () {
      final soundPass = ShaderPass(
        name: 'Sound',
        type: PassType.sound,
        code: 'vec2 mainSound(int samp, float time) { return vec2(0.0); }',
      );
      final projectWithSound = ShaderProject(passes: [soundPass]);
      expect(projectWithSound.hasSoundPass, isTrue);
      expect(projectWithSound.usesAudio, isTrue);
      expect(projectWithSound.usesAudioChannel, isFalse);
      expect(projectWithSound.usesMic, isFalse);
    });

    test('detects microphone usage when MicAudioChannel is present', () {
      final passWithMic = ShaderPass(
        name: 'Image',
        type: PassType.image,
        code: '',
      );
      passWithMic.setChannel(0, MicAudioChannel());
      final projectWithMic = ShaderProject(passes: [passWithMic]);
      expect(projectWithMic.usesMic, isTrue);
      expect(projectWithMic.usesAudio, isFalse);
    });

    test('detects keyboard keys usage when KeyboardChannel is present', () {
      final passWithKeys = ShaderPass(
        name: 'Image',
        type: PassType.image,
        code: '',
      );
      passWithKeys.setChannel(0, KeyboardChannel());
      final projectWithKeys = ShaderProject(passes: [passWithKeys]);
      expect(projectWithKeys.usesKeys, isTrue);
    });

    test(
      'detects texture usage when TextureChannel or CubeMapChannel is present',
      () {
        final passWithTexture = ShaderPass(
          name: 'Image',
          type: PassType.image,
          code: '',
        );
        passWithTexture.setChannel(0, TextureChannel(src: 'texture.png'));
        final projectWithTexture = ShaderProject(passes: [passWithTexture]);
        expect(projectWithTexture.usesTextures, isTrue);

        final passWithCube = ShaderPass(
          name: 'Image',
          type: PassType.image,
          code: '',
        );
        passWithCube.setChannel(0, CubeMapChannel(assetPaths: ['cube.png']));
        final projectWithCube = ShaderProject(passes: [passWithCube]);
        expect(projectWithCube.usesTextures, isTrue);

        final passWithoutTexture = ShaderPass(
          name: 'Image',
          type: PassType.image,
          code: '',
        );
        final projectWithoutTexture = ShaderProject(
          passes: [passWithoutTexture],
        );
        expect(projectWithoutTexture.usesTextures, isFalse);
      },
    );

    test('parses features correctly from JSON structure', () {
      const jsonStr = '''
      {
        "Shader": {
          "info": { "name": "Feature Test" },
          "renderpass": [
            {
              "name": "Image",
              "type": "image",
              "code": "void mainImage(out vec4 c, in vec2 f) { vec2 m = iMouse.xy; }",
              "inputs": [
                { "channel": 0, "ctype": "keyboard" },
                { "channel": 1, "ctype": "music", "src": "song.mp3" },
                { "channel": 2, "ctype": "mic" },
                { "channel": 3, "ctype": "texture", "src": "test.png" }
              ],
              "outputs": []
            }
          ]
        }
      }
      ''';

      final project = ShaderProject.parseJsonString(jsonStr);
      expect(project.usesMouse, isTrue);
      expect(project.usesAudio, isTrue);
      expect(project.usesAudioChannel, isTrue);
      expect(project.hasSoundPass, isFalse);
      expect(project.usesMic, isTrue);
      expect(project.usesKeys, isTrue);
      expect(project.usesTextures, isTrue);
    });

    test('parses GPU sound pass correctly from JSON structure', () {
      const jsonStr = '''
      {
        "Shader": {
          "info": { "name": "GPU Sound Test" },
          "renderpass": [
            {
              "name": "Image",
              "type": "image",
              "code": "void mainImage(out vec4 c, in vec2 f) { c = vec4(1.0); }",
              "inputs": [],
              "outputs": []
            },
            {
              "name": "Sound",
              "type": "sound",
              "code": "vec2 mainSound(int samp, float time) { return vec2(0.0); }",
              "inputs": [],
              "outputs": []
            }
          ]
        }
      }
      ''';

      final project = ShaderProject.parseJsonString(jsonStr);
      expect(project.hasSoundPass, isTrue);
      expect(project.usesAudio, isTrue);
      expect(project.usesAudioChannel, isFalse);
    });
  });
}
