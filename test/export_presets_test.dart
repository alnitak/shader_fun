import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/shader_fun.dart';

void main() {
  test('all example preset assets parse into valid ShaderToyProject if present', () {
    final dir = Directory('example/assets/examples');
    if (!dir.existsSync()) return;
    for (final filename in ShaderToyProject.exampleAssets) {
      final file = File('example/assets/examples/$filename');
      if (!file.existsSync()) continue;
      final jsonContent = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final project = ShaderToyProject.fromJson(jsonContent);
      expect(project.name.isNotEmpty, isTrue);
      expect(project.passes.isNotEmpty, isTrue);
    }
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

