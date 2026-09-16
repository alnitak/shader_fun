import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_fun/shader_fun.dart';
import 'package:shader_fun/src/channels/shader_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Test loading TextureChannel asset with raw decoding and fallback', () async {
    final channel = TextureChannel(src: 'assets/2d_texture/rgba_noise_medium.png');
    final img = await channel.loadImage();
    expect(img, isNotNull);
    expect(channel.rawRgbaBytes, isNotNull);
    expect(channel.imageWidth, 256);
    expect(channel.imageHeight, 256);
  });

  test('ShaderProject.loadFromAsset loads and parses JSON correctly', () async {
    final mockBundle = _MockAssetBundle({
      'shaders/test_shader.json': '''
{
  "Shader": {
    "info": {
      "id": "test_id",
      "name": "Test Shader",
      "username": "Tester",
      "description": "A test shader description"
    },
    "renderpass": [
      {
        "name": "Image",
        "type": "image",
        "code": "void mainImage(out vec4 fragColor, in vec2 fragCoord) { fragColor = vec4(1.0); }"
      }
    ]
  }
}
''',
      'assets/examples/fallback_shader.json': '''
{
  "Shader": {
    "info": {
      "name": "Fallback Shader"
    },
    "renderpass": []
  }
}
''',
    });

    // Load with exact path containing slash
    final p1 = await ShaderProject.loadFromAsset(
      'shaders/test_shader.json',
      bundle: mockBundle,
    );
    expect(p1.name, 'Test Shader');
    expect(p1.author, 'Tester');
    expect(p1.passes.length, 1);

    // Load with simple file name resolving to shaders/
    final p2 = await ShaderProject.loadFromAsset(
      'test_shader.json',
      bundle: mockBundle,
    );
    expect(p2.name, 'Test Shader');

    // Load with simple file name resolving to assets/examples/
    final p3 = await ShaderProject.loadFromAsset(
      'fallback_shader.json',
      bundle: mockBundle,
    );
    expect(p3.name, 'Fallback Shader');
  });
}

class _MockAssetBundle extends Fake implements AssetBundle {
  _MockAssetBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final content = assets[key];
    if (content == null) {
      throw Exception('Asset not found: $key');
    }
    return content;
  }
}

