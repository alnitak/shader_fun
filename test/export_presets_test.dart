import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/shader_fun.dart';
// ignore: avoid_relative_lib_imports
import '../example/lib/shader_presets.dart';

void main() {
  test('export presets to example/assets/examples', () {
    final dir = Directory('example/assets/examples');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    File('example/assets/examples/raymarching_primitives.json')
        .writeAsStringSync(ShaderPresets.raymarchingPrimitives().toJsonString());

    File('example/assets/examples/audio_reactive_tunnel.json')
        .writeAsStringSync(ShaderPresets.audioReactiveWaves().toJsonString());

    File('example/assets/examples/temporal_feedback.json')
        .writeAsStringSync(ShaderPresets.multiPassFeedback().toJsonString());

    File('example/assets/examples/cosine_palette_fractal.json')
        .writeAsStringSync(ShaderPresets.cosinePaletteFractal().toJsonString());

    expect(File('example/assets/examples/raymarching_primitives.json').existsSync(), isTrue);
    expect(File('example/assets/examples/audio_reactive_tunnel.json').existsSync(), isTrue);
    expect(File('example/assets/examples/temporal_feedback.json').existsSync(), isTrue);
    expect(File('example/assets/examples/cosine_palette_fractal.json').existsSync(), isTrue);
    expect(File('example/assets/examples/mouse_paint_eroded_mountains.json').existsSync(), isTrue);
  });

  test('ShaderToyProject.exampleAssets contains preset filenames and can load via loadFromAsset', () async {
    expect(ShaderToyProject.exampleAssets, contains('mouse_paint_eroded_mountains.json'));
    expect(ShaderToyProject.exampleAssets, contains('raymarching_primitives.json'));
    expect(ShaderToyProject.exampleAssets, contains('audio_reactive_tunnel.json'));
    expect(ShaderToyProject.exampleAssets, contains('temporal_feedback.json'));
    expect(ShaderToyProject.exampleAssets, contains('cosine_palette_fractal.json'));

    // Test loadFromAsset with custom bundle
    final fakeBundle = _FakeAssetBundle({
      'assets/examples/test_shader.json': '''
{
  "Shader": {
    "ver": "0.1",
    "info": {
      "id": "test1",
      "name": "Test Asset Shader",
      "username": "tester",
      "description": "A test asset shader"
    },
    "renderpass": [
      {
        "name": "Image",
        "type": "image",
        "code": "void mainImage(out vec4 c, in vec2 f) { c = vec4(1.0); }"
      }
    ]
  }
}'''
    });

    final project = await ShaderToyProject.loadFromAsset('test_shader.json', bundle: fakeBundle);
    expect(project.name, 'Test Asset Shader');
    expect(project.author, 'tester');
    expect(project.description, 'A test asset shader');
    expect(project.passes.length, 1);
  });
}

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this._assets);
  final Map<String, String> _assets;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (_assets.containsKey(key)) {
      return _assets[key]!;
    }
    throw Exception('Asset not found: $key');
  }

  @override
  Future<ByteData> load(String key) async {
    throw UnimplementedError();
  }
}

